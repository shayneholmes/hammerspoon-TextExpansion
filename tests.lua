local obj = {}

local settings = {
  {
    title = "sample",
    expansions = {aaa = "bbbb"},
    cases = {
      { title = "complete",
        input = "aaa ", expected = "bbbb " },
      { title = "incomplete",
        input = "aaa",  expected = "aaa" },
    }
  },
  {
    title = "by the way",
    expansions = {btw = "by the way"},
    cases = {
      { title = "in conversation",
        input = "btw, how are you?", expected = "by the way, how are you?" }
    }
  },
}

function obj.runtests(TextExpansion)
  print("Running tests...")
  for i=1,#settings do
    local setting = settings[i]
    for j=1,#(setting.cases or {}) do
      local case = setting.cases[j]
      print(("%s:%s"):format(setting.title or "anonymous", case.title or "anonymous"))
      TextExpansion:runtest(
        setting.expansions,
        case.input or case[1],
        case.expected or case[2],
        case.doAfters or case[3]
      )
    end
  end
  print("Tests complete.")
end

return obj
