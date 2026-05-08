--[[
  5/8/2026
  Signal library
  API
    Signal.new(ordered: boolean?): Signal
      creates a new signal
      ordered: boolean? - if true, disconnects will be ordered at the cost of performance
                        - if false/nil, disconnects will be swapped at the cost of order
  Signal
    Signal:Connect(f): Connection
      creates a new connection
    Signal:Once(...): Connection
      creates a new connection, disconnects itself after Signal:Fire
    Signal:Wait(): any
      waits for the signal (can be only used in coroutines!)
    Signal:Fire(...)
      fires the signal
    Signal:DisconnectAll(...)
      disconnect all connections
    Signal:Destroy(...)
      clear all connections and waiters, marks itself as destroyed (you cannot use destroyed Signals again)
      
  Connection
    Connection.Connected: boolean
      is true if the connection is active
    Connection:Disconnect()
      disconnect the connection!
]]
-----------------------
local DESTROYED = {}
-----------------------
local function noOp() end
local function swapAndPop(t, i: number)
	local size = #t
	t[i] = t[size]
	t[size] = nil
end
-----------------------
type API = {
  new: (ordered: boolean?) -> (Signal)
}
export type Connection = {
  Disconnect: (Connection, any?) -> (),
  Connected: boolean
}
export type Signal = {
  Fire: (any?),
  Wait: (Signal) -> (any?),

  Connect: (Signal, (any) -> ()) -> Connection,
  Once: (Signal, (any) -> ()) -> Connection,
}
type SignalPrivate = {[any]: any}
-----------------------
local Connection = {}
Connection.__index = Connection
Connection.__newindex = noOp
function Connection.new(f, signalTable, ordered): Connection
  return setmetatable({[1] = f, [2] = signalTable, [3] = ordered or false, Connected = true}, Connection) :: any
end
function Connection:Disconnect()
  local self: SignalPrivate = self
  if not rawget(self, 1) then
    return
  end
  local signalTable = self[2]
  local i = table.find(signalTable, self)
  if i then
    if self[3] then
      table.remove(signalTable, i)
    else
      swapAndPop(signalTable, i)
    end
  end
  rawset(self, 1, nil)
  rawset(self, "Connected", false)
end
-----------------------
local function safecall(f, ...)
  local ok, err = pcall(f, ...)
  if not ok then
    print(`SIGNAL ERROR: {err}`)
  end
end
local function isolatedsafecall(f, ...)
  coroutine.wrap(safecall)(f, ...)
end
-----------------------
local function signalConnect(self, signalTable, f)
  assert(type(f) == 'function', 'connected is not a function')
  local i = #signalTable + 1
  local c = Connection.new(f, signalTable, self[4])
  signalTable[i] = c
  return c
end
local function disconnectAll(t: {Connection})
  for _, v: {[any]: any} in t do
    rawset(v, 1, nil)
    rawset(v, "Connected", false)
  end
  table.clear(t)
end

local Signal = {}
Signal.__index = Signal
Signal.__newindex = noOp

function Signal.new(ordered: boolean?): Signal
  return setmetatable({
    [1] = {}, 
    [2] = {}, 
    [3] = {}, 
    [4] = ordered or false,
  }, Signal) :: any
end

function Signal:Connect(f): Connection
  assert(self[1] ~= DESTROYED, 'Cannot :Connect on destroyed Signal')
  return signalConnect(self, self[1], f)
end
function Signal:Once(f): Connection
  assert(self[1] ~= DESTROYED, 'Cannot :Once on destroyed Signal')
  return signalConnect(self, self[2], f)
end

function Signal:Fire(...)
  assert(self[1] ~= DESTROYED, 'Cannot :Fire on destroyed Signal')
  local self: SignalPrivate = self
  for _, c in self[1] do
    isolatedsafecall(c[1], ...)
  end
  for _, o in self[2] do
    isolatedsafecall(o[1], ...)
    rawset(o, 1, nil)
    rawset(o, "Connected", false)
  end
  for _, w in self[3] do
    coroutine.resume(w, ...)
  end
  table.clear(self[2])
  table.clear(self[3])
end
function Signal:Wait()
  assert(self[1] ~= DESTROYED, 'Cannot :Wait on destroyed Signal')
  assert(coroutine.isyieldable(), "Signal:Wait() cannot be called from the main thread")
  table.insert(self[3], coroutine.running())
  return coroutine.yield() 
end

function Signal:DisconnectAll()
  assert(self[1] ~= DESTROYED, 'Cannot :DisconnectAll on destroyed Signals')
  disconnectAll(self[1])
  disconnectAll(self[2])
end

function Signal:Destroy()
  assert(self[1] ~= DESTROYED, 'Cannot :Destroy on destroyed Signal')
  local self: SignalPrivate = self
  self:DisconnectAll()
  for _, w in self[3] do
    coroutine.resume(w)
  end
  table.clear(self[3])
  rawset(self, 1, DESTROYED)
end

return Signal :: API
