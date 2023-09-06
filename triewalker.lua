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

local function toLower(charcode)
  local str = utf8.char(charcode):lower()
  for p,c in utf8.codes(str) do
    charcode = c
  end
  return charcode
end

local function nextstate(state, charcode, isEndChar)
  local nextstate = nil
  local node = state
  while node.suffix and not node.transitions[charcode] do
    node = node.suffix
  end
  if node.transitions[charcode] then -- exact match
    nextstate = node.transitions[charcode]
  else -- no exact match, fail to the appropriate state
    if isEndChar then
      nextstate = node.transitions[Trie.WORDBOUNDARY] -- reset to word boundary
    else
      nextstate = node -- to the no-state, so we can trigger internals
    end
  end
  return nextstate
end

-- looks for completions in node and its suffixes
local function getcompletion(node)
  local cur = node
  while cur and not cur.transitions[Trie.COMPLETION] do
    cur = cur.suffix
  end
  if cur then -- there is a completion
    return cur.transitions[Trie.COMPLETION]
  end
end

function TrieWalker:followedge(charcode)
  -- analyze and maybe homogenize the character
  local isEndChar = self.isEndChar(charcode) -- save for later
  if self.homogenizecase then
    charcode = toLower(charcode)
  end
  -- find the next state
  local nextstate = nextstate(self.state, charcode, isEndChar)
  -- compute the expansion; it's usually whatever's at the next state, but may not be if the char is an end char
  local expansionstate = nextstate
  if isEndChar then
    expansionstate = getcompletion(self.state) or expansionstate
  end
  -- change states and return the expansion (which may be nil)
  if self.debug then print(( "%s -> %s -> %s" ):format(self.state.address, utf8.char(charcode), nextstate.address)) end
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
