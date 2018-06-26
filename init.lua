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
  -- abbreviation = nil, -- programmatically populated at start
  -- output = nil, -- populated at trigger time
  -- trigger = nil, -- populated at trigger time
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

local endChars = "\"' \r\n\t;:(){},@="

local function isEndChar(char)
  return endChars:find(char, 1, 1) ~= nil
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
  return output;
end

local function getAbbreviation(x)
  local length = #x.abbreviation
  if x.waitforcompletionkey then length = length + 1 end
  local actual = utf8.char(table.unpack(buffer:getEnding(length)))
  if debug then print(("Abbreviation interpreted: %s -> %s"):format(x.abbreviation,actual)) end
  return actual
end

local function getMatchingExpansion(state)
  local expansions = dfa[state].expansions
  if expansions then
    for _,x in pairs(expansions) do
      if true then -- evaluate match
        x.trigger = getAbbreviation(x)
        x.output = evaluateExpansion(x)
        return x
      end
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

local function getnextstate(cur, charcode)
  local str = utf8.char(charcode)
  if debug then print(("Char %s, code %s"):format(str,charcode)) end
  local isCompletion = false -- true if this transition moves to a completion node
  local nxt = dfa[cur].transitions[charcode] -- follow any valid transitions
  if nxt == nil then -- no valid transitions
    if isEndChar(str) then
      -- check original state for completions, otherwise reset
      nxt = dfa[cur].transitions[trie.COMPLETION]
      if nxt == nil then
        nxt = trie.WORDBOUNDARY_NODE
      else
        isCompletion = true -- go straight to word boundary state after this
      end
    else
      nxt = dfa[trie.INTERNAL_NODE].transitions[charcode] or trie.INTERNAL_NODE -- to internals
    end
  end
  if debug then print(( "%d -> %s -> %d" ):format(cur, str, nxt)) end

  return nxt, isCompletion
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
    local state = states:getHead() or trie.WORDBOUNDARY_NODE
    for p, c in utf8.codes(ev:getCharacters()) do -- might be multiple chars, e.g. when deadkeys are enabled
      local isCompletion
      state, isCompletion = getnextstate(state, c)
      buffer:push(c)
      states:push(state)
      local expansion = getMatchingExpansion(state)
      if expansion then
        debugTable(expansion)
        processexpansion(expansion)
        eatAction = eatAction or not expansion.sendcompletionkey -- true if any are true
        if expansion.resetrecognizer then resetAbbreviation() end
        if isCompletion then states:push(trie.WORDBOUNDARY_NODE) end -- reset after completions
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
  states:push(trie.WORDBOUNDARY_NODE) -- start in root set
  dfa = trie:createdfa(expansions, isEndChar)
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

function obj:testPerformance(expansions, input)
  assert(not obj:isEnabled(), "Object must not be enabled when running tests.")

  -- parameters
  local expansionsSizes = {
    10,
    100,
    1000,
    10000,
    100000,
  }
  local inputSizes = {
    10,
    100,
    1000,
    10000,
    100000,
  }
  local attempts = 5 -- smooth out benchmarking

  -- mock
  local originalExpansions = self.expansions
  local originalGenerateKeystrokes = generateKeystrokes
  generateKeystrokes = function() end

  -- fixtures
  for _, testExpansionsSize in pairs(expansionsSizes) do
    local testExpansions = {}
    for i=1,testExpansionsSize do
      local key = ("abbreviation%d"):format(i)
      local value = ("expansion%d"):format(i)
      testExpansions[key] = value
    end

    self.expansions = testExpansions

    -- init test
    for _=1,attempts do
      if self:isEnabled() then self:stop() end
      local initStart = os.clock()
      self:start()
      local initEnd = os.clock()
      print(("init, %d, %f"):format(
        testExpansionsSize,
        initEnd - initStart
      ))
    end

    for _, testInputSize in pairs(inputSizes) do
      local testInputBase = "test words "
      local sizeSoFar = #testInputBase
      local testInput = testInputBase
      while sizeSoFar < testInputSize do
        sizeSoFar = sizeSoFar * 2
        testInput = testInput .. testInput
      end
      testInput = string.sub(testInput, 1, testInputSize)

      -- input test
      for _=1,attempts do
        local inputStart = os.clock()

        for i=1,#testInput do
          local ev = {
            getKeyCode = function() return " " end,
            getCharacters = function() return testInput[i] end,
            getFlags = function() return {cmd = false} end,
          }
          handleEvent(self, ev)
        end

        local inputEnd = os.clock()
        print(("input, %d, %d, %f"):format(
        testExpansionsSize,
        testInputSize,
        inputEnd - inputStart
        ))
      end
    end
    self:stop()

  end

  -- unmock
  generateKeystrokes = originalGenerateKeystrokes
  self.expansions = originalExpansions
end

return obj
