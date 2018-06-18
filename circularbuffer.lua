local CircularBuffer = {}

CircularBuffer.__index = CircularBuffer
function CircularBuffer.new (size)
  local self = setmetatable({}, CircularBuffer)
  self:init(size)
  return self
end

function CircularBuffer:mod(n)
  -- keep n between 1 and bufferSize, inclusive
  return (n - 1) % self.bufferSize + 1
end

function CircularBuffer:inc(n)
  return self:mod(n + 1)
end

function CircularBuffer:dec(n)
  return self:mod(n - 1)
end

function CircularBuffer:asserts()
  assert(0 <= self.count)
  assert(self.count <= self.bufferSize)
end

function CircularBuffer:init(size)
  if not (size and size > 0) then
    error("Size must be a positive integer!")
    return
  end
  self.bufferSize = size
  self.array = {}
  self.head = 1
  self.count = 0
  self.debug = false -- set to true to get debug spew
  if self.debug then self:asserts() end
end

function CircularBuffer:getHead()
  if self.count == 0 then
    return nil
  end
  return self.array[self:mod(self.head-1)]
end

function CircularBuffer:getEnding(length)
  assert(length <= self.count, "length must be no greater than count")
  local slice = {}
  local cur = self:mod(self.head-length)
  for _=1,self.count do
    slice[#slice+1] = self.array[cur]
    cur = self:inc(cur)
  end
  if self.debug then assert(cur == self.head) end
  if self.debug then self:asserts() end
  return slice
end

function CircularBuffer:getAll()
  return self:getEnding(self.count)
end

function CircularBuffer:push(data)
  self.array[self.head] = data
  self.head = self:inc(self.head)
  if self.count < self.bufferSize then
    self.count = self.count + 1
  end
  if self.debug then self:asserts() end
end

function CircularBuffer:pop()
  if self.count == 0 then
    return nil -- already empty
  end
  self.head = self:dec(self.head)
  self.count = self.count - 1
  if self.debug then self:asserts() end
  return self.array[self.head]
end

function CircularBuffer:clear()
  self.count = 0
  if self.debug then self:asserts() end
end

function CircularBuffer:size()
  if self.debug then self:asserts() end
  return self.count
end

return CircularBuffer
