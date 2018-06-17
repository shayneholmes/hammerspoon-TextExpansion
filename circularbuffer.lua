obj = {}

local bufferSize
local array -- table of size bufferSize
local head -- array[head] is the space after the last item
local tail -- array[tail] is the first item
local count
local debug -- set to true to get debug spew

local function mod(n)
  -- keep n between 1 and bufferSize, inclusive
  return (n - 1) % bufferSize + 1
end

local function inc(n)
  return mod(n + 1)
end

local function dec(n)
  return mod(n - 1)
end

local function asserts()
  actualSize = head - tail
  if actualSize < 0 then
    actualSize = actualSize + bufferSize
  end
  assert(actualSize == count)
  assert(0 <= count)
  assert(count < bufferSize)
  print(( "count: %d" ):format(count))
  print(( "head: %d" ):format(head))
  print(( "top: %s" ):format(array[mod(head-1)]))
end

function obj:init(size)
  if not (size and size > 0) then
    print("Error: Size must be a positive integer!")
    return
  end
  bufferSize = size
  array = {}
  head = 1
  tail = head
  count = 0
end

function obj:getHead()
  if count == 0 then
    return nil
  end
  return array[mod(head-1)]
end

function obj:getChars(offset) -- starting at head-offset
  assert(offset <= count, "offset must be less than count")
  assert(offset >= 0, "offset must be at least zero")
  local slice = {}
  local cur = mod(head-offset)
  while cur ~= head do
    slice[#slice+1] = array[cur]
    cur = inc(cur)
  end
  if debug then asserts() end
  return utf8.char(table.unpack(slice))
end

function obj:getAll()
  return self:getChars(count)
end

function obj:matches(str, pos)
  -- pos is an offset from the end
  local len = utf8.len(str)
  local start = mod(head - len - pos)
  if len + pos > count then
    return false
  end
  local cur = start
  for p, c in utf8.codes(str) do
    if debug then print(("array[%d] = %d <-> %d = str[%d]"):format(cur, array[cur] or 0, c, p)) end
    if array[cur] ~= c then
      return false
    end
    cur = inc(cur)
  end
  return true
end

function obj:push(data)
  array[head] = data
  head = inc(head)
  if tail == head then
    tail = inc(head) -- old data got eaten
  else
    count = count + 1
  end
  if debug then asserts() end
end

function obj:pop()
  if tail == head then
    return -- already empty
  end
  head = dec(head)
  count = count - 1
  if debug then asserts() end
end

function obj:clear()
  tail = head
  count = 0
  if debug then asserts() end
end

function obj:size()
  if debug then asserts() end
  return count
end

return obj
