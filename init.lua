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
--- * **casesensitive** (default false): Case of abbreviation must match exactly
--- * **internal** (default false): Trigger the expansion even when the abbreviation is inside another word
--- * **matchcase** (default true): If you type an abbreviation in `ALL CAPS` or `FirstCaps`, the expansion will be typed in the same manner; ignored when `casesensitive` is set
--- * **resetrecognizer** (default false): When an abbreviation is completed, reset the recognizer.
--- * **sendcompletionkey** (default true): When an abbreviation is completed, send the completion key along with it.
--- * **waitforcompletionkey** (default true): Wait for a completion key before expanding the abbreviation.
obj.defaults = {
  backspace = true, -- remove the abbreviation
  casesensitive = false, -- case of abbreviation must match exactly
  internal = false, -- trigger even inside another word
  matchcase = true, -- if you type an abbreviation in `ALL CAPS` or `FirstCaps`, the expansion will be typed in the same manner; ignored when `casesensitive` is set
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
local debug
local trie
local keyWatcher
local keyActions -- generated on start() from specialKeys
local expansions -- generated on start()
local statemanager -- generated on start()
local abbreviation
local pendingTimer
local timeoutSeconds

-- Test variables
local testMocked -- nil normally, but during tests, mocked things are stored here
local testOutput
local testDoAfter

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
  statemanager:clear()
end

local function printBuffer()
  print(("Buffer: %s"):format(utf8.char(table.unpack(buffer:getAll()))))
end

local endChars = "\"' \r\n\t;:(){},@="

local function isEndChar(char)
  return endChars:find(char, 1, 1) ~= nil
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

local function isallcaps(str)
  return str:upper() == str and str:lower() ~= str
end

local function makeallcaps(str)
  return str:upper()
end

local function isfirstcap(str)
  return isallcaps(str:sub(1,1))
end

local function makefirstcap(str)
  return str:sub(1,1):upper() .. str:sub(2)
end

-- modify output depending on trigger
local function matchcase(trigger, output)
  if isallcaps(trigger) then
    return makeallcaps(output)
  elseif isfirstcap(trigger) then
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
    statemanager:rewindstate()
  else
    for p, c in utf8.codes(ev:getCharacters()) do -- might be multiple chars, e.g. when deadkeys are enabled
      buffer:push(c)
      statemanager:followedge(c)
      local expansion = statemanager:getMatchingExpansion()
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

local function init(self)
  generateKeyActions(self)
  generateExpansions(self)
  timeoutSeconds = self.timeoutSeconds
  buffer = circularbuffer.new(maxAbbreviationLength)
  statemanager = StateManager.new(expansions, isEndChar, maxStatesUndo, debug)
  resetAbbreviation()
  keyWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(ev) return handleEvent(self, ev) end)
end

--- TextExpansion:start()
--- Method
--- Read expansions, and start the keyboard event watcher.
---
--- You must make any changes to `TextExpansion.expansions` and `TextExpansion.specialKeys` before this method is called; any further changes to them won't take effect until the watcher is started again.
function obj:start()
  assert(not testMocked, "Can't start in test mode")
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
  local attempts = 10 -- smooth out benchmarking

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
      local testInputBase = "abbreviation2 abbreviation and a bunch of words that don't make it very far down the state machine"
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

        string.gsub(testInput, ".", function(char)
          local ev = {
            getKeyCode = function() return " " end,
            getCharacters = function() return char end,
            getFlags = function() return {cmd = false} end,
          }
          handleEvent(self, ev)
        end)

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

function obj:testSetup()
  assert(not obj:isEnabled(), "Object must not be enabled when running tests.")
  assert(not testMocked, "Can't setup tests twice!")
  testMocked = {
    expansions = self.expansions,
    eventtap = eventtap,
    doAfter = doAfter,
    restartActivityTimer = restartInactivityTimer,
  }

  self.expansions = nil -- this must be set by a test
  eventtap = {
    keyStrokes = function(str) -- add strokes to output
      testOutput = testOutput .. str
    end,
    keyStroke = function() -- remove strokes from output
      assert(testOutput:len() > 0)
      testOutput = testOutput:sub(1, -2)
    end,
    new = function() return { stop = function() end, start = function() end } end,
    event = { types = { keyDown = nil } },
  }
  doAfter = function(_, func)
    testDoAfter = func
  end
  restartInactivityTimer = function() end -- this calls doAfter
end

function obj:testTeardown()
  assert(testMocked, "Test mode must already be set up to tear it down")
  self.expansions = testMocked.expansions
  eventtap = testMocked.eventtap
  doAfter = testMocked.doAfter
  restartActivityTimer = testMocked.restartInactivityTimer
  testMocked = nil

  testOutput = nil
  testDoAfter = nil

  keyWatcher = nil
end

function obj:testSetContext(expansions)
  assert(testMocked, "Test mode must be enabled to set a context")
  self.expansions = expansions
  init(self)
end

function obj:testRun(input, expected)
  assert(testMocked, "Test mode must be enabled to run a test")
  assert(self.expansions, "A context must be set before running a test")
  testOutput = ""
  testDoAfter = nil
  resetAbbreviation()
  string.gsub(input, ".", function(char)
    local ev = {
      getKeyCode = function() return " " end,
      getCharacters = function() return char end,
      getFlags = function() return {cmd = false} end,
    }
    local eat = handleEvent(self, ev)
    if not eat then
      testOutput = testOutput .. char
    end
    if testDoAfter then
      testDoAfter()
      testDoAfter = nil
    end
  end)

  assert(testDoAfter == nil, "Must be no remaining delayed calls")
  assert(expected == testOutput,
    ("Output for input \"%s\": Expected: \"%s\", actual: \"%s\""):format(input, expected, testOutput))
end


function obj:runtests()
  local tests = dofile(obj.spoonPath.."/tests.lua")
  return tests.runtests(self)
end

return obj
