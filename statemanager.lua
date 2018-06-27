StateManager = {}
StateManager.__index = StateManager

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end
local spoonPath = script_path()

local Trie = dofile(spoonPath.."/trie.lua")
local DfaFactory = dofile(spoonPath.."/dfafactory.lua")

function StateManager:getgroupid(x)
  local groupid = 1
  -- if not x.casesensitive then -- case sensitive has to have a lower number than the other for collision precedence
  --   groupid = groupid + 1
  -- end
  return groupid
end

function StateManager.new(expansions, isEndChar, maxStatesUndo, debug)
  local self = {
    dfas = {}, -- a group of DFAs to coordinate
  }
  self = setmetatable(self, StateManager)

  local expansiongroups = {}
  for k,x in pairs(expansions) do
    local groupid = self:getgroupid(x)
    if not expansiongroups[groupid] then expansiongroups[groupid] = {} end
    expansiongroups[groupid][k] = x
  end
  for k,expansions in pairs(expansiongroups) do
    local trieset = Trie.createtrieset(expansions, debug)
    local states = DfaFactory.create(trieset, isEndChar, debug)
    local dfa = Dfa.new(states, isEndChar, maxStatesUndo, debug)
    self.dfas[#self.dfas+1] = dfa
  end
  return self
end

function StateManager:getMatchingExpansion()
  for i=1,#self.dfas do
    local dfa = self.dfas[i]
    local match = dfa:getMatchingExpansion()
    if match then
      return match
    end
  end
  return nil
end

function StateManager:clear()
  for i=1,#self.dfas do
    self.dfas[i]:clear()
  end
end

function StateManager:rewindstate()
  for i=1,#self.dfas do
    self.dfas[i]:rewindstate()
  end
end

function StateManager:followedge(charcode)
  for i=1,#self.dfas do
    self.dfas[i]:followedge(charcode)
  end
end

return StateManager
