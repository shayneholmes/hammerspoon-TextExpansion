-- Make a deterministic finite automaton (DFA) out of tries representing an NFA

-- The output is a table of states, where each state has:
-- - transitions: a table wherein each subelement has:
--   - key: a UTF-8 character code describing the edge
--   - value: the state the edge leads to
-- - expansion: the highest priority expansion at this state

-- Each expansion is included in the DFA only once, at the end state described
-- by its abbreviation.

-- Two of the states are special:
-- - State Dfa.WORDBOUNDARY_NODE is the root of the tree after a word
--   boundary. After a completion event, the state should be reset to this node.
-- - State Dfa.INTERNAL_NODE is the root state for "internal"
--   abbreviations; that is, they can occur anywhere in a word. If a transition
--   for a given node isn't found, this state should be checked as well.

-- Note: Internal abbreviation starts are included alongside other nodes, but
-- only when they intersect with existing transitions. For example: with three
-- abbreviations "abc", "bad" (internal) and "cab" (internal), "bad" would be
-- included in the "a" -> b transition, but "cab" would not, because "a" -> c
-- doesn't exist. When the transition isn't found, the caller needs to check
-- the internal transitions as well.

local DfaFactory = {}
DfaFactory.__index = DfaFactory

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end
local spoonPath = script_path()

local List = dofile(spoonPath.."/list.lua")
local makeCounter = dofile(spoonPath.."/counter.lua")
local Dfa = dofile(spoonPath.."/dfa.lua")

local biggestkey = 0

local max = 2^61-1
local hashmult = nil -- set below once trie size is known
function DfaFactory:getkey(nodecollection)
  -- each Trie has a "value" key that is numeric and unique
  -- this function returns a value that is probably unique, and consistent for a set of nodes
  -- assumes that nodes fall in the same order each time, which seems to hold based on hierarchical nature of trees
  -- if the node order changes, the outcome is that more DFA states will be created than necessary
  local key = 0
  for i=1,#nodecollection do
    key = key * hashmult + nodecollection[i].value
    while key > max do key = key - max end
  end
  if key > biggestkey then biggestkey = key end
  return key
end

function DfaFactory:getsetnumber(nodecollection)
  -- add it if necessary
  local key = self:getkey(nodecollection)
  local set = self.setnumbers[key]
  local new = not set
  if new then -- add it
    set = self.getnextsetnumber()
    self.setnumbers[key] = set
    if self.debug then print(("New node's key: %s"):format(key)) end
  end
  return set, new
end

function DfaFactory:print()
  for i=1,#self.states do
    local state = self.states[i]
    if state.expansion then
      print(("%d has %s"):format(i,state.expansion.expansion))
    end
    for edge, j in pairs(state.transitions or {}) do
      local label = edge
      if type(label) == "number" then
        label = utf8.char(label)
      end
      print(("%d -> %s -> %d"):format(i,label,j))
    end
  end
end

-- Combine all expansions and transitions from the indicated nodes
--
-- Factor in internal and wordboundaries; they're included in the resulting combined transitions.
function DfaFactory:combinenodes(nodes)
  local expansions = {}
  local transitions = {} -- transitions[c] is the set of trie nodes that c goes to
  for i=1,#nodes do
    local node = nodes[i]
    if node.expansions then
      for j=1,#node.expansions do
        expansions[#expansions+1] = node.expansions[j]
      end
    end
    for k,v in pairs(node.transitions or {}) do
      local key = k
      if type(key) == "number" then
        key = utf8.char(key)
      end
      if not transitions[k] then
        if node ~= self.internals and self.internals.transitions and self.internals.transitions[k] then
          -- evaluate starting new internals with the transition
          transitions[k] = { self.internals.transitions[k] }
        else
          transitions[k] = {}
        end
      end
      transitions[k][#transitions[k]+1] = v
      if self.isEndChar(k) then -- also consider word boundaries starting here
        if self.debug then print(("End char %s (%s)"):format(key,k)) end
        transitions[k][#transitions[k]+1] = self.wordboundary
      end
    end
  end
  return expansions, transitions
end

-- Make a DFA state from the combined nodes
-- Choose the expansion with highest priority to store here
function DfaFactory:generatestate(expansions, transitions)
  local state = {transitions = {}} -- state.transitions[c] is a single set id
  for k,v in pairs(transitions) do
    local setnumber, new = self:getsetnumber(v)
    state.transitions[k] = setnumber
    if new then
      -- add it to the queue
      self.queue:pushright(v)
    end
  end
  if #expansions > 0 then
    local best = expansions[1] -- highest priority
    for i=2,#expansions do
      local x = expansions[i]
      if x:takesPriorityOver(best) then best = x end
    end
    state.expansion = best
  end
  return state
end

-- Return a DFA based on the NFA represented by the trie set
function DfaFactory.create(trieset, isEndChar, debug)
  assert(trieset and trieset.wordboundary and trieset.internals, "Trie set must have word boundaries and internals.")
  assert(type(isEndChar) == "function", "Must pass in a function to identify end characters")

  local self = {
    debug = not not debug,
    getnextsetnumber = makeCounter(),
    states = {}, -- states[i] for i=1,n is a table containing set ID values, keyed by characters
    setnumbers = {}, -- temporary table to hold set numbers by key (only used in construction)
    queue = List.new(),
    internals = trieset.internals,
    wordboundary = trieset.wordboundary,
    isEndChar = isEndChar,
  }
  hashmult = trieset.wordboundary.getnextvalue() -- a bit of an abuse
  self = setmetatable(self, DfaFactory)

  local boundaryset = { self.wordboundary }
  local internalset = { self.internals }
  self.queue:pushright(boundaryset) -- seed the boundary set
  self.queue:pushright(internalset) -- seed the internals set
  assert(self:getsetnumber(boundaryset) == Dfa.WORDBOUNDARY_NODE, "Word boundary set must have correct number")
  assert(self:getsetnumber(internalset) == Dfa.INTERNAL_NODE, "Internal set must have correct number")
  while not self.queue:empty() do
    local nodes = self.queue:popleft()
    local expansions, transitions = self:combinenodes(nodes)
    local state = self:generatestate(expansions, transitions)
    local activeset = self:getsetnumber(nodes)
    self.states[activeset] = state
  end
  if self.debug then print(("Biggest key: %s"):format(biggestkey)) end
  if self.debug then print(("Nodes: %s"):format(#self.states)) end
  if self.debug then self:print() end

  return self.states
end

return DfaFactory
