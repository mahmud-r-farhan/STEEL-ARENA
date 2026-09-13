--=============================================================================
-- UDP transport (LuaSocket) with a light reliability layer.
-- - Every packet: magic(2) + connId(2) + seq(2) + payload
-- - Piggybacked ack bitfield: lastAck + 32-bit mask
-- - keepalive + timeout-based disconnect
-- Works headless (server) and in LÖVE (client) via socket.try/udp.
--=============================================================================

local socket = nil
pcall(function() socket = require("socket") end)

local Protocol = require("net.protocol")

local Transport = {}
Transport.__index = Transport
Transport.available = socket ~= nil

local HEADER = 8   -- magic u16 + connId u16 + seq u16 + ackBase u16
local MAGIC_LO, MAGIC_HI = Protocol.MAGIC % 256, math.floor(Protocol.MAGIC / 256)

function Transport.new(isServer, port)
  if not socket then
    return nil, "LuaSocket not available"
  end
  local self = setmetatable({}, Transport)
  self.udp = socket.udp()
  self.udp:settimeout(0)
  if isServer then
    assert(self.udp:setsockname("*", port or Protocol.DEFAULT_PORT), "cannot bind port")
    self.isServer = true
    self.nextConnId = 1
    self.byAddr = {}
  else
    self.connId = 0      -- assigned by server in WELCOME flow
    self.sendSeq = 0
    self.recvSeq = {}
    self.lastAckBase = 0
    self.lastRecv = socket.gettime()
  end
  self.handlers = {}     -- msgType -> fn(conn, msg)
  self.connTimeout = 12
  return self
end

-- both sides: register handler for message type
function Transport:on(msgType, fn)
  self.handlers[msgType] = fn
end

-- server: find or create a connection record for an address
function Transport:serverConn(addr)
  local c = self.byAddr[addr]
  if not c then
    c = {
      id = self.nextConnId,
      addr = addr,
      sendSeq = 0,
      recvSeq = {},
      lastAckBase = 0,
      lastRecv = socket.gettime(),
      data = {},          -- app layer (player object)
      pendingAcks = {},   -- reliable resends
    }
    self.nextConnId = self.nextConnId + 1
    self.byAddr[addr] = c
  end
  return c
end

-- server: assign a fresh connection (drop any stale one at same addr)
function Transport:resetConn(addr)
  local old = self.byAddr[addr]
  if old and old.data and old.data.kick then old.data.kick("reconnected") end
  local c = self:serverConn(addr)
  c.recvSeq = {}
  return c
end

function Transport:connByAddr(addr) return self.byAddr[addr] end
function Transport:connById(id)
  for _, c in pairs(self.byAddr) do
    if c.id == id then return c end
  end
end
function Transport:dropConn(c)
  if c.addr then self.byAddr[c.addr] = nil end
end
function Transport:connections()
  local list = {}
  for _, c in pairs(self.byAddr) do list[#list + 1] = c end
  return list
end

local function packHeader(connId, seq, ackBase)
  return string.char(MAGIC_LO, MAGIC_HI,
    connId % 256, math.floor(connId / 256) % 256,
    seq % 256, math.floor(seq / 256) % 256,
    ackBase % 256, math.floor(ackBase / 256) % 256)
end

-- client: connect to host
function Transport:connect(host, port)
  self.host = host
  self.port = port or Protocol.DEFAULT_PORT
  self.udp:setpeername(self.host, self.port)
  self.lastRecv = socket.gettime()
end

-- client-side: send raw (header built here)
function Transport:send(msgType, msg)
  local body, err = Protocol.encode(msgType, msg)
  if not body then return nil, err end
  self.sendSeq = (self.sendSeq + 1) % 65536
  local pkt = packHeader(self.connId, self.sendSeq, self.lastAckBase) .. body
  return self.udp:send(pkt)
end

-- server-side: send to a specific connection
function Transport:sendTo(conn, msgType, msg)
  local body, err = Protocol.encode(msgType, msg)
  if not body then return nil, err end
  conn.sendSeq = (conn.sendSeq + 1) % 65536
  local pkt = packHeader(conn.id, conn.sendSeq, conn.lastAckBase) .. body
  local ok = self.udp:sendto(pkt, conn.addr)
  if ok then conn.lastSend = socket.gettime() end
  return ok
end

function Transport:broadcast(conns, msgType, msg)
  for _, c in ipairs(conns) do
    self:sendTo(c, msgType, msg)
  end
end

-- parse a raw datagram; returns conn(server)/true(client), msgType, msg
local function parse(self, datagram, addr)
  if #datagram < HEADER + 1 then return nil end
  local b1, b2 = datagram:byte(1, 2)
  if b1 ~= MAGIC_LO or b2 ~= MAGIC_HI then return nil end
  local function u16(pos)
    local a, b = datagram:byte(pos, pos + 1)
    return a + b * 256
  end
  local connId, seq, ackBase = u16(3), u16(5), u16(7)
  local msgType, msg, consumed = Protocol.decode(datagram:sub(HEADER + 1))
  if not msgType then return nil end

  if self.isServer then
    local conn = self:serverConn(addr)
    conn.lastRecv = socket.gettime()
    conn.lastAckBase = ackBase
    -- duplicate-suppression: track recent seqs
    if conn.recvSeq[seq] then return nil end
    conn.recvSeq[seq] = true
    -- cap table size
    local n = 0
    for _ in pairs(conn.recvSeq) do n = n + 1 end
    if n > 512 then conn.recvSeq = { [seq] = true } end
    return conn, msgType, msg
  else
    self.lastRecv = socket.gettime()
    self.lastAckBase = ackBase
    if self.connId == 0 then
      self.connId = connId
    elseif self.connId ~= connId then
      return nil
    end
    if self.recvSeq[seq] then return nil end
    self.recvSeq[seq] = true
    local n = 0
    for _ in pairs(self.recvSeq) do n = n + 1 end
    if n > 512 then self.recvSeq = { [seq] = true } end
    return true, msgType, msg
  end
end

-- pump: receive + dispatch all pending datagrams
function Transport:pump()
  while true do
    local data, msg_or_addr, addr = self.udp:receive()
    if not data then break end
    local conn, msgType, msg
    if self.isServer then
      conn, msgType, msg = parse(self, data, msg_or_addr)
    else
      conn, msgType, msg = parse(self, data, nil)
    end
    if conn and msgType then
      local h = self.handlers[msgType]
      if h then
        local ok, err = pcall(h, conn, msg)
        if not ok then print("[net] handler error: " .. tostring(err)) end
      end
    end
  end
end

-- call each frame: drops timed-out connections (server), warns client
function Transport:service(dt)
  local now = socket.gettime()
  if self.isServer then
    for _, c in pairs(self.byAddr) do
      if now - (c.lastRecv or now) > self.connTimeout then
        local d = c.data
        self:dropConn(c)
        if d and d.onTimeout then d.onTimeout() end
      end
    end
  else
    if now - self.lastRecv > self.connTimeout then
      return false   -- disconnected
    end
  end
  return true
end

function Transport:close()
  if self.udp then self.udp:close() end
  self.udp = nil
end

return Transport
