local obj = {}

local counter = function() -- closure for function tests
  local counter = 0
  return function()
    counter = counter + 1 return ("%s"):format(counter)
  end
end

local settings = {
  {
    title = "sample",
    expansions = {aaa = "bbbb"},
    cases = {
      { title = "complete",
        input = "aaa ", expected = "bbbb " },
      { title = "after word space",
        input = "t aaa ", expected = "t bbbb " },
      { title = "incomplete",
        input = "aaa",  expected = "aaa" },
      { title = "suffixed",
        input = "aaat",  expected = "aaat" },
      { title = "ended with @",
        input = "to:aaa@example.com ", expected = "to:bbbb@example.com " },
    }
  },
  {
    title = "by the way",
    expansions = {btw = "by the way"},
    cases = {
      { title = "in conversation",
        input = "btw, how are you?", expected = "by the way, how are you?" },
    }
  },
  {
    title = "functions",
    expansions = {
      counter = counter(),
      simple = function() return "output" end,
    },
    cases = {
      { title = "function is called",
        input = "simple ", expected = "output " },
      { title = "function is called each time it's referenced",
        input = "counter counter counter ", expected = "1 2 3 " },
    }
  },
  {
    title = "completion keys",
    expansions = {
      earlycomplete = {
        expansion = "Right away!",
        waitforcompletionkey = false,
        sendcompletionkey = true,
      },
      withoutcompletion = {
        expansion = "Right away!",
        waitforcompletionkey = false,
        sendcompletionkey = false,
      },
      ban = {
        expansion = "ana",
        waitforcompletionkey = false,
        sendcompletionkey = true,
        backspace = false,
      },
    },
    cases = {
      { title = "includes completion key",
        input = "earlycomplete", expected = "Right away!e" },
      { title = "excludes completion key",
        input = "withoutcompletion", expected = "Right away!" },
      { title = "endkey ordering",
        input = "ban", expected = "banana" },
    }
  },
  {
    title = "flag combinations",
    expansions = {


      ["00000"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = false, sendcompletionkey = false, waitforcompletionkey = false },
      ["00001"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = false, sendcompletionkey = false, waitforcompletionkey = true  },
      ["00010"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = false, sendcompletionkey = true , waitforcompletionkey = false },
      ["00011"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = false, sendcompletionkey = true , waitforcompletionkey = true  },
      ["00100"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = true , sendcompletionkey = false, waitforcompletionkey = false },
      ["00101"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = true , sendcompletionkey = false, waitforcompletionkey = true  },
      ["00110"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = true , sendcompletionkey = true , waitforcompletionkey = false },
      ["00111"] = { expansion = "X", internal = false, resetrecognizer = false, backspace = true , sendcompletionkey = true , waitforcompletionkey = true  },
      ["01000"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = false, sendcompletionkey = false, waitforcompletionkey = false },
      ["01001"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = false, sendcompletionkey = false, waitforcompletionkey = true  },
      ["01010"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = false, sendcompletionkey = true , waitforcompletionkey = false },
      ["01011"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = false, sendcompletionkey = true , waitforcompletionkey = true  },
      ["01100"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = true , sendcompletionkey = false, waitforcompletionkey = false },
      ["01101"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = true , sendcompletionkey = false, waitforcompletionkey = true  },
      ["01110"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = true , sendcompletionkey = true , waitforcompletionkey = false },
      ["01111"] = { expansion = "X", internal = false, resetrecognizer = true , backspace = true , sendcompletionkey = true , waitforcompletionkey = true  },
      ["10000"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = false, sendcompletionkey = false, waitforcompletionkey = false },
      ["10001"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = false, sendcompletionkey = false, waitforcompletionkey = true  },
      ["10010"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = false, sendcompletionkey = true , waitforcompletionkey = false },
      ["10011"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = false, sendcompletionkey = true , waitforcompletionkey = true  },
      ["10100"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = true , sendcompletionkey = false, waitforcompletionkey = false },
      ["10101"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = true , sendcompletionkey = false, waitforcompletionkey = true  },
      ["10110"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = true , sendcompletionkey = true , waitforcompletionkey = false },
      ["10111"] = { expansion = "X", internal = true , resetrecognizer = false, backspace = true , sendcompletionkey = true , waitforcompletionkey = true  },
      ["11000"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = false, sendcompletionkey = false, waitforcompletionkey = false },
      ["11001"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = false, sendcompletionkey = false, waitforcompletionkey = true  },
      ["11010"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = false, sendcompletionkey = true , waitforcompletionkey = false },
      ["11011"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = false, sendcompletionkey = true , waitforcompletionkey = true  },
      ["11100"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = true , sendcompletionkey = false, waitforcompletionkey = false },
      ["11101"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = true , sendcompletionkey = false, waitforcompletionkey = true  },
      ["11110"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = true , sendcompletionkey = true , waitforcompletionkey = false },
      ["11111"] = { expansion = "X", internal = true , resetrecognizer = true , backspace = true , sendcompletionkey = true , waitforcompletionkey = true  },

    },
    cases = {
      {
        title = "an internal gets replaced when prefixed",
        input = "t11111 ",
        expected = "tX ",
      },
      {
        title = "all internals get replaced when prefixed",
        input = "t10000 t10001 t10010 t10011 t10100 t10101 t10110 t10111 t11000 t11001 t11010 t11011 t11100 t11101 t11110 t11111 ",
        expected = "t1000X t10001Xt10010X t10011X tX tXtX0 tX t1100X t11001Xt11010X t11011X tX tXtX0 tX ",
      },
      {
        title = "non-internals don't get replaced when prefixed",
        input = "t00000  t00001  t00010  t00011  t00100  t00101  t00110  t00111  t01000  t01001  t01010  t01011  t01100  t01101  t01110  t01111 ",
        expected = "t00000  t00001  t00010  t00011  t00100  t00101  t00110  t00111  t01000  t01001  t01010  t01011  t01100  t01101  t01110  t01111 ",
      },
      {
        title = "a non-waiter gets replaced when suffixed",
        input = "00000t",
        expected = "0000Xt"
      },
      {
        title = "all non-waiters get replaced when suffixed",
        input = "00000t 00010t  00100t  00110t  01000t  01010t  01100t  01110t  10000t  10010t  10100t  10110t  11000t  11010t  11100t  11110t ",
        expected = "0000Xt 00010Xt  Xt  X0t  0100Xt  01010Xt  Xt  X0t  1000Xt  10010Xt  Xt  X0t  1100Xt  11010Xt  Xt  X0t "
      },
      {
        title = "no waiters get replaced when suffixed",
        input = "00001t  00011t  00101t  00111t  01001t  01011t  01101t  01111t  10001t  10011t  10101t  10111t  11001t  11011t  11101t  11111t ",
        expected = "00001t  00011t  00101t  00111t  01001t  01011t  01101t  01111t  10001t  10011t  10101t  10111t  11001t  11011t  11101t  11111t "
      },
    }
  }
}

function obj.runtests(TextExpansion)
  TextExpansion:testSetup()
  print("Running tests...")
  local failed = {}
  for i=1,#settings do
    local setting = settings[i]
    TextExpansion:testSetContext(setting.expansions)
    for j=1,#(setting.cases or {}) do
      local case = setting.cases[j]
      print(("%s:%s"):format(setting.title or "anonymous", case.title or "anonymous"))
      local status, err = pcall(function()
        TextExpansion:testRun(
          case.input or case[1],
          case.expected or case[2]
        )
      end)
      if not status then
        print(err)
        failed[#failed+1] = err
      end
    end
  end
  TextExpansion:testTeardown()
  print("Tests complete.")
  if #failed > 0 then
    print(("%d failed."):format(#failed))
  else
    print("All passed.")
  end
  return failed
end

return obj
