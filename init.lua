--- === TextExpansion ===
---
--- TextExpansion helps you eliminate repetitive typing. It does this by replacing any known
--- **abbreviation** with a corresponding **expansion** as you type.
---
--- As installed, TextExpansion does _nothing_; you need to supply your own expansions (see
--- below) that should be expanded.
---
--- TODO: Examples
---
--- TODO: Download link
---
--- Functionality inspired by AHK's [hotstrings](https://autohotkey.com/docs/Hotstrings.htm)

local obj={}
obj.__index = obj

-- Internal function used to find our location, so we know where to load files from
local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end
obj.spoonPath = script_path()

local circularbuffer = dofile(obj.spoonPath.."/circularbuffer.lua")
local StateManager = dofile(obj.spoonPath.."/statemanager.lua")

-- Dependencies
local eventtap = hs.eventtap
local keyMap = hs.keycodes.map
local doAfter = hs.timer.doAfter

-- Metadata
obj.name = "TextExpansion"
obj.version = "0.1"
obj.author = "Shayne Holmes"
obj.homepage = "https://github.com/shayneholmes/hammerspoon-TextExpansion"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- TextExpansion.defaults
--- Variable
--- Table containing options to be applied to expansions by default. The following keys are valid:
--- * **`backspace`** (default true): Use backspaces to remove the abbreviation when it is expanded.
--- * **`casesensitive`** (default false): Case of abbreviation must match exactly
--- * **`internal`** (default false): Trigger the expansion even when the abbreviation is inside another word
--- * **`matchcase`** (default true): If you type an abbreviation in `ALL CAPS` or `FirstCaps`, the expansion will be typed in the same manner; ignored when `casesensitive` is set
--- * **`priority`** (default 0): A number that specifies which of two expansions to use in case of collision. Expansions with higher numbers will be preferred.
--- * **`resetrecognizer`** (default false): When an abbreviation is completed, reset the recognizer.
--- * **`sendcompletionkey`** (default true): When an abbreviation is completed, send the completion key along with it.
--- * **`waitforcompletionkey`** (default true): Wait for a completion key before expanding the abbreviation.
obj.defaults = {
  backspace = true, -- remove the abbreviation
  casesensitive = false, -- case of abbreviation must match exactly
  internal = false, -- trigger even inside another word
  matchcase = true, -- if you type an abbreviation in `ALL CAPS` or `FirstCaps`, the expansion will be typed in the same manner; ignored when `casesensitive` is set
  priority = 0, -- explicit override for priority between conflicting abbreviations
  resetrecognizer = false, -- reset the recognizer after each completion
  sendcompletionkey = true, -- send the completion key
  waitforcompletionkey = true, -- wait for a completion key
  expansion = nil, -- not in default, must be defined
  abbreviation = nil, -- programmatically populated at start
  output = nil, -- populated at trigger time
  trigger = nil, -- populated at trigger time
}

--- TextExpansion.specialKeys
--- Variable
--- Table containing information about special keys. It contains the following tables within it:
---
--- * The `specialKeys.reset` table contains the names of keys that should reset any abbreviation in progress. (For example, typing `da<left>te` does not trigger an expansion of "date".)
---
--- * The `specialKeys.delete` table contains the names of keys that should delete the last character in an abbreviation in progress.
---
--- The value of each entry in these tables is a valid key name from `hs.keycodes.map`
---
--- By default:
--- ```
--- TextExpansion.specialKeys = {
---   reset = {
---     "escape", "help", "forwarddelete",
---     "left", "right", "up", "down",
---     "home", "end", "pageup", "pagedown",
---   },
---   delete = {
---     "delete",
---   },
--- }
--- ```
obj.specialKeys = {
  reset = {
    "escape", "help", "forwarddelete",
    "left", "right", "up", "down",
    "home", "end", "pageup", "pagedown",
  },
  delete = {
    "delete",
  },
}

--- TextExpansion.timeoutSeconds
--- Variable
--- Length of time, in seconds, to wait before timeout. If no new events arrive in that time period, TextExpansion will forget the abbreviation underway.
---
--- A non-positive value disables the timeout functionality entirely.
obj.timeoutSeconds = 10

local maxAbbreviationLength = 40
local maxStatesUndo = 10

-- Internal variables
local initialized = false
local buffer
local keyWatcher
local keyActions -- generated on start() from specialKeys
local statemanager -- generated on start()
local pendingTimer
local timeoutSeconds

local function merge_tables(default, override)
  local combined = {}
  for k,v in pairs(default) do combined[k] = v end
  for k,v in pairs(override) do combined[k] = v end
  return combined
