-- Walk a trie (decorated for Aho-Corasick), managing state transitions and things

local TrieWalker = {}
TrieWalker.__index = TrieWalker

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end
local spoonPath = script_path()

local circularbuffer = dofile(spoonPath.."/circularbuffer.lua")
local Trie = dofile(spoonPath.."/trie.lua")

function TrieWalker:reset()
  self.states:clear()
  self:selectstate(self.trie)
end

function TrieWalker:rewindstate()
  self.states:pop()
  self.state = self.states:getHead() or self.trie
end

function TrieWalker:selectstate(state)
  self.state = state
  self.states:push(state)
end

function TrieWalker:followedge(charcode)
  -- analyze and maybe homogenize the character
  local isEndChar = self.isEndChar(charcode) -- save for later
  local str = utf8.char(charcode)
  if self.homogenizecase then
    str = str:lower()
    for p,c in utf8.codes(str) do
      charcode = c
    end
  end
  -- find the next state
  local nextstate = nil -- this will be set to the next state
  local node = self.state
  while node.suffix and not node.transitions[charcode] do
    node = node.suffix
  end
  if node.transitions[charcode] then -- exact match
    nextstate = node.transitions[charcode]
  else -- no exact match, fail to the appropriate state
    if isEndChar then
      nextstate = self.trie -- reset to word boundary
    else
      nextstate = node -- to the no-state, so we can trigger internals
    end
  end
  -- compute the expansion; it's usually whatever's at the next state, but may not be if the char is an end char
  local expansionstate = nextstate
  if isEndChar then
    -- this end char might have completed an abbreviation; check current state and suffixes for completions that we should trigger
    local cur = self.state
    while cur and not cur.transitions[Trie.COMPLETION] do
      cur = cur.suffix
    end
    if cur then -- there is a completion
      expansionstate = cur.transitions[Trie.COMPLETION]
    end
  end
  -- change states and return the expansion (which may be nil)
  if self.debug then print(( "%s -> %s -> %s" ):format(self.state.address, str, nextstate.address)) end
  if self.debug and expansionstate.expansion then print(( "(expand %s to %s)" ):format(expansionstate.address, expansionstate.expansion)) end
  self:selectstate(nextstate)
  return expansionstate.expansion
end

function TrieWalker.new(trie, homogenizecase, isEndChar, maxStatesUndo, debug)
  assert(trie, "Must provide trie")
  assert(type(isEndChar) == "function", "Must pass in a function to identify end characters")
  assert(maxStatesUndo, "Must pass in a number of states to save")
  local self = {
    debug = not not debug,
    trie = trie,
    homogenizecase = homogenizecase,
    isEndChar = isEndChar,
    state = nil, -- set this in in reset
    states = circularbuffer.new(maxStatesUndo),
  }
  self = setmetatable(self, TrieWalker)
  self:reset()
  return self
end

return TrieWalker
