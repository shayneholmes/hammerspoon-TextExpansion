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
--- * **`matchcase`** (default true): If you type an abbreviation in `ALL CAPS` or `First caps`, the expansion will be typed in the same manner; ignored when `casesensitive` is set
--- * **`priority`** (default 0): A number that specifies which of two expansions to use in case of collision. Expansions with higher numbers will be preferred.
--- * **`resetrecognizer`** (default true): When an abbreviation is completed, reset the recognizer.
--- * **`sendcompletionkey`** (default true): When an abbreviation is completed, send the completion key along with it.
--- * **`waitforcompletionkey`** (default true): Wait for a completion key before expanding the abbreviation.
obj.defaults = {
  backspace = true, -- remove the abbreviation
  casesensitive = false, -- case of abbreviation must match exactly
  internal = false, -- trigger even inside another word
  matchcase = true, -- if you type an abbreviation in `ALL CAPS` or `FirstCaps`, the expansion will be typed in the same manner; ignored when `casesensitive` is set
  priority = 0, -- explicit override for priority between conflicting abbreviations
  resetrecognizer = true, -- reset the recognizer after each completion
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
local debug
local keyWatcher
local keyActions -- generated on start() from specialKeys
local statemanager -- generated on start()
local pendingTimer
local timeoutSeconds

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
  -- x1 is guaranteed to exist, so if x2 is nil, this one wins; must be present to win!
  if not x2 then return true end
  -- strict equality is easy to check for and will save us some work
  if x1 == x2 then return false end
  -- higher explicit priority wins
  if x1.priority ~= x2.priority then return x1.priority > x2.priority end
  -- longer abbreviation wins (on the theory that they're more specific to a situation)
  local x1len = x1.abbreviation:len()
  local x2len = x2.abbreviation:len()
  if x1len ~= x2len then return x1len > x2len end
  -- abbreviation with a word boundary wins over internals
  if x1.internal ~= x2.internal then return not x1.internal end
  -- case sensitive wins
  if x1.casesensitive ~= x2.casesensitive then return x1.casesensitive end
  -- so, abbreviations and config are the functionally the same (but see below for last-ditch efforts); let's try comparing expansions, first lexicographically by type
  -- note that strings win over functions for now; maybe that's unfortunate
  local x1type = type(x1.expansion)
  local x2type = type(x2.expansion)
  if x1type ~= x2type then return x1type > x2type end
  -- expansion types are the same; let's try and compare expansion values
  local status, ret = pcall(function() if x1.expansion ~= x2.expansion then return x1.expansion > x2.expansion end end)
  if status then return ret end
  -- non-comparable expansions (e.g. two functions), and functionally identical configs and abbreviations, but we haven't tried lexically comparing the abbreviations; that's at least consistent
  local x1abbr = x1.abbreviation
  local x2abbr = x2.abbreviation
  if x1abbr ~= x2abbr then return x1abbr > x2abbr end
  -- the expansion values weren't comparable (e.g. two functions); let's convert the values to strings we can compare
  -- note that the comparison between functions is by address, which is non-deterministic across instances but at least consistent within a run
  local x1str = ("%s"):format(x1.expansion)
  local x2str = ("%s"):format(x2.expansion)
  if x1str ~= x2str then return x1str > x2str end
  -- now we *really* don't know what to do, since the abbreviation, expansion and config are the same; call them equal, which means their sort order is undefined behavior
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
  statemanager:reset()
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
  if debug then print(("Abbreviation interpreted: %s -> %s"):format(x.abbreviation,actual)) end
  return actual
end

local function debugTable(table)
  if debug and table then
    for k,v in pairs(table) do print(string.format("%s -> %s", k, v)) end
  end
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
  if debug then print("timed out") end
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
local function getCase(triggerString)
  local upper = triggerString:upper()
  local lower = triggerString:lower()
  local charsWithCase = 0 -- Number of characters that can be cased
  local firstUpper = false
  local anyLower = false
  for i=1,#triggerString do
    local upperChar = upper:sub(i,i)
    local lowerChar = lower:sub(i,i)
    if upperChar ~= lowerChar then
      local origChar = triggerString:sub(i,i)
      charsWithCase = charsWithCase + 1
      local isUpper = (origChar == upperChar)
      if charsWithCase == 1 then
        firstUpper = isUpper
      end
      if not isUpper then
        anyLower = true
        break
      end
    end
  end
  if firstUpper then
    if charsWithCase > 1 and not anyLower then
      return CASE_ALL_CAPS
    else
      return CASE_FIRST_CAP
    end
  else
    return CASE_NONE
  end
end

local function makeallcaps(expansionString)
  return expansionString:upper()
end

local function makefirstcap(expansionString)
  return expansionString:sub(1,1):upper() .. expansionString:sub(2)
end

-- modify output depending on trigger
local function matchcase(trigger, output)
  local case = getCase(trigger)
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
      local expansion = statemanager:followedge(c)
      if expansion then
        hydrateexpansion(expansion)
        debugTable(expansion)
        processexpansion(expansion)
        eatAction = eatAction or not expansion.sendcompletionkey -- true if any are true
        if expansion.resetrecognizer then resetAbbreviation() end
      end
    end
  end
  if debug then printBuffer() end
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
  if keywatcher and keyWatcher:isEnabled() then
    print("Warning: watcher is already running! Stopping...")
    keyWatcher:stop()
  end
  local xs = generateExpansions(self, expansions)
  statemanager = StateManager.new(xs, isEndChar, maxStatesUndo, debug)
  resetAbbreviation()
  return self
end

--- TextExpansion:init()
--- Method
--- Read configuration and setup internal state.
---
--- You must make any changes to `TextExpansion.specialKeys` before this method is called; any further changes to it won't take effect until `init` is called again.
function obj:init()
  if keywatcher and keyWatcher:isEnabled() then
    print("Warning: watcher is already running! Stopping...")
    keyWatcher:stop()
  end
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
  if debug then print("Starting keyboard event watcher.") end
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
  if debug then print("Stopping keyboard event watcher.") end
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

function obj:setDebug(val)
  if val then
    debug = true
  else
    debug = false
  end
  return self
end

return obj
