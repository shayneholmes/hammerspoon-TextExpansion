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
local trie = dofile(obj.spoonPath.."/trie.lua")

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
obj.timeoutSeconds = 10

local maxAbbreviationLength = 40
local maxStatesUndo = 10

-- Internal variables
local buffer
local states
local debug
local keyWatcher
local keyActions -- generated on start() from specialKeys
local expansions -- generated on start()
local dfa -- generated on start()
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
    v.abbreviation = k
    expansions[k] = merge_tables(self.defaults, v)
  end
end

local function resetAbbreviation()
  buffer:clear()
  states:clear()
end

local function printBuffer()
  print(("Buffer: %s"):format(utf8.char(table.unpack(buffer:getAll()))))
end

local function printStateHistory()
  print(("States: %s"):format(table.concat(states:getAll(),",")))
end

local endChars = " \r\n\t;:(){},"

local function isEndChar(char)
  return endChars:find(char, 1, 1) ~= nil
end

local printableChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function isPrintable(char)
  return printableChars:find(char, 1, 1) ~= nil
end

local function evaluateExpansion(expansion)
  -- place the result in output
  output = expansion.expansion
  if type(output) == "function" then
    local _, result = pcall(output)
    if not _ then
      print("~~ expansion for '" .. expansion.abbreviation .. "' gave an error of " .. result)
      result = nil
    end
    output = result
  end
  expansion.output = output
  return expansion;
end

local function getMatchingExpansion(state)
  local expansions = dfa[state].expansions
  if expansions then
    for _,x in pairs(expansions) do
      return evaluateExpansion(x)
    end
  end
  return nil
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
  elseif keyAction == "delete" then -- delete the last character, go back to previous state
    buffer:pop()
    states:pop()
  else
    local state = states:getHead() or 1
    local oldState = state
    local s = ev:getCharacters()
    if s then -- follow transition to next state
      local isCompletion = isEndChar(s)
      if isCompletion then
        state = dfa[state].transitions["_completion"] or 1
      end
      for p, c in utf8.codes(s) do
        buffer:push(c)
        if not isCompletion then
          state = dfa[state].transitions[c] or dfa[2].transitions[c] or 2 -- to internals
        end
      end
      states:push(state)
      if debug then print(( "%d -> %s -> %d" ):format(oldState, s, state)) end
      local expansion = getMatchingExpansion(state)
      if expansion then
        if not expansion.sendcompletionkey then
          eatAction = true
        end
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
        elseif isCompletion then
          states:push(1) -- reset after completions
        end
      end
    end
  end
  if debug then printBuffer() printStateHistory() end
  return eatAction
end

local function init(self)
  generateKeyActions(self)
  generateExpansions(self)
  timeoutSeconds = self.timeoutSeconds
  buffer = circularbuffer.new(maxAbbreviationLength)
  states = circularbuffer.new(maxStatesUndo)
  states:push(1) -- start in root set
  dfa = trie:createdfa(expansions)
  if debug then trie:printdfa(dfa) end
  resetAbbreviation()
  keyWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(ev) return handleEvent(self, ev) end)
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
  init(self)
  if debug then print("Starting keyboard event watcher.") end
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
