-- Create a trie to hold expansions, indexed by their abbreviations
--
-- One wrinkle is in the root node: We build the trie starting from an "empty state" root, which has children for internals and a special "word boundary" child, where abbreviations that require word boundaries live. However, when we return the trie, we return it with the "word boundary" node as the root. It's still connected to the empty state node by suffix links, but the consumers of the trie will reset to the word boundary node after end characters, and only go to the empty state when nothing matches. It just makes the consumer code cleaner.

local Trie = {}
Trie.__index = Trie

Trie.COMPLETION = "_completion"
Trie.WORDBOUNDARY = "_wordboundary"

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end
local spoonPath = script_path()

local List = dofile(spoonPath.."/list.lua")

-- create an empty trie node
function Trie.new()
  local new = {
    transitions = {},
    expansions = nil,
  }
  new = setmetatable(new, Trie)
  return new
end

function Trie:addentry(keys, value)
  local cur = self
  for i=1,#keys do
    local k = keys[i]
    assert(k ~= nil)
    if cur.transitions[k] == nil then cur.transitions[k] = Trie.new() end
    cur = cur.transitions[k]
  end
  if not value then return end
  if cur.expansions == nil then cur.expansions = {} end
  cur.expansions[#cur.expansions + 1] = value
end

function Trie.get_label(t)
  if t == Trie.COMPLETION then
    return '(completion)'
  end
  if t == Trie.WORDBOUNDARY then
    return '(word-boundary)'
  end
  return utf8.char(t)
end

function Trie:print()
  if self == nil then
    return
  end
  if not self.expansion and not self.expansions then
    print(("%s"):format(self.address))
  end
  for _, val in pairs(self.expansions or {self.expansion}) do
    local out = val
    if type(out) == "table" then out = out.expansion end
    print(("%s -> %s"):format(self.address,out))
  end
  for key, val in pairs(self.transitions or {}) do
    val:print()
  end
end

local function aggregateExpansions(node, debug)
  -- choose the highest-pri expansion and keep it; discard the rest
  local best = nil
  -- first, examine this node itself
  local expansions = node.expansions
  if expansions then
    for i=1,#expansions do
      local x = expansions[i]
      if x:takesPriorityOver(best) then best = x end
    end
  end
  -- now, look at the alternatives; this is necessary because we allow priorities to override the other rules, so a shorter abbreviation from a suffix might win
  local cur = node.nextexpansion
  while cur do
    assert(cur.expansion, ("%s -> nextexpansion pointed to %s, so it should have an expansion"):format(node.address, cur.address))
    if cur.expansion:takesPriorityOver(best) then best = cur.expansion end
    cur = cur.nextexpansion
  end
  node.expansion = best
  if debug and node.expansion then print(("Expansion at %s: %s"):format(node.address, node.expansion.expansion)) end
  node.expansions = nil
end

local function findSuffix(parent, child, key, isEndChar)
  local cand = parent
  if cand.suffix then -- start at the parent's suffix, unless we're at the root
    cand = cand.suffix
  end
  while cand.suffix and not (cand.transitions and cand.transitions[key]) do
    cand = cand.suffix
  end
  if cand.transitions and cand.transitions[key] then -- found an exact match
    if cand.transitions[key] ~= child then -- avoid the case where a child of the top node finds itself
      return cand.transitions[key]
    end
  end
  local root = cand -- we're at the root now
  assert(root.suffix == nil, "No strict suffixes; must be the root node")
  assert(root.transitions[Trie.WORDBOUNDARY], "With no strict suffixes, double-check that the root node has a wordboundary item")
  if isEndChar(key) then -- note that WORDBOUNDARY is not an endchar itself
    return root.transitions[Trie.WORDBOUNDARY]
  end
  return root -- no suffixes at all; just return the root node
end

local function findNextExpansions(node)
  if not node.suffix then return nil end
  node = node.suffix
  while node.suffix do
    if node.expansion then
      return node
    end
    node = node.suffix
  end
end

function Trie:decorateForAhoCorasick(isEndChar, debug)
  -- populate a Trie and all its children with two fields for Aho-Corasick algorithm:
  -- * `suffix` points to the longest strict suffix
  -- * `nextexpansion` points to the longest suffix with an expansion, so we can quickly find them without storing them multiply
  local queue = List.new()
  queue:pushright(self)
  while not queue:empty() do
    -- this search is done breadth-first, so that all possible strict suffixes have already been decorated already
    local cur = queue:popleft()
    if debug then print(("Decorating node %s"):format(cur.address)) end
    cur.nextexpansion = findNextExpansions(cur)
    if debug and cur.nextexpansion then print(("NextExpansion of %s: %s"):format(cur.address, cur.suffix.address)) end
    aggregateExpansions(cur, debug)
    for key, child in pairs(cur.transitions or {}) do
      child.suffix = findSuffix(cur, child, key, isEndChar)
      if debug then print(("Suffix of %s: %s"):format(child.address, child.suffix.address)) end
      queue:pushright(child)
    end
  end
end

function Trie:decorateForDebug(prefix) -- this is expensive!
  self.address = prefix or "$"
  for key, child in pairs(self.transitions or {}) do
    child:decorateForDebug(("%s.%s"):format(self.address, Trie.get_label(key)))
  end
end

function Trie.createtrie(expansions, homogenizecase, isEndChar, debug)
  local trie = Trie.new()
  trie:addentry({Trie.WORDBOUNDARY},nil) -- ensure that this node exists
  for i=1,#expansions do
    local exp = expansions[i]
    local abbr = exp.abbreviation
    -- add each abbreviation to the appropriate trie with exp at its leaf
    if debug then print(("Inserting abbreviation %s with expansion %s"):format(abbr, exp)) end
    if homogenizecase then
      abbr = string.lower(abbr)
    end
    local keys = {}
    if not exp.internal then
      keys[#keys+1] = Trie.WORDBOUNDARY
    end
    for p,c in utf8.codes(abbr) do
      keys[#keys+1] = c
    end
    if exp.waitforcompletionkey then
      keys[#keys+1] = Trie.COMPLETION
    end
    trie:addentry(keys, exp)
  end
  if debug then trie:decorateForDebug() end
  trie:decorateForAhoCorasick(isEndChar, debug)
  if debug then trie:print() end
  assert(trie.transitions[Trie.WORDBOUNDARY], "Ensure that we've created a word boundary node")
  return trie.transitions[Trie.WORDBOUNDARY] -- this is the root, for all interpretation purposes
end

return Trie
