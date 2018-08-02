local obj = {}

local counter = function() -- closure for function tests
  local counter = 0
  return function()
    counter = counter + 1 return ("%s"):format(counter)
  end
end

local function concatTables(t1,t2)
  for i=1,#t2 do
    t1[#t1+1] = t2[i]
  end
  return t1
end

local apiTests = {
  {
    title = "doesn't start without init",
    func = function(te) te:start() end,
    err = true,
  },
  {
    title = "starting works after init",
    func = function(te) te:init():start() end,
    err = false,
  },
  {
    title = "starting twice in a row is fine",
    func = function(te) te:init():start():start() end,
    err = false,
  },
  {
    title = "no errors stopping before init",
    func = function(te) te:stop() end,
    err = false,
  },
  {
    title = "no errors stopping before start",
    func = function(te) te:init():stop() end,
    err = false,
  },
  {
    title = "stop works after start",
    func = function(te) te:init():start():stop() end,
    err = false,
  },
  {
    title = "start works after stop",
    func = function(te) te:init():start():stop():start() end,
    err = false,
  },
}

local hotstringTests = {
  {
    title = "empty set",
    expansions = {},
    cases = {
      { title = "nothing happens",
        input = "nothing goes in ", expected = "nothing goes in " },
    }
  },
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
    title = "cross-word boundaries",
    expansions = {
      ["doe snot"] = "does not",
      ["tt"] = "test",
    },
    cases = {
      { title = "baseline",
        input = "doe snot tt ", expected = "does not test " },
      { title = "interruption on the word boundary",
        input = "doe tt ", expected = "doe test " },
      { title = "abbreviations don't generalize end chars",
        input = "doe-snot ", expected = "doe-snot " },
      { title = "word boundaries do generalize end chars",
        input = "doe-tt ", expected = "doe-test " },
    }
  },
  {
    title = "functions",
    expansions = {
      simple = function() return "output" end,
      int = function() return 54 // 3 end,
      float = function() return 54 / 3 end,
      counter = counter(),
    },
    cases = {
      { title = "string function",
        input = "simple ", expected = "output " },
      { title = "integer function",
        input = "int ", expected = "18 " },
      { title = "float function",
        input = "float ", expected = "18.0 " },
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
      missingcompletion = {
        expansion = "No space after me.",
        waitforcompletionkey = true,
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
      { title = "excludes completion key even when waiting",
        input = "missingcompletion ", expected = "No space after me." },
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
        title = "an internal gets replaced at a word boundary",
        input = "11111 ",
        expected = "X ",
      },
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
  },
  {
    title = "case sensitivity",
    expansions = {
      lower = { expansion = "x", matchcase = false, },
      UPPER = "Y",
      collision = "lower",
      Collision = { expansion = "upper", casesensitive = true, },
    },
    cases = {
      {
        title = "lowercase",
        input = "lower ", expected = "x ",
      },
      {
        title = "lowercase typed upper still triggers",
        input = "LOWER ", expected = "x ",
      },
      {
        title = "uppercase",
        input = "UPPER ", expected = "Y ",
      },
      {
        title = "uppercase typed lower is as specified",
        input = "upper ", expected = "Y ",
      },
      {
        title = "case sensitive ones win",
        input = "Collision ", expected = "upper ",
      },
      {
        title = "case insensitive trigger",
        input = "coLLiSiON ", expected = "lower ",
      },
    },
  },
  {
    title = "match case",
    expansions = {
      btw = { expansion = "by the way", matchcase = true },
      CASESENSITIVE = { expansion = "case sensitive", matchcase = true, casesensitive = true },
      [ "8ball" ] = { expansion = "eight ball", matchcase = true },
      eightyfour = { expansion = "8-four", matchcase = true },
      name = { expansion = "Jefferson", matchcase = true },
      t = { expansion = "test", matchcase = true },
      v = { expansion = "test", matchcase = true },
      Y = { expansion = "YES", casesensitive = true },
      ["80b"] = { expansion = "test", matchcase = true }
    },
    cases = {
      { title = "first caps",
        input = "Hey. Btw, how are you?", expected = "Hey. By the way, how are you?" },
      { title = "all caps",
        input = "Hey. BTW, how are you?", expected = "Hey. BY THE WAY, how are you?" },
      { title = "all lower",
        input = "Hey. btw, how are you?", expected = "Hey. by the way, how are you?" },
      { title = "first and others caps",
        input = "Hey. BTw, how are you?", expected = "Hey. By the way, how are you?" },
      { title = "not first but others",
        input = "Hey. bTW, how are you?", expected = "Hey. by the way, how are you?" },
      { title = "case sensitive works",
        input = "CASESENSITIVE ", expected = "case sensitive " },
      { title = "ignored when wrong case b/c case sensitive",
        input = "CASESENSITIVe ", expected = "CASESENSITIVe " },
      { title = "first cap keys off first caseable",
        input = "8Ball ", expected = "Eight ball " },
      { title = "all caps works with first number",
        input = "8BALL ", expected = "EIGHT BALL " },
      { title = "can't capitalize first char",
        input = "Eightyfour ", expected = "8-four " },
      { title = "can capitalize the rest",
        input = "EIGHTYFOUR ", expected = "8-FOUR " },
      { title = "name not affected when small",
        input = "name ", expected = "Jefferson " },
      { title = "name not affected by firstcap",
        input = "Name ", expected = "Jefferson " },
      { title = "name gets all caps",
        input = "NAME ", expected = "JEFFERSON " },
      { title = "single char capitalizes first",
        input = "T ", expected = "Test " },
      { title = "one caseable gives first cap",
        input = "80B ", expected = "Test " },
      { title = "one-character baseline",
        input = "v ", expected = "test " },
      { title = "one-character capitalized gives first-cap",
        input = "V ", expected = "Test " },
      { title = "work around one-character limits with case sensitivity",
        input = "Y ", expected = "YES " },
    }
  },
  { title = "internals starting with end chars",
    expansions = {
      ["/yd"] = { expansion = "yard", internal = true },
    },
    cases = {
      { title = "expands at word boundaries",
        input = "/yd ", expected = "yard " },
      { title = "expands in a word",
        input = "5/yd ", expected = "5yard " },
      { title = "expands after other end chars",
        input = "5-/yd ", expected = "5-yard " },
    }
  },
  {
    title = "collisions and precedence",
    expansions = {
      ["/yd"] = { expansion = "yard", internal = true },
      ["yd"] = "yesterday",
      ["yard"] = { expansion = "longer", internal = true },
      ["ard"] = { expansion = "shorter", internal = true },
      ["yard1"] = { expansion = "longer", internal = true },
      ["ard1"] = { expansion = "shorter", internal = true, priority = 1, },
      ["word"] = { expansion = "inner", internal = true },
      ["Word"] = { expansion = "outer", internal = false },
      ["word1"] = { expansion = "inner", internal = true, priority = 1, },
      ["Word1"] = { expansion = "outer", internal = false },
      ["CS1"] = { expansion = "sensitive", internal = true, casesensitive = true, },
      ["cs1"] = { expansion = "insensitive", internal = true, casesensitive = false, },
      ["cs2"] = { expansion = "insensitive", priority = 1, internal = true, casesensitive = false, },
      ["CS2"] = { expansion = "sensitive", internal = true, casesensitive = true, },
    },
    cases = {
      { title = "longer abbreviation wins",
        input = "/yd ", expected = "yard " },
      { title = "longer abbreviation wins",
        input = "backyard backnard ", expected = "backlonger backnshorter " },
      { title = "higher priority wins over longer",
        input = "backyard1 ", expected = "backyshorter " },
      { title = "word boundary wins over internal",
        input = "word zword z-word ", expected = "outer zinner z-outer " },
      { title = "higher priority wins over word boundary",
        input = "word1 zword1 z-word1 ", expected = "inner zinner z-inner " },
      { title = "case sensitive: case sensitive wins in a conflict",
        input = "Cs1 CS1 ", expected = "Insensitive sensitive " },
      { title = "higher priority wins over case sensitivity",
        input = "CS2 ", expected = "INSENSITIVE " }, -- case matching
    }
  },
  {
    title = "word boundaries mid-expansion",
    expansions = {
      ["aa-aa-aa"] = { expansion = "aaa", internal = false, },
      ["aa-aab"] = { expansion = "bbb", internal = false, },
      ["aac"] = { expansion = "ccc", internal = false, },
      ["-aac"] = { expansion = "dashed", internal = false, },
      ["-aab"] = { expansion = "dashed2", internal = true, },
    },
    cases = {
      { title = "full",
        input = "aa-aa-aa ", expected = "aaa " },
      { title = "forked word boundary",
        input = "aa-aa-aab ", expected = "aa-bbb " },
      { title = "forked internal",
        input = "aazzaa-aab ", expected = "aazzaadashed2 " },
      { title = "forked",
        input = "aa(aa-aab ", expected = "aa(bbb " },
      { title = "forked with dashed",
        input = "aa-aa--aac ", expected = "aa-aa-dashed " },
      { title = "forked again",
        input = "aa-aa-aac ", expected = "aa-aa-ccc " },
      { title = "hidden",
        input = "aa-aab ", expected = "bbb " },
      { title = "hidden forked",
        input = "aa-aac ", expected = "aa-ccc " },
      { title = "dashed solo",
        input = "-aac ", expected = "dashed " },
      { title = "dashed after whitespace",
        input = "test-aab ", expected = "testdashed2 " },
      { title = "even hiddener",
        input = "aac ", expected = "ccc " },
    }
  },
  {
    title = "find suffixes",
    expansions = {
      ["aaa"] = { expansion = "3", internal = false, backspace = false, },
      ["aa"] = { expansion = "2", internal = true, backspace = false, },
      ["a"] = { expansion = "1", internal = true, backspace = false, waitforcompletionkey = false, sendcompletionkey = true, },
    },
    cases = {
      { title = "triggers longer of the shorters",
        input = "aa ", expected = "a1a12 " },
      { title = "triggers longest when availabale",
        input = "aaa ", expected = "a1a1a13 " },
      { title = "triggers after items that aren't in the tree at all",
        input = "azzaa ", expected = "a1zza1a12 " },
    }
  },
  {
    title = "incremental matches",
    expansions = {
      ["a"] = { expansion = "1", internal = true, backspace = false, waitforcompletionkey = false, sendcompletionkey = true, },
      ["aa"] = { expansion = "2", internal = true, backspace = false, waitforcompletionkey = false, sendcompletionkey = true, },
      ["aaa"] = { expansion = "3", internal = true, backspace = false, waitforcompletionkey = false, sendcompletionkey = true, },
      ["aaaaa"] = { expansion = "5", internal = true, backspace = false, waitforcompletionkey = false, sendcompletionkey = true, },
    },
    cases = {
      { title = "triggers longer of the shorters",
        input = "aa ", expected = "a1a2 " },
      { title = "triggers after items that aren't in the tree at all",
        input = "azzaa zzaaaaa ", expected = "a1zza1a2 zza1a2a3a3a5 " },
    }
  },
  {
    title = "consecutive expansions",
    expansions = {
    ["aaa"] = { expansion = "bbb", internal = true, waitforcompletionkey = false, sendcompletionkey = false },
    },
    cases = {
      { title = "just one",
        input = "aaa", expected = "bbb" },
      { title = "two in a row",
        input = "aaaa", expected = "bbbb" },
    }
  },
  {
    title = "nil functions",
    expansions = {
      ["aaa"] = function() return nil end,
    },
    cases = {
      { title = "backspacing",
        input = "aaa ", expected = " " },
    }
  },
}

local testDeferredAction
local function testDefer(func)
  assert(not testDeferredAction, "Only one deferred action at a time")
  testDeferredAction = func
end

local function testResolveDeferred()
  if testDeferredAction then
    testDeferredAction()
    testDeferredAction = nil
  end
end

local testMocked
local function setMocks()
  assert(not testMocked, "Can't setup tests twice!")
  testMocked = {
    hs = hs,
  }
  hs = {
    eventtap = {
      keyStrokes = function(str) -- add strokes to output
        testOutput[#testOutput+1] = str
      end,
      keyStroke = function() -- remove strokes from output
        if testOutput[#testOutput]:len() == 1 then
          testOutput[#testOutput] = nil
        else
          testOutput[#testOutput] = testOutput[#testOutput]:sub(1,-2)
        end
      end,
      new = function()
        local enabled = false
        return {
          stop = function() enabled = true end,
          start = function() enabled = false end,
          isEnabled = function() return enabled end,
        }
      end,
      event = { types = { keyDown = nil } },
    },
    keycodes = {
      map = setmetatable({}, {__index = function() return 1 end}) -- shameless mock
    },
    timer = {
      doAfter = function(_, func) testDefer(func) end,
    },
  }
end

local function unsetMocks()
  assert(testMocked, "Test mode must already be set up to tear it down")
  hs = testMocked.hs
  testMocked = nil
end

local function getTextExpansion()
  setMocks()
  local te = require('init')
  te.timeoutSeconds = 0 -- disable timeout doAfters
  return te
end

local function testRun(te, input, expected, repeatlength)
  assert(testMocked, "Test mode must be enabled to run a test")
  repeatlength = repeatlength or string.len(input)
  testOutput = {}
  testDoAfter = nil
  te:resetAbbreviation()
  local getFlags = {cmd = false}
  local nextchar
  local ev = {
    getKeyCode = function() return " " end,
    getFlags = function() return getFlags end,
    getCharacters = function() return nextchar end,
  }
  local charsSent = 0
  local function sendchar(char)
    if charsSent >= repeatlength then return end
    nextchar = char
    local eat = te:handleEvent(ev)
    if not eat then
      testOutput[#testOutput+1] = char
    end
    testResolveDeferred()
    charsSent = charsSent + 1
  end

  while (charsSent < repeatlength) do
    string.gsub(input, ".", sendchar)
  end

  assert(testDoAfter == nil, "Must be no remaining delayed calls")
  testOutput = table.concat(testOutput)
  assert(not expected or expected == testOutput,
    ("Output for input \"%s\": Expected: \"%s\", actual: \"%s\""):format(input, expected, testOutput))
end

local function runApiTests()
  local failed = {}
  print("Running API tests...")
  for i=1,#apiTests do
    local te = getTextExpansion()
    local case = apiTests[i]
    local caseTitle = case.title or "anonymous"
    print(("%s"):format(caseTitle))
    local func = case.func or function() end
    local errorExpected = not not case.err
    local status, err = pcall(func, te)
    local errorReceived = not status
    if errorReceived ~= errorExpected then
      local expected, actual
      actual = err or "no error"
      if errorExpected then expected = "an error" else expected = "no error" end
      print(("Failed: expected %s, got '%s'"):format(expected, actual))
      failed[#failed+1] = caseTitle
    end
    unsetMocks()
  end
  return failed
end

local function runHotstringTests(te)
  local failed = {}
  print("Running hostring tests...")
  local te = getTextExpansion()
  te:init()
  for i=1,#hotstringTests do
    local setting = hotstringTests[i]
    te:setExpansions(setting.expansions)
    for j=1,#(setting.cases or {}) do
      local case = setting.cases[j]
      print(("%s: %s"):format(setting.title or "anonymous", case.title or "anonymous"))
      local status, err = pcall(function()
        testRun(
          te,
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
  unsetMocks()
  return failed
end

function obj.runtests()
  local failed = {}
  failed = concatTables(failed, runApiTests())
  failed = concatTables(failed, runHotstringTests())
  print("Tests complete.")
  if #failed > 0 then
    print(("%d failed."):format(#failed))
  else
    print("All passed.")
  end
  return failed
end

function obj.testPerformance()
  local te = getTextExpansion()
  te:init()

  -- parameters
  local expansionsSizes = {
    10,
    100,
    1000,
    10000,
    100000,
  }
  local inputSizes = {
    10,
    100,
    1000,
    10000,
    100000,
  }
  local attempts = 10 -- smooth out benchmarking

  -- fixtures
  for _, testExpansionsSize in pairs(expansionsSizes) do
    local testExpansions = {}
    for i=1,testExpansionsSize do
      local key = ("abbreviation%d"):format(i)
      local value = ("expansion%d"):format(i)
      testExpansions[key] = value
    end


    -- init test
    for _=1,attempts do
      collectgarbage()
      local initStart = os.clock()
      te:setExpansions(testExpansions)
      local initEnd = os.clock()
      print(("init, %d, %f"):format(
        testExpansionsSize,
        initEnd - initStart
      ))
    end

    for _, testInputSize in pairs(inputSizes) do
      local testInput = "abbreviation1 abbreviation2 and some other text that doesn't get expanded "
      for _=1,attempts do
        collectgarbage()
        local inputStart = os.clock()
        testRun(te, testInput, nil, testInputSize)
        local inputEnd = os.clock()
        print(("input, %d, %d, %f"):format(
          testExpansionsSize,
          testInputSize,
          inputEnd - inputStart
        ))
      end
    end
  end
  unsetMocks()
end

return obj
