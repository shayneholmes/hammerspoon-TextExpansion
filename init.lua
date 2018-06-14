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
    "return",
    "space",
    "padenter",
    "tab",
  },
  reset = {
    "escape",
    "left",
    "right",
    "up",
    "down",
    "help",
    "home",
    "pageup",
    "forwarddelete",
    "end",
    "pagedown",
  },
  delete = {
    "delete",
  },
}

--- TextExpansion:start()
--- Method
--- Start the keyboard event watcher.
function obj:start()
end

return obj
