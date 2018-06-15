obj = {}

local bufferSize
local array -- table of size bufferSize
local head -- array[head] is the space after the last item
local tail -- array[tail] is the first item
local count
local debug = true -- set to true to get debug spew

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
  print(( "array: %s" ):format(utf8.char(table.unpack(array))))
end

local function mod(n)
  return (n - 1) % bufferSize + 1
end

local function inc(n)
  return mod(n + 1)
end

local function dec(n)
  return mod(n - 1)
end

function obj:init(size)
  if not (size and size > 0) then
    print("Error: Size must be a positive integer!")
    return
  end
  bufferSize = size
  array = {}
  head = 1
  tail = 1
  count = 0
end

function obj:get(offset) -- offset back from head
  assert(offset <= count, "offset is greater than count")
  assert(offset > 0, "offset is zero")
  if debug then asserts() end
  return utf8.char(array[mod(head-offset)])
end

function obj:getAll()
  local slice = {}
  local cur = tail
  while cur ~= head do
    slice[#slice+1] = array[cur]
    cur = inc(cur)
  end
  if debug then asserts() end
  return utf8.char(table.unpack(slice))
end

function obj:endsWith(str)
  local len = utf8.len(str)
  if len > count then
    return false
  end
  local cur = mod(head - len)
  for p, c in utf8.codes(str) do
    if debug then print(("array[%d] = %d <-> %d = str[%d]"):format(cur, array[cur], c, p)) end
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
