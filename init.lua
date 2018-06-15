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

-- Dependencies
local keyMap = require"hs.keycodes".map

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
---
--- A simple example:
--- ```
--- spoon.TextExpansion.expansions = {
---     ["date"] = function() return os.date("%B %d, %Y") end,
---     ["name"] = "my name is foo",
--- }
--- ```
obj.expansions = {}

obj.expansionDefaults = {
  -- internal = false, -- trigger even inside another word TODO
  backspace = true, -- remove the abbreviation
  -- casesensitive = false, -- case of abbreviation must match exactly TODO
  -- matchcase = true, -- make expansion conform in case to the abbreviation (works only for first caps, all caps) TODO
  -- omitcompletionkey = false, -- don't send the completion key TODO
  -- resetrecognizer = false, -- reset the recognizer after each completion TODO
  -- expansion = nil, -- not in default, must be defined
  -- abbreviation = nil, -- at format time, contains the actual abbreviation that triggered this expansion
}

-- Recognizer:
--   internal
--   casesensitive
-- Expander:
--   matchcase
--   omitcompletionkey
-- Output:
--   backspace
--   resetrecognizer

--- TextExpansion.specialKeys
--- Variable
--- Table containing information about special keys. It contains two tables within it:
---
--- * The `specialKeys["complete"]` table contains keys that signal completion of an abbreviation. When one of these keys is pressed, the abbreviation is checked against the list of abbreviations specified as the keys in `TextExpansion.expansions`. If a match is found, the abbreviation is deleted and replaced with the corresponding expansion. Then the completion key is sent.
---
--- * The `specialKeys["reset"]` table contains the names of keys that should reset any abbreviation in progress. (For example, typing `da<left>te` does not trigger an expansion of "date".)
---
--- * The `specialKeys["delete"]` table contains the names of keys that should delete the last character in an abbreviation in progress.
---
--- The value of each entry in these tables is a valid key name from `hs.keycodes.map`
---
--- By default:
--- ```
--- TODO
--- ```
obj.specialKeys = {
  complete = {
    "return", "space", "padenter", "tab", ".",
    ",", ";", ":", "/", "\"", "(", ")",
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

-- Internal variables
local keyWatcher
local keyActions -- generated on start() from specialKeys
local abbreviation
local pendingTimer

function generateKeyActions(array)
  keyActions = {}
  for action,keyTable in pairs(array) do
    for _,keyName in pairs(keyTable) do
      keyActions[keyMap[keyName]] = action
    end
  end
end

function obj:resetAbbreviation()
  abbreviation = ""
end

function merge_tables(default, override)
  local combined = {}
  for k,v in pairs(default) do combined[k] = v end
  for k,v in pairs(override) do combined[k] = v end
  return combined
end

function obj:getExpansion(abbreviation)
  local expansion = self.expansions[abbreviation]
  if expansion == nil then
    return nil
  end
  if type(expansion) ~= "table" then
    expansion = {["expansion"] = expansion}
  end
  expansion["abbreviation"] = abbreviation
  return merge_tables(self.expansionDefaults, expansion)
end

function obj:formatOutput(output)
  if type(output) == "function" then
    local _, result = pcall(output)
    if not _ then
      print("~~ expansion for '" .. abbreviation .. "' gave an error of " .. result)
      result = nil
    end
    output = result
  end
  return output
end

function obj:formatExpansion(expansion)
  if expansion == nil then
    return
  end
  expansion["expansion"] = self:formatOutput(expansion["expansion"])
  return expansion;
end

function generateKeystrokes(expansion)
  if expansion == nil then
    return
  end
  local output = expansion["expansion"]
  local backspace = expansion["backspace"]
  if output then
    keyWatcher:stop()
    if backspace then
      for i = 1, utf8.len(expansion["abbreviation"]), 1 do hs.eventtap.keyStroke({}, "delete", 0) end
    end
    hs.eventtap.keyStrokes(output)
    keyWatcher:start()
  end
end

function obj:resetAbbreviationTimeout()
  -- print("timed out")
  self:resetAbbreviation()
end

function obj:handleEvent(ev)
  local keyCode = ev:getKeyCode()
  local keyAction = keyActions[keyCode] or "other"
  if ev:getFlags().cmd then
    keyAction = "reset"
  end
  if keyAction == "reset" then
    self:resetAbbreviation()
  elseif keyAction == "delete" then -- delete the last character
    local lastChar = utf8.offset(abbreviation, -1) or 0
    abbreviation = abbreviation:sub(1, lastChar-1)
  elseif keyAction == "complete" then
    local expansion = self:getExpansion(abbreviation)
    local expansion = self:formatExpansion(expansion)
    generateKeystrokes(expansion)
    self:resetAbbreviation()
  else -- add character to abbreviation
    local c = ev:getCharacters()
    if c then abbreviation = abbreviation .. c end
  end
  if pendingTimer then
    pendingTimer:stop()
  end
  pendingTimer = hs.timer.doAfter(self.timeoutSeconds, function() self:resetAbbreviationTimeout() end)
  -- print("Current abbreviation: " .. abbreviation)

  return false -- pass the event on to the focused application
end

--- TextExpansion:start()
--- Method
--- Start the keyboard event watcher.
---
--- You must make any changes to `TextExpansion.expansions` and `TextExpansion.specialKeys` before this method is called; any further changes to them won't take effect until the watcher is started again.
function obj:start()
  if keyWatcher ~= nil then
    print("Warning: watcher is already running! Restarting...")
    keyWatcher:stop()
  end
  generateKeyActions(self.specialKeys)
  self:resetAbbreviation()
  keyWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev) self:handleEvent(ev) end)
  keyWatcher:start()
end

--- TextExpansion:stop()
--- Method
--- Stop the keyboard event watcher.
function obj:stop()
  if keyWatcher == nil then
    print("Warning: watcher is already stopped!")
    return
  end
  keyWatcher:stop()
  keyWatcher = nil
end

return obj
