-- Make a deterministic finite automaton (DFA) out of expansions

-- The output is a table of states, where each state has:
-- - transitions: a table wherein each subelement has:
--   - key: a UTF-8 character code describing the edge
--   - value: the state the edge leads to
-- - expansions: a list of expansions

-- Each expansion is included in the DFA only once, at the end state described
-- by its abbreviation.

-- Two of the states are special:
-- - State 1 is the root of the tree after a word boundary. After a completion
--   event, the state should be reset to this node.
-- - State 2 is the root state for "internal" abbreviations; that is, they can
--   occur anywhere in a word. If a transition for a given node isn't found,
--   state 2 should be checked as well.

-- Note: Internal abbreviation starts are included in other nodes only when
-- they intersect with existing transitions. For example: "btw" and internal
-- "bb" would both be included in the 1 -> b transition, but an internal "abc"
-- would not. Since 1 -> a isn't a valid transition, the caller needs to check
-- state 2's transitions as well.

-- Implementation: the expansions are first made into a trie (two tries for
-- simplicity: one for word boundary abbreviations, another for internal
-- abbreviations), which is interpreted as a non-deterministic finite automaton
-- (NFA) and then converted into a DFA.

local debug = false

List = {}
List.__index = List
function List.new ()
  local self = setmetatable({first = 0, last = -1}, List)
  return self
end

function List.empty (list)
  return list.first > list.last
end

function List.pushleft (list, value)
  local first = list.first - 1
  list.first = first
  list[first] = value
end

function List.pushright (list, value)
  local last = list.last + 1
  list.last = last
  list[last] = value
end

function List.popleft (list)
  local first = list.first
  if first > list.last then error("list is empty") end
  local value = list[first]
  list[first] = nil        -- to allow garbage collection
  list.first = first + 1
  return value
end

function List.popright (list)
  local last = list.last
  if list.first > last then error("list is empty") end
  local value = list[last]
  list[last] = nil         -- to allow garbage collection
  list.last = last - 1
  return value
end

obj = {}

obj.WORDBOUNDARY_NODE = 1
obj.INTERNAL_NODE = 2
obj.COMPLETION = "_completion"

local lasttrienode = 0 -- counter so nodes have values

function newnode()
  lasttrienode = lasttrienode + 1
  node = {value = lasttrienode}
  return node
end

function createtransition(node,k)
  if k == nil then return end
  if node.transitions == nil then node.transitions = {} end
  if node.transitions[k] == nil then node.transitions[k] = newnode() end
  return node.transitions[k]
end

local print_trie

function obj:createtries(expansions)
  local wordboundary = newnode()
  local internals = newnode()
  for abbr,exp in pairs(expansions) do
    -- add each abbreviation to the appropriate trie with exp at its leaf
    if debug then print(("Inserting abbreviation %s with expansion %s"):format(abbr, exp)) end
    local cur
    if exp.internal then
      if debug then print(("Internal %s"):format(abbr)) end
      cur = internals
    else
      cur = wordboundary
    end
    for p, c in utf8.codes(abbr) do
      cur = createtransition(cur, c)
    end
    if exp.waitforcompletionkey then
      cur = createtransition(cur, self.COMPLETION)
    end
    if cur.expansions == nil then cur.expansions = {} end
    cur.expansions[#cur.expansions + 1] = exp
  end
  if debug then print("Word boundaries:") print_trie(wordboundary) end
  if debug then print("Internals") print_trie(internals) end
  return wordboundary, internals
end

local function print_helper(trie, depth)
  if trie == nil then
    return
  end
  local preface = string.rep("-", depth)
  for key, val in pairs(trie.expansions or {}) do
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
    print_helper(val, depth + 1)
  end
end

print_trie = function(trie)
  print("Printing trie...")
  print_helper(trie, 0)
end

local lastset
local definitions
local biggestkey = ""

local function getkey(nodecollection)
  -- each node has a "value" key that is numeric and unique
  -- this function returns a value unique and consistent for a set of nodes
  local ids = {}
  for i=1,#nodecollection do
    ids[#ids+1] = nodecollection[i].value
  end
  table.sort(ids)
  local key = table.concat(ids, ":")
  if #key > #biggestkey then biggestkey = key end
  return key
end

local function getsetnumber(nodecollection)
  -- add it if necessary
  local key = getkey(nodecollection)
  local set = definitions[key]
  local new = not set
  if new then -- add it
    lastset = lastset + 1
    set = lastset
    definitions[key] = set
    if debug then print(("New node's key: %s"):format(key)) end
  end
  return set, new
end

function obj:printdfa(dfa)
  for i,state in pairs(dfa) do
    for _,x in pairs(state.expansions or {}) do
      if type(x) == "table" then
        x = x.expansion
      end
      print(("%d has %s"):format(i,x))
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
local function combinenodes(nodes, wordboundaries, internals, isEndChar)
  local expansions = {}
  local transitions = {} -- transitions[c] is the set of trie nodes that c goes to
  for _,node in pairs(nodes) do
    for k,v in pairs(node.expansions or {}) do
      expansions[#expansions+1] = v
    end
    for k,v in pairs(node.transitions or {}) do
      local key = k
      if type(key) == "number" then
        key = utf8.char(key)
      end
      if not transitions[k] then
        if node ~= internals and internals.transitions and internals.transitions[k] then
          -- evaluate starting new internals with the transition
          transitions[k] = { internals.transitions[k] }
        else
          transitions[k] = {}
        end
      end
      transitions[k][#transitions[k]+1] = v
      if isEndChar(key) then -- the root node is in this set
        if debug then print(("End char %s (%s)"):format(key,k)) end
        transitions[k][#transitions[k]+1] = wordboundaries
      end
    end
  end
  return expansions, transitions
end

local function generatedfastate(expansions, transitions, queue)
  local dfastate = {transitions = {}} -- dfastate.transitions[c] is a single set id
  for k,v in pairs(transitions) do
    local setnumber, new = getsetnumber(v)
    dfastate.transitions[k] = setnumber
    if new then
      -- add it to the queue
      queue:pushright(v)
    end
  end
  if #expansions > 0 then
    dfastate.expansions = expansions
  end
  return dfastate
end

function obj:dfa(wordboundaries, internals, isEndChar)
  local dfasets = {} -- dfasets[i] is a table containing characters containing set IDs
  lastset = 0
  definitions = {} -- defs[setkey] is the index of the set with the key
  local queue = List.new()
  local boundaryroot = { wordboundaries }
  local internalroot = { internals }
  queue:pushright(boundaryroot) -- seed the root node
  queue:pushright(internalroot) -- seed the internals node
  getsetnumber(boundaryroot) -- always gets #1 (self.WORDBOUNDARY_NODE)
  getsetnumber(internalroot) -- always gets #2 (self.INTERNAL_NODE)
  while not queue:empty() do
    local nodes = queue:popleft()
    local expansions, transitions = combinenodes(nodes, wordboundaries, internals, isEndChar)
    local dfastate = generatedfastate(expansions, transitions, queue)
    local activeset = getsetnumber(nodes)
    dfasets[activeset] = dfastate
  end
  definitions = nil
  if debug then print(("Biggest key: %s"):format(biggestkey)) end
  if debug then print(("Nodes: %s"):format(#dfasets)) end
  return dfasets
end

function obj:createdfa(expansions, isEndChar)
  local wordboundary, internals = self:createtries(expansions)
  local dfa = self:dfa(wordboundary, internals, isEndChar)
  return dfa
end

return obj
