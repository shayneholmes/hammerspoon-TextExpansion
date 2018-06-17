-- Make a trie out of a group of expansions

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

function obj:create(expansions)
  local root = {}
  root["wordboundary"] = {}
  root["internal"] = {}
  for abbr,exp in pairs(expansions) do
    -- add each abbreviation to the trie with exp at its leaf
    local cur = root
    if exp.internal then
      cur = cur["internal"]
    else
      cur = cur["wordboundary"]
    end
    for p, c in utf8.codes(abbr) do
      if cur[c] == nil then cur[c] = {} end
      cur = cur[c]
    end
    if exp.waitforcompletionkey then
      if cur["_completion"] == nil then cur["_completion"] = {} end
      cur = cur["_completion"]
    end
    cur["_expansion"] = exp
  end
  return root
end

local function print_helper(trie, depth)
  if trie == nil then
    return
  end
  local preface = string.rep("-", depth)
  for key, val in pairs(trie) do
    if key == "_expansion" then
      print(val.expansion)
    else
      local label = key
      if type(label) == "number" then
        label = utf8.char(label)
      end
      print(preface .. label)
      print_helper(val, depth + 1)
    end
  end
end

function obj:print(trie)
  print_helper(trie, 0)
end

local dfssets
local lastset
local definitions
local wordboundaries
local internals

local function getkey(nodes)
  local ids = {}
  for k,v in pairs(nodes) do
    ids[#ids+1] = ("%s"):format(v)
  end
  table.sort(ids)
  return table.concat(ids,",")
end

local function getsetnumber(nodecollection)
  -- add it if necessary
  local key = getkey(nodecollection)
  local set = definitions[key]
  local new = false
  if not set then -- it's new, add it
    new = true
    lastset = lastset + 1
    set = lastset
    definitions[key] = set
    -- print(("Adding new set %d for key '%s'"):format(set,key))
  else
    -- print(("Reusing set %d for key '%s'"):format(set,key))
  end
  -- print(("Returning %s, %s"):format(set,new))
  return set, new
end

function obj:printdfs(dfs)
  for i,transitions in pairs(dfs) do
    for edge,v in pairs(transitions) do
      if edge == "_expansions" then
        if type(v) == "table" then
          for _,v in pairs(v) do
            print(("%d has %s"):format(i,v.expansion))
          end
        else
          print(("%d has %s"):format(i,v))
        end
      else
        if type(edge) == "number" then
          print(("%d -> %s -> %d"):format(i,utf8.char(edge),v))
        else
          print(("%d -> %s -> %d"):format(i,edge,v))
        end
      end
    end
  end
end

function obj:dfs(trie)
  dfssets = {} -- dfssets[i] is a table containing characters containing set IDs
  lastset = 0
  definitions = {} -- defs[setkey] is the index of the set with the key
  wordboundaries = trie["wordboundary"] -- can only start from set 1
  internals = trie["internal"] -- can start from any set
  local queue = List.new()
  local boundaryroot = { wordboundaries }
  local internalroot = { internals }
  getsetnumber(boundaryroot) -- add it as set #1
  queue:pushright(boundaryroot) -- seed the root node
  getsetnumber(internalroot) -- add it as set #2
  queue:pushright(internalroot) -- seed the internals node
  while not queue:empty() do
    local nodes = queue:popleft()
    local activeset = getsetnumber(nodes)
    -- print(("Considering set %s"):format(getkey(nodes)))
    local expansions = {}
    local transitions = {} -- transitions[c] is the set of trie nodes that c goes to
    for _,node in pairs(nodes) do
      for k,v in pairs(node) do
        if k == "_expansion" then
          -- print("Expansion; skipping")
          expansions[#expansions+1] = v
        else
          local key = k
          if type(key) == "number" then
            key = utf8.char(key)
          end
          -- print(("Adding transition %s"):format(key))
          if not transitions[k] then
            transitions[k] = {v}
          else
            transitions[k][#transitions[k]+1] = v
          end
        end
      end
    end
    local dfsedges = {} -- dfsedges[c] is a single set id
    for k,v in pairs(transitions) do
      if internals[k] then -- always evaluate starting new internals
        -- print(("Adding internal starter %s"):format(utf8.char(k)))
        v[#v+1] = internals[k]
      end
      local setnumber, new = getsetnumber(v)
      -- print(("Got %s, %s"):format(setnumber,new))
      dfsedges[k] = setnumber
      -- if new, add it to the queue
      if new then
        -- print(("Adding set %d to queue"):format(setnumber))
        queue:pushright(v)
      end
    end
    dfsedges["_expansions"] = expansions
    dfssets[activeset] = dfsedges
  end
  lastset = 0
  definitions = nil
  return dfssets
end

return obj
