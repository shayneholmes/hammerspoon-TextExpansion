-- Use a provided DFA to manage state and report back any expansions that
-- are in the active state

Dfa = {}
Dfa.__index = Dfa

Dfa.WORDBOUNDARY_NODE = 1
Dfa.INTERNAL_NODE = 2

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end
local spoonPath = script_path()

local circularbuffer = dofile(spoonPath.."/circularbuffer.lua")
local Trie = dofile(spoonPath.."/trie.lua")

function Dfa:getMatchingExpansion()
  local expansions = self.dfa[self.state].expansions
  if expansions then
    assert(#expansions == 1, "There should only be only expansion matching.")
    return expansions[1]
  end
  return nil
end

function Dfa:clear()
  self.states:clear()
  self.state = Dfa.WORDBOUNDARY_NODE
end

function Dfa:rewindstate()
  self.states:pop()
  self.state = self.states:getHead() or Dfa.WORDBOUNDARY_NODE
end

function Dfa:selectstate(state)
  self.state = state
  self.states:push(state)
end

function Dfa:followedge(charcode)
  if self.isCompletion then -- reset after completions
    self.isCompletion = false
    self:selectstate(Dfa.WORDBOUNDARY_NODE)
  end
  local str = utf8.char(charcode)
  if self.debug then print(("Char %s, code %s"):format(str,charcode)) end
  local nextstate = self.dfa[self.state].transitions[charcode] -- follow any valid transitions
  if nextstate == nil then -- no valid transitions
    if self.isEndChar(str) then
      -- check original state for completions, otherwise reset
      nextstate = self.dfa[self.state].transitions[Trie.COMPLETION]
      if nextstate == nil then
        nextstate = Dfa.WORDBOUNDARY_NODE
      else
        self.isCompletion = true -- go straight to word boundary state after this match
      end
    else
      nextstate = self.dfa[Dfa.INTERNAL_NODE].transitions[charcode] or Dfa.INTERNAL_NODE -- to internals
    end
  end
  if self.debug then print(( "%d -> %s -> %d" ):format(self.state, str, nextstate)) end

  self:selectstate(nextstate)
end

function Dfa.new(states, isEndChar, maxStatesUndo, debug)
  assert(states, "Must provide states")
  assert(isEndChar, "Must pass in a function to identify end characters")
  assert(maxStatesUndo, "Must pass in a number of states to save")
  local self = {
    debug = not not debug,
    dfa = states,
    isEndChar = isEndChar,
    state = Dfa.WORDBOUNDARY_NODE,
    states = circularbuffer.new(maxStatesUndo),
    isCompletion = false, -- variable to hold state: when we've completed, we stay in the completion state, but the next move goes from the word boundary root
  }
  self = setmetatable(self, Dfa)
  return self
end

return Dfa
