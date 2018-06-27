-- returns a closure that counts from 1 to infinity
-- used to ensure unique, dense numbering for e.g. trie nodes and DFA sets
local function makeCounter()
  local count = 0
  return function()
    count = count + 1
    return count
  end
end

return makeCounter
