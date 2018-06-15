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

buffer = dofile(obj.spoonPath.."/circularbuffer.lua")

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

--- TextExpansion.expansions
--- Variable
--- Table containing expansions, indexed by their abbreviations.
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
--- spoon.TextExpansion.expansions = {
---   ["sig"] = "Sincerely, Foo",
---   ["dt"] = function() return os.date("%B %d, %Y") end,
---   ["hamm"] = {
---     expansion = "erspoon",
---     backspace = false,
---   },
--- }
--- ```
obj.expansions = {}

--- TextExpansion.defaults
--- Variable
--- Table containing options to be applied to expansions by default. The following keys are valid:
--- * **backspace** (default true): Use backspaces to remove the abbreviation when it is expanded.
--- * **internal** (default false): Trigger the expansion even when the abbreviation is inside another word
--- * **resetrecognizer** (default false): When an abbreviation is completed, reset the recognizer.
--- * **sendcompletionkey** (default true): When an abbreviation is completed, send the completion key along with it.
--- * **waitforcompletionkey** (default true): Wait for a completion key before expanding the abbreviation.
-- Options still TODO
-- Recognizer:
--   casesensitive = false, -- case of abbreviation must match exactly
-- Expander:
--   matchcase = true, -- make expansion conform in case to the abbreviation (works only for first caps, all caps)
obj.defaults = {
  backspace = true, -- remove the abbreviation
  internal = false, -- trigger even inside another word
  resetrecognizer = false, -- reset the recognizer after each completion
  sendcompletionkey = true, -- send the completion key
  waitforcompletionkey = true, -- wait for a completion key
  -- expansion = nil, -- not in default, must be defined
  -- abbreviation = nil, -- at format time, populated with the actual abbreviation that triggered this expansion
}

--- TextExpansion.specialKeys
--- Variable
--- Table containing information about special keys. It contains the following tables within it:
---
--- * The `specialKeys.complete` table contains keys that signal completion of an abbreviation. When one of these keys is pressed, the abbreviation is checked against the list of abbreviations specified as the keys in `TextExpansion.expansions`. If a match is found, the abbreviation is deleted and replaced with the corresponding expansion. Then the completion key is sent.
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
---   complete = {
---     "return", "space", "padenter", "tab",
---     ".", ",", ";", "/", "'",
---   },
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
  complete = {
    "return", "space", "padenter", "tab",
    ".", ",", ";", "/", "'",
  },
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
--- Length of time, in seconds, to wait before timeout.
---
--- If no new events arrive in that time period, TextExpansion will forget the abbreviation underway.
obj.timeoutSeconds = 3

local maxAbbreviationLength = 40

-- Internal variables
local debug
local keyWatcher
local keyActions -- generated on start() from specialKeys
local expansions -- generated on start()
local abbreviation
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

local function generateExpansions(self)
  expansions = {}
  for k,v in pairs(self.expansions) do
    if type(v) ~= "table" then
      v = {["expansion"] = v}
    end
    expansions[k] = merge_tables(self.defaults, v)
  end
end

local function resetAbbreviation()
  buffer:clear()
end

local endChars = " \r\n\t;:(){},"

local function isEndChar(char)
  return endChars:find(char, 1, 1) ~= nil
end

local printableChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function isPrintable(char)
  return printableChars:find(char, 1, 1) ~= nil
end

local function isMatch(abbr, expansion)
  if debug then print(("Considering abbreviation %s"):format(abbr)) end
  len = utf8.len(abbr)
  if expansion.waitforcompletionkey then
    if not isEndChar(buffer:get(1)) then
      if debug then print(("Not an end character: %s"):format(buffer:get(1))) end
      return false
    end
    offset = 1
  else
    offset = 0
  end
  local isMatch = buffer:matches(abbr, offset)
  if not isMatch then
    if debug then print("Buffer doesn't match abbreviation") end
    return false
  end
  if not expansion.internal then
    local isWholeWord = (buffer:size() <= len+offset) or (not isPrintable(buffer:get(len+offset+1)))
    if debug then print(("%s in buffer? %s (isWholeWord? %s)"):format(abbr, isMatch, isWholeWord)) end
    if not isWholeWord then
      if debug then print("Buried inside another word") end
      return false
    end
  end
  expansion.abbreviation = buffer:getAll():sub(-len)
  return true
end

local function getMatchingExpansion()
  for abbr, expansion in pairs(expansions) do
    if isMatch(abbr, expansion) then
      return expansion
    end
  end
  return nil
end

local function formatOutput(output)
  if type(output) == "function" then
    local _, result = pcall(output)
    if not _ then
      print("~~ expansion for '" .. buffer:getAll() .. "' gave an error of " .. result)
      result = nil
    end
    output = result
  end
  return output
end

local function formatExpansion(expansion)
  if expansion == nil then
    return
  end
  expansion.expansion = formatOutput(expansion.expansion)
  return expansion;
end

local function debugTable(table)
  if not debug then
    return
  end
  if table then
    for k,v in pairs(table) do print(string.format("%s -> %s", k, v)) end
  end
end

local function generateKeystrokes(expansion)
  if expansion == nil then
    return
  end
  local output = expansion.expansion
  local backspace = expansion.backspace
  if output then
    keyWatcher:stop()
    if backspace then
      local backspaces = utf8.len(expansion.abbreviation)
      if not expansion.waitforcompletionkey then
        backspaces = backspaces - 1 -- part of the abbreviation hasn't been output, so don't backspace that
      end
      for i = 1, backspaces, 1 do
        eventtap.keyStroke({}, "delete", 0)
      end
    end
    eventtap.keyStrokes(output)
    keyWatcher:start()
  end
end

local function resetAbbreviationTimeout()
  if debug then print("timed out") end
  resetAbbreviation()
end

local function restartInactivityTimer()
  if pendingTimer then pendingTimer:stop() end
  pendingTimer = doAfter(timeoutSeconds, function() resetAbbreviationTimeout() end)
end

local function handleEvent(self, ev)
  restartInactivityTimer()

  local keyCode = ev:getKeyCode()
  local keyAction = keyActions[keyCode] or "other"
  local eatAction = false -- pass the event on to the focused application
  if ev:getFlags().cmd then
    keyAction = "reset"
  end
  if keyAction == "reset" then
    resetAbbreviation()
  elseif keyAction == "delete" then -- delete the last character
    buffer:pop()
  else
    local s = ev:getCharacters()
    if s then -- add character to buffer
      for p, c in utf8.codes(s) do
        buffer:push(c)
      end
    end
    local expansion = getMatchingExpansion()
    if expansion then
      if not expansion.sendcompletionkey then
        eatAction = true
      end
      local expansion = formatExpansion(expansion)
      if not expansion.waitforcompletionkey -- the key event we're holding now is part of the abbreviation, it should stick with the abbreviation
        and not expansion.backspace -- if we were backspacing, the abbreviation wouldn't be around to be examined
        and expansion.sendcompletionkey -- if we weren't sending it, the order wouldn't matter, now would it?
        then
        -- give time for the other event to be processed first
        doAfter(0, function() generateKeystrokes(expansion) end)
      else
        generateKeystrokes(expansion)
      end
      debugTable(expansion)
      if expansion.resetrecognizer then
        resetAbbreviation()
      end
    end
  end
  if debug then print("Current abbreviation: " .. buffer:getAll()) end

  return eatAction
end

--- TextExpansion:start()
--- Method
--- Read expansions, and start the keyboard event watcher.
---
--- You must make any changes to `TextExpansion.expansions` and `TextExpansion.specialKeys` before this method is called; any further changes to them won't take effect until the watcher is started again.
function obj:start()
  if keyWatcher ~= nil then
    print("Warning: watcher is already running! Restarting...")
    keyWatcher:stop()
  end
  if debug then print("Starting keyboard event watcher.") end
  generateKeyActions(self)
  generateExpansions(self)
  timeoutSeconds = self.timeoutSeconds
  buffer:init(maxAbbreviationLength)
  resetAbbreviation()
  keyWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(ev) return handleEvent(self, ev) end)
  keyWatcher:start()
end

--- TextExpansion:stop()
--- Method
--- Stop and uninitialize the keyboard event watcher.
function obj:stop()
  if keyWatcher == nil then
    print("Warning: watcher is already stopped!")
    return
  end
  if debug then print("Stopping keyboard event watcher.") end
  keyWatcher:stop()
  keyWatcher = nil
end

--- TextExpansion:suspend()
--- Method
--- Suspend the keyboard event watcher.
function obj:suspend()
  if keyWatcher == nil then
    print("Error: watcher isn't initialized! Call TextExpansion:start() first.")
    return
  end
  if not keyWatcher:isEnabled() then
    print("Warning: watcher is already suspended! No change.")
  else
    if debug then print("Suspending keyboard event watcher.") end
    keyWatcher:stop()
  end
end

--- TextExpansion:resume()
--- Method
--- Resume the keyboard event watcher.
function obj:resume()
  if keyWatcher == nil then
    print("Error: watcher isn't initialized! Call TextExpansion:start() first.")
    return
  end
  if keyWatcher:isEnabled() then
    print("Warning: watcher is already running! No change.")
  else
    if debug then print("Resuming keyboard event watcher.") end
    keyWatcher:start()
  end
end

--- TextExpansion:isEnabled()
--- Method
--- Returns true if the keyboard event watcher is configured and active.
function obj:isEnabled()
  return keyWatcher and keyWatcher:isEnabled()
end

function obj:resetAbbreviation()
  resetAbbreviation()
end

function obj:setDebug(val)
  if val then
    debug = true
  else
    debug = false
  end
end

return obj
