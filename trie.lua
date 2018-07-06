-- Create a set of tries to represent abbreviations

-- Each node in a trie set has a unique value, numbered densely starting at 1

local Trie = {}
Trie.__index = Trie

Trie.COMPLETION = "_completion"

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end
local spoonPath = script_path()

local makeCounter = dofile(spoonPath.."/counter.lua")

-- create an empty trie, using the same counter as its parent, if any
function Trie:new()
  local counter -- counter so nodes have unique values
  if self then
    counter = self.getnextvalue
  else
    counter = makeCounter()
  end
  local new = {
    value = counter(),
    transitions = {},
    expansions = {},
    getnextvalue = counter,
  }
  new = setmetatable(new, Trie)
  return new
end

function Trie:addentry(keys, value)
  local cur = self
  for i=1,#keys do
    local k = keys[i]
    assert(k ~= nil)
    if cur.transitions[k] == nil then cur.transitions[k] = cur:new() end
    cur = cur.transitions[k]
  end
  if cur.expansions == nil then cur.expansions = {} end
  cur.expansions[#cur.expansions + 1] = value
end

function Trie.print_helper(trie, depth)
  if trie == nil then
    return
  end
  local preface = string.rep("-", depth)
  for _, val in pairs(trie.expansions or {}) do
    local out = val
    if type(out) == "table" then out = out.expansion end
    print(("%sEXPANSION: %s"):format(preface,out))
  end
  for key, val in pairs(trie.transitions or {}) do
    local label = key
    if type(label) == "number" then
      label = utf8.char(label)
    end
    print(("%s%s"):format(preface,label))
    val:print_helper(depth + 1)
  end
end

function Trie:print()
  print("Printing trie...")
  self:print_helper(0)
end

function Trie.createtrieset(expansions, homogenizecase, debug)
  local trieset = {}
  trieset.wordboundary = Trie.new()
  trieset.internals = trieset.wordboundary:new() -- tie counters together
  assert(trieset.wordboundary.value == 1, ("Word boundary node should be 1; actual %d"):format(trieset.wordboundary.value))
  assert(trieset.internals.value == 2, ("Internals node should be 2; actual %d"):format(trieset.internals.value))
  for i=1,#expansions do
    local exp = expansions[i]
    local abbr = exp.abbreviation
    -- add each abbreviation to the appropriate trie with exp at its leaf
    if debug then print(("Inserting abbreviation %s with expansion %s"):format(abbr, exp)) end
    if homogenizecase then
      abbr = string.lower(abbr)
    end
    local cur
    if exp.internal then
      cur = trieset.internals
    else
      cur = trieset.wordboundary
    end
    local keys = {}
    for p,c in utf8.codes(abbr) do
      keys[#keys+1] = c
    end
    if exp.waitforcompletionkey then
      keys[#keys+1] = Trie.COMPLETION
    end
    cur:addentry(keys,exp)
  end
  if debug then print("Word boundaries:") trieset.wordboundary:print() end
  if debug then print("Internals") trieset.internals:print() end
  return trieset
end

return Trie