end

local function generateKeyActions(self)
  keyActions = {}
  for action,keyTable in pairs(self.specialKeys) do
    for _,keyName in pairs(keyTable) do
      keyActions[keyMap[keyName]] = action
    end
  end
end

-- compare two expansions, and return true if the first one is "greater than" (higher precedence) the other
local function expansion_gt(x1, x2)
  -- x1 is guaranteed to exist
  -- if x2 is nil, this one wins
  if not x2 then return true end -- must be present to win
  -- higher priority wins
  if x1.priority ~= x2.priority then return x1.priority > x2.priority end
  -- longer abbreviation wins
  local x1len = x1.abbreviation:len()
  local x2len = x2.abbreviation:len()
  if x1len ~= x2len then return x1len > x2len end
  -- case sensitive wins
  if x1.casesensitive ~= x2.casesensitive then return x1.casesensitive end
  -- or tie; undefined behavior (but with an error message)
  print(("Error: can't differentiate between expansions '%s' and '%s'!"):format(x1.abbreviation, x2.abbreviation))
  return false
end

local function generateExpansions(self, xs)
  self.defaults.takesPriorityOver = expansion_gt -- this comparison needs to be in there, regardless of what defaults have been set
  local expansion_metatable = { __index = self.defaults }
  local expansions = {}
  for k,v in pairs(xs) do
    if type(v) ~= "table" then
      v = {["expansion"] = v}
    end
    v.abbreviation = k
    expansions[#expansions+1] = setmetatable(v, expansion_metatable)
  end
  return expansions
end

local function resetAbbreviation()
  buffer:clear()
  statemanager:clear()
end

local function printBuffer()
  print(("Buffer: %s"):format(utf8.char(table.unpack(buffer:getAll()))))
end

local endChars = "-@()[]{}:;'\"/\\,.?!\r\n \t"

local endCharsArray = {}
for _,code in utf8.codes(endChars) do
  endCharsArray[code] = true
end

local function isEndChar(code)
  return endCharsArray[code]
end

local function evaluateExpansion(expansion)
  -- place the result in output
  local output = expansion.expansion
  if type(output) == "function" then
    local _, result = pcall(output)
    if not _ then
      print("~~ expansion for '" .. expansion.abbreviation .. "' gave an error of " .. result)
      result = nil
    end
    output = result or "" -- nil values are okay
  end
  return output;
end

local function getAbbreviation(x)
  local length = #x.abbreviation
  if x.waitforcompletionkey then length = length + 1 end
  local actual = utf8.char(table.unpack(buffer:getEnding(length)))
  return actual
end

local function sendBackspaces(expansion)
  if expansion.backspace then
    local backspaces = utf8.len(expansion.abbreviation)
    if not expansion.waitforcompletionkey then
      backspaces = backspaces - 1 -- part of the abbreviation hasn't been output, so don't backspace that
    end
    for i = 1, backspaces, 1 do
      eventtap.keyStroke({}, "delete", 0)
    end
  end
end

local function generateKeystrokes(expansion)
  local output = expansion.output
  if output then
    keyWatcher:stop()
    sendBackspaces(expansion)
    eventtap.keyStrokes(output)
    keyWatcher:start()
  end
end

local function resetAbbreviationTimeout()
  resetAbbreviation()
end

local function restartInactivityTimer()
  if timeoutSeconds <= 0 then return end
  if pendingTimer then pendingTimer:stop() end
  pendingTimer = doAfter(timeoutSeconds, function() resetAbbreviationTimeout() end)
end

local CASE_NONE = 0
local CASE_ALL_CAPS = 1
local CASE_FIRST_CAP = 2
local function getcase(str)
  local upper = str:upper()
  local lower = str:lower()
  local caseables = 0
  local firstupper = false
  local anylower = false
  for i=1,#str do
    local upper = upper:sub(i,i)
    if upper ~= lower:sub(i,i) then
      caseables = caseables + 1
      local isupper = upper == str:sub(i,i)
      if caseables == 1 then
        firstupper = isupper
      end
      if not isupper then
        anylower = true
        break
      end
    end
  end
  if firstupper then
    if caseables > 1 and not anylower then
      return CASE_ALL_CAPS
    else
      return CASE_FIRST_CAP
    end
  else
    return CASE_NONE
  end
end

local function makeallcaps(str)
  return str:upper()
end

local function makefirstcap(str)
  return str:sub(1,1):upper() .. str:sub(2)
end

-- modify output depending on trigger
local function matchcase(trigger, output)
  local case = getcase(trigger)
  if case == CASE_ALL_CAPS then
    return makeallcaps(output)
  elseif case == CASE_FIRST_CAP then
    return makefirstcap(output)
  else
    return output
  end
end

local function hydrateexpansion(x)
  x.trigger = getAbbreviation(x)
  x.output = evaluateExpansion(x)
  if x.matchcase and not x.casesensitive then
    x.output = matchcase(x.trigger, x.output)
  end
end

local function processexpansion(expansion)
  if not expansion then return end
  if not expansion.waitforcompletionkey -- the key event we're holding now is part of the abbreviation, it should stick with the abbreviation
    and not expansion.backspace -- if we were backspacing, the abbreviation wouldn't be around to be examined
    and expansion.sendcompletionkey -- if we weren't sending it, the order wouldn't matter, now would it?
  then
    -- give time for the other event to be processed first
    doAfter(0, function() generateKeystrokes(expansion) end)
  else
    generateKeystrokes(expansion)
  end
end

function obj:handleEvent(ev)
  restartInactivityTimer()

  local keyCode = ev:getKeyCode()
  local keyAction = keyActions[keyCode] or "other"
  local eatAction = false -- pass the event on to the focused application
  if ev:getFlags().cmd then
    keyAction = "reset"
  end
  if keyAction == "reset" then
    resetAbbreviation()
  elseif keyAction == "delete" then -- delete the last character, go back to previous state
    buffer:pop()
    statemanager:rewindstate()
  else
    for p, c in utf8.codes(ev:getCharacters()) do -- might be multiple chars, e.g. when deadkeys are enabled
      buffer:push(c)
      statemanager:followedge(c)
      local expansion = statemanager:getMatchingExpansion()
      if expansion then
        hydrateexpansion(expansion)
        processexpansion(expansion)
        eatAction = eatAction or not expansion.sendcompletionkey -- true if any are true
        if expansion.resetrecognizer then resetAbbreviation() end
      end
    end
  end
  return eatAction
end

--- TextExpansion:setExpansions()
--- Method
--- Set the expansions that this TextExpansion object will recognize.
---
--- Pass in a table containing expansions, indexed by their abbreviations.
---
--- The index of each entry is a sequence of printable characters; this is the **abbreviation**.
---
--- The value of each entry represents the **expansion**. It is one of:
--- * A string value containing the expanded text
--- * A nullary function (no parameters) that returns the expanded text
--- * A table with the key "expansion" containing either of the above, alongside any of the options from `defaults`
---
--- A simple example:
--- ```
--- spoon.TextExpansion:setExpansions({
---   ["sig"] = "Sincerely, Foo",
---   ["dt"] = function() return os.date("%B %d, %Y") end,
---   ["hamm"] = {
---     expansion = "erspoon",
---     backspace = false,
---   },
--- })
--- ```
function obj:setExpansions(expansions)
  local xs = generateExpansions(self, expansions)
  statemanager = StateManager.new(xs, isEndChar, maxStatesUndo)
  resetAbbreviation()
  return self
end

--- TextExpansion:init()
--- Method
--- Read configuration and setup internal state.
---
--- You must make any changes to `TextExpansion.specialKeys` before this method is called; any further changes to it won't take effect until `init` is called again.
function obj:init()
  generateKeyActions(self)
  timeoutSeconds = self.timeoutSeconds
  buffer = circularbuffer.new(maxAbbreviationLength)
  keyWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(ev) return self:handleEvent(ev) end)
  self:setExpansions({})
  initialized = true
  return self
end

--- TextExpansion:start()
--- Method
--- Start the keyboard event watcher.
---
--- You must make any changes to `TextExpansion.expansions` and `TextExpansion.specialKeys` before this method is called; any further changes to them won't take effect until the watcher is started again.
function obj:start()
  assert(initialized, "Must be initialized before running")
  if keyWatcher:isEnabled() then
    print("Warning: watcher is already running! Restarting...")
    keyWatcher:stop()
  end
  keyWatcher:start()
  return self
end

--- TextExpansion:stop()
--- Method
--- Stop the keyboard event watcher.
function obj:stop()
  if not initialized then
    print("Warning: Not initialized.")
    return self
  end
  if not keyWatcher:isEnabled() then
    print("Warning: watcher is already stopped!")
    return self
  end
  keyWatcher:stop()
  return self
end

--- TextExpansion:isEnabled()
--- Method
--- Returns true if the keyboard event watcher is configured and active.
function obj:isEnabled()
  return initialized and keyWatcher:isEnabled()
end

function obj:resetAbbreviation()
  resetAbbreviation()
  return self
end

return obj
