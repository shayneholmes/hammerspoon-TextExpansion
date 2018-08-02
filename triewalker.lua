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

function TrieWalker:getMatchingExpansion()
  -- return the expansion at the current node
  -- the aggregation function in the trie has already checked suffixes
  return self.state.expansion
end

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
  if self.isCompletion then -- reset after completions
    self.isCompletion = false
    self:selectstate(self.trie)
  end
  local str = utf8.char(charcode)
  if self.homogenizecase then
    str = str:lower()
    for p,c in utf8.codes(str) do
      charcode = c
    end
  end
  if self.debug then print(("Char %s, code %s"):format(str,charcode)) end
  local nextstate = nil -- this will be set to the next state
  local node = self.state
  while node.suffix and not node.transitions[charcode] do
    node = node.suffix
  end
  if node.transitions[charcode] then -- exact match
    nextstate = node.transitions[charcode]
  else -- no match possible, so node points to the no-state node
    if self.isEndChar(charcode) then
      -- this end char might complete an abbreviation, and starts a new one either way
      -- first, check current state and suffixes for completions that we should trigger
      local cur = self.state
      while cur and not cur.transitions[Trie.COMPLETION] do
        cur = cur.suffix
      end
      if cur then -- there is a completion; go to word boundary state, but after this
        nextstate = cur.transitions[Trie.COMPLETION]
        self.isCompletion = true
      else
        nextstate = self.trie -- no completion; reset to word boundary now
      end
    else
      nextstate = node -- no-state node, so we can trigger internals
    end
  end

  if self.debug then print(( "%s -> %s -> %s" ):format(self.state.address, str, nextstate.address)) end
  self:selectstate(nextstate)
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
    isCompletion = false, -- variable to hold state: when we've completed, we stay in the completion state, but the next move goes from the word boundary root
  }
  self = setmetatable(self, TrieWalker)
  self:reset()
  return self
end

return TrieWalker
