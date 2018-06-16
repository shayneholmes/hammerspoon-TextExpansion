-- Make a trie out of a group of expansions

obj = {}

function obj:create(expansions)
  local root = {}
  root["wordboundary"] = {}
  for abbr,exp in pairs(expansions) do
    -- add each abbreviation to the trie with exp at its leaf
    local cur = root
    if exp.internal then
      cur = cur["wordboundary"]
    end
    for p, c in utf8.codes(abbr) do
      if cur[c] == nil then
        cur[c] = {}
      end
      cur = cur[c]
    end
    cur["expansion"] = exp
  end
  return root
end

local function print_helper(trie, depth)
  if trie == nil then
    return
  end
  local preface = string.rep("-", depth)
  for key, val in pairs(trie) do
    if key == "expansion" then
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

return obj
