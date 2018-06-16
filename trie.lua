-- Make a trie out of a group of expansions

obj = {}

function obj:create(expansions)
  local root = {}
  for abbr,exp in pairs(expansions) do
    -- add each abbreviation to the trie with exp at its leaf
    local cur = root
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
  for char, trie in pairs(trie) do
    if char == "expansion" then
      print(trie.expansion)
    else
      print(preface .. utf8.char(char))
      print_helper(trie, depth + 1)
    end
  end
end

function obj:print(trie)
  print_helper(trie, 0)
end

return obj
