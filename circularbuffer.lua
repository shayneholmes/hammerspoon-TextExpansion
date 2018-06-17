obj = {}

local bufferSize
local array -- table of size bufferSize
local head -- array[head] is the space after the last item
local count -- defines how much of the buffer is used
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
  assert(0 <= count)
  assert(count <= bufferSize)
end

function obj:init(size)
  if not (size and size > 0) then
    print("Error: Size must be a positive integer!")
    return
  end
  bufferSize = size
  array = {}
  head = 1
  count = 0
  if debug then asserts() end
end

function obj:getHead()
  if count == 0 then
    return nil
  end
  return array[mod(head-1)]
end

function obj:getEnding(length)
  assert(length <= count, "length must be no greater than count")
  local slice = {}
  local cur = mod(head-length)
  for _=1,count do
    slice[#slice+1] = array[cur]
    cur = inc(cur)
  end
  if debug then assert(cur == head) end
  if debug then asserts() end
  return slice
end

function obj:getAll()
  return self:getEnding(count)
end

function obj:push(data)
  array[head] = data
  head = inc(head)
  if count < bufferSize then
    count = count + 1
  end
  if debug then asserts() end
end

function obj:pop()
  if count == 0 then
    return nil -- already empty
  end
  head = dec(head)
  count = count - 1
  if debug then asserts() end
  return array[head]
end

function obj:clear()
  count = 0
  if debug then asserts() end
end

function obj:size()
  if debug then asserts() end
  return count
end

return obj
