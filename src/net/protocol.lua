--=============================================================================
-- Wire protocol: message types + binary encoder/decoder.
-- All numbers are quantized integers (compact, no float endianness issues).
-- World coordinates: u16 = value*10 (supports up to 6553.5 world units).
-- Angles: u16 = radians*1000.
--=============================================================================

local Protocol = {
  VERSION = 1,
  MAGIC = 0x5341,          -- "SA"
  DEFAULT_PORT = 37555,
}

-- ---------- message ids ----------
local T = {}
-- client -> server
T.HELLO        = 1
T.INPUT        = 2
T.PING         = 3
T.LOBBY_LIST   = 4
T.ROOM_CREATE  = 5
T.ROOM_JOIN    = 6
T.ROOM_LEAVE   = 7
T.ROOM_CHAT    = 8
T.INVITE_SEND  = 9
T.INVITE_ACCEPT= 10
T.SET_LOADOUT  = 11
T.SET_READY    = 12
T.ROOM_CONFIG  = 13
T.KICK         = 14
T.QUICK_MATCH  = 15
T.DISCONNECT   = 16
T.ACK          = 17   -- both directions: reliable-delivery ack
T.START_MATCH  = 18   -- client->server (host only)
T.LOBBY_PLAYERS= 19   -- client->server: who's connected and roomless
-- server -> client
T.WELCOME      = 64
T.LOBBY_LIST   = 65
T.ROOM_STATE   = 66
T.CHAT         = 67
T.INVITE       = 68
T.ERROR        = 69
T.KICKED       = 70
T.MATCH_START  = 71
T.SNAPSHOT     = 72
T.MATCH_END    = 73
T.PONG         = 74
T.RECONNECT_HINT = 75
T.LOBBY_PLAYERS = 76
Protocol.T = T

-- snapshot event kinds
Protocol.EV = {
  SHOT = 1, HIT = 2, EXPLODE = 3, PICKUP = 4, KILL = 5,
  FLAG_TAKEN = 6, FLAG_DROPPED = 7, FLAG_CAPTURED = 8,
  ZONE_CAPTURED = 9, RESPAWN = 10, DAMAGE_TAKEN = 11,
  RICOCHET = 12, FLAG_RETURNED = 13,
}

Protocol.ERRORS = {
  BAD_VERSION = 1, FULL = 2, IN_MATCH = 3, BAD_PASSWORD = 4,
  NOT_FOUND = 5, NOT_HOST = 6, NAME_TAKEN = 7, BANNED = 8,
  PROTOCOL = 9, FLOOD = 10,
}

-- ---------- byte writer ----------
local Writer = {}
Writer.__index = Writer

function Writer.new()
  return setmetatable({ buf = {} }, Writer)
end

function Writer:u8(v)  self.buf[#self.buf + 1] = string.char(math.max(0, math.min(255, math.floor(v or 0)))) return self end
function Writer:i8(v)  return self:u8((math.floor(v or 0) + 128) % 256) end
function Writer:u16(v) v = math.max(0, math.min(65535, math.floor(v or 0))) return self:u8(v % 256):u8(math.floor(v / 256)) end
function Writer:i16(v) return self:u16((math.floor(v or 0) + 32768) % 65536) end
function Writer:u32(v) v = math.max(0, math.min(4294967295, math.floor(v or 0)))
  return self:u8(v % 256):u8(math.floor(v / 256) % 256):u8(math.floor(v / 65536) % 256):u8(math.floor(v / 16777216) % 256) end
function Writer:bool(v) return self:u8(v and 1 or 0) end

-- scaled fixed-point
function Writer:pos(v)  return self:u16(math.floor((v or 0) * 10 + 0.5)) end
function Writer:ang(v)  local a = (v or 0) % (math.pi * 2) return self:u16(math.floor(a * 1000 + 0.5)) end
function Writer:frac(v) v = math.max(0, math.min(1, v or 0)) return self:u8(math.floor(v * 255 + 0.5)) end

function Writer:str(s)
  s = tostring(s or "")
  local bytes = { s:byte(1, 255) }
  self:u8(#bytes)
  for i = 1, #bytes do self.buf[#self.buf + 1] = string.char(bytes[i]) end
  return self
end

function Writer:done() return table.concat(self.buf) end

-- ---------- byte reader ----------
local Reader = {}
Reader.__index = Reader

function Reader.new(data)
  return setmetatable({ data = data, p = 1, len = #data }, Reader)
end

function Reader:u8()
  if self.p > self.len then error("reader eof") end
  local v = self.data:byte(self.p); self.p = self.p + 1; return v
end
function Reader:i8() return self:u8() - 128 end
function Reader:u16()
  local a = self:u8(); return a + self:u8() * 256
end
function Reader:i16() return self:u16() - 32768 end
function Reader:u32()
  local a, b, c, d = self:u8(), self:u8(), self:u8(), self:u8()
  return a + b * 256 + c * 65536 + d * 16777216
end
function Reader:bool() return self:u8() ~= 0 end
function Reader:pos()  return self:u16() / 10 end
function Reader:ang()  return self:u16() / 1000 end
function Reader:frac() return self:u8() / 255 end
function Reader:str()
  local n = self:u8()
  if n == 0 then return "" end
  if self.p + n - 1 > self.len then error("reader eof str") end
  local s = self.data:sub(self.p, self.p + n - 1)
  self.p = self.p + n
  return s
end

Protocol.Writer = Writer
Protocol.Reader = Reader

--=============================================================================
-- Message encode/decode
--=============================================================================

local enc, dec = {}, {}

-- --- C2S ---
enc[T.HELLO] = function(w, m)
  w:str(m.name):str(m.tankId):str(m.camoId or "none")
  for i = 1, 5 do w:u8(m.upgrades[i] or 0) end
  w:u16(Protocol.VERSION)
end
dec[T.HELLO] = function(r)
  local upg = {}
  local m = { name = r:str(), tankId = r:str(), camoId = r:str() }
  for i = 1, 5 do upg[i] = r:u8() end
  m.upgrades = upg
  m.version = r:u16()
  return m
end

enc[T.INPUT] = function(w, m)
  w:u8(m.seq or 0)
  w:i8(m.move or 0)          -- -1 back, +1 forward
  w:i8(m.turn or 0)          -- -1 left, +1 right (hull)
  w:ang(m.turret or 0)       -- absolute world turret angle
  w:bool(m.fire)
end
dec[T.INPUT] = function(r)
  return {
    seq = r:u8(), move = r:i8(), turn = r:i8(),
    turret = r:ang(), fire = r:bool(),
  }
end

enc[T.PING] = function(w, m) w:u32(m.t or 0) end
dec[T.PING] = function(r) return { t = r:u32() } end

enc[T.LOBBY_LIST] = function() end
dec[T.LOBBY_LIST] = function() return {} end

enc[T.ROOM_CREATE] = function(w, m)
  w:str(m.name):str(m.mapId or "outpost"):str(m.modeId or "dm")
  w:u8(m.maxPlayers or 8):str(m.password or ""):u8(m.bots or 0):u8(m.difficulty or 1)
end
dec[T.ROOM_CREATE] = function(r)
  return { name = r:str(), mapId = r:str(), modeId = r:str(),
    maxPlayers = r:u8(), password = r:str(), bots = r:u8(), difficulty = r:u8() }
end

enc[T.ROOM_JOIN] = function(w, m) w:u16(m.roomId or 0):str(m.password or "") end
dec[T.ROOM_JOIN] = function(r) return { roomId = r:u16(), password = r:str() } end

enc[T.ROOM_LEAVE] = function() end
dec[T.ROOM_LEAVE] = function() return {} end

enc[T.ROOM_CHAT] = function(w, m) w:str(m.text or "") end
dec[T.ROOM_CHAT] = function(r) return { text = r:str() } end

enc[T.INVITE_SEND] = function(w, m) w:u16(m.targetId or 0) end
dec[T.INVITE_SEND] = function(r) return { targetId = r:u16() } end

enc[T.INVITE_ACCEPT] = function(w, m) w:u8(m.inviteId or 0) end
dec[T.INVITE_ACCEPT] = function(r) return { inviteId = r:u8() } end

enc[T.SET_LOADOUT] = function(w, m)
  w:str(m.tankId or "scout"):str(m.camoId or "none")
  for i = 1, 5 do w:u8(m.upgrades[i] or 0) end
end
dec[T.SET_LOADOUT] = function(r)
  local m = { tankId = r:str(), camoId = r:str() }
  local upg = {}
  for i = 1, 5 do upg[i] = r:u8() end
  m.upgrades = upg
  return m
end

enc[T.SET_READY] = function(w, m) w:bool(m.ready) end
dec[T.SET_READY] = function(r) return { ready = r:bool() } end

enc[T.ROOM_CONFIG] = function(w, m)
  w:str(m.mapId or "outpost"):str(m.modeId or "dm")
  w:u8(m.maxPlayers or 8):u8(m.bots or 0):u8(m.difficulty or 1)
end
dec[T.ROOM_CONFIG] = function(r)
  return { mapId = r:str(), modeId = r:str(), maxPlayers = r:u8(), bots = r:u8(), difficulty = r:u8() }
end

enc[T.KICK] = function(w, m) w:u16(m.playerId or 0) end
dec[T.KICK] = function(r) return { playerId = r:u16() } end

enc[T.QUICK_MATCH] = function(w, m) w:str(m.modeId or "dm") end
dec[T.QUICK_MATCH] = function(r) return { modeId = r:str() } end

enc[T.DISCONNECT] = function() end
dec[T.DISCONNECT] = function() return {} end

-- ack: base seq + 32-bit mask of acked seqs (base..base+31)
enc[T.ACK] = function(w, m) w:u16(m.base or 0):u32(m.mask or 0) end
dec[T.ACK] = function(r) return { base = r:u16(), mask = r:u32() } end

enc[T.START_MATCH] = function() end
dec[T.START_MATCH] = function() return {} end

enc[T.LOBBY_PLAYERS] = function() end
dec[T.LOBBY_PLAYERS] = function() return {} end

enc[T.LOBBY_PLAYERS] = function(w, m)
  local ps = m.players or {}
  w:u8(#ps)
  for _, p in ipairs(ps) do
    w:u16(p.id):str(p.name):u16(p.level or 1)
  end
end
dec[T.LOBBY_PLAYERS] = function(r)
  local ps, n = {}, r:u8()
  for i = 1, n do
    ps[i] = { id = r:u16(), name = r:str(), level = r:u16() }
  end
  return { players = ps }
end

-- --- S2C ---
enc[T.WELCOME] = function(w, m) w:u16(m.playerId or 0):str(m.motd or "") end
dec[T.WELCOME] = function(r) return { playerId = r:u16(), motd = r:str() } end

enc[T.LOBBY_LIST] = function(w, m)
  local rooms = m.rooms or {}
  w:u8(#rooms)
  for _, rm in ipairs(rooms) do
    w:u16(rm.id):str(rm.name):str(rm.modeId):str(rm.mapId)
    w:u8(rm.players):u8(rm.maxPlayers):u8(rm.status or 0):bool(rm.hasPassword)
  end
end
dec[T.LOBBY_LIST] = function(r)
  local rooms = {}
  local n = r:u8()
  for i = 1, n do
    rooms[i] = {
      id = r:u16(), name = r:str(), modeId = r:str(), mapId = r:str(),
      players = r:u8(), maxPlayers = r:u8(), status = r:u8(), hasPassword = r:bool(),
    }
  end
  return { rooms = rooms }
end

enc[T.ROOM_STATE] = function(w, m)
  w:u16(m.roomId or 0):str(m.name or ""):u16(m.hostId or 0)
  w:str(m.modeId or "dm"):str(m.mapId or "outpost")
  w:u8(m.bots or 0):u8(m.difficulty or 1):u8(m.status or 0):bool(m.hasPassword or false)
  local players = m.players or {}
  w:u8(#players)
  for _, p in ipairs(players) do
    w:u16(p.id):str(p.name):str(p.tankId or "scout"):str(p.camoId or "none")
    w:bool(p.ready):u8(p.team or 0):bool(p.isBot):u16(p.level or 1)
  end
end
dec[T.ROOM_STATE] = function(r)
  local m = {
    roomId = r:u16(), name = r:str(), hostId = r:u16(),
    modeId = r:str(), mapId = r:str(),
    bots = r:u8(), difficulty = r:u8(), status = r:u8(), hasPassword = r:bool(),
  }
  local players, n = {}, r:u8()
  for i = 1, n do
    players[i] = {
      id = r:u16(), name = r:str(), tankId = r:str(), camoId = r:str(),
      ready = r:bool(), team = r:u8(), isBot = r:bool(), level = r:u16(),
    }
  end
  m.players = players
  return m
end

enc[T.CHAT] = function(w, m) w:u16(m.playerId or 0):str(m.name or ""):str(m.text or "") end
dec[T.CHAT] = function(r) return { playerId = r:u16(), name = r:str(), text = r:str() } end

enc[T.INVITE] = function(w, m)
  w:u8(m.inviteId or 0):u16(m.fromId or 0):str(m.fromName or ""):u16(m.roomId or 0):str(m.roomName or "")
end
dec[T.INVITE] = function(r)
  return { inviteId = r:u8(), fromId = r:u16(), fromName = r:str(), roomId = r:u16(), roomName = r:str() }
end

enc[T.ERROR] = function(w, m) w:u8(m.code or 0):str(m.msg or "") end
dec[T.ERROR] = function(r) return { code = r:u8(), msg = r:str() } end

enc[T.KICKED] = function(w, m) w:str(m.reason or "") end
dec[T.KICKED] = function(r) return { reason = r:str() } end

enc[T.MATCH_START] = function(w, m)
  w:str(m.mapId):str(m.modeId):u32(m.seed or 0):u8(m.tickRate or 30)
  local ps = m.players or {}
  w:u8(#ps)
  for _, p in ipairs(ps) do
    w:u16(p.id):str(p.name):str(p.tankId):str(p.camoId or "none")
    w:u8(p.team or 0):bool(p.isBot)
    w:pos(p.x):pos(p.y):u16(p.hp or 100)
    for i = 1, 5 do w:u8(p.upgrades and p.upgrades[i] or 0) end
  end
end
dec[T.MATCH_START] = function(r)
  local m = { mapId = r:str(), modeId = r:str(), seed = r:u32(), tickRate = r:u8() }
  local ps, n = {}, r:u8()
  for i = 1, n do
    local upg = {}
    local p = {
      id = r:u16(), name = r:str(), tankId = r:str(), camoId = r:str(),
      team = r:u8(), isBot = r:bool(),
      x = r:pos(), y = r:pos(), hp = r:u16(),
    }
    for j = 1, 5 do upg[j] = r:u8() end
    p.upgrades = upg
    ps[i] = p
  end
  m.players = ps
  return m
end

enc[T.SNAPSHOT] = function(w, m)
  w:u16(m.tick or 0)
  local tanks = m.tanks or {}
  w:u8(#tanks)
  for _, t in ipairs(tanks) do
    w:u16(t.id):pos(t.x):pos(t.y):ang(t.hull):ang(t.turret)
    w:u16(t.hp):frac(t.reload or 0):u8(t.flags or 0)
    w:u8(t.kills or 0):u8(t.deaths or 0)
  end
  local bullets = m.bullets or {}
  w:u8(#bullets)
  for _, b in ipairs(bullets) do
    w:u16(b.id):pos(b.x):pos(b.y):ang(b.angle):u8(b.kind or 0)
  end
  local events = m.events or {}
  w:u8(#events)
  for _, e in ipairs(events) do
    w:u8(e.kind):u16(e.tankId or 0):u16(e.extra or 0):pos(e.x):pos(e.y):u16(e.extra2 or 0)
  end
  -- mode state
  local ms = m.mode or {}
  w:u16(ms.scoreA or 0):u16(ms.scoreB or 0):u16(ms.timeLeft or 0)
  local zones = ms.zones or {}
  w:u8(#zones)
  for _, z in ipairs(zones) do w:u8(z.owner or 0) end
  w:u16(ms.flagA or 0):u16(ms.flagB or 0)   -- 0 = at base, else carrierId
end
dec[T.SNAPSHOT] = function(r)
  local m = { tick = r:u16() }
  local tanks, n = {}, r:u8()
  for i = 1, n do
    tanks[i] = {
      id = r:u16(), x = r:pos(), y = r:pos(), hull = r:ang(), turret = r:ang(),
      hp = r:u16(), reload = r:frac(), flags = r:u8(),
      kills = r:u8(), deaths = r:u8(),
    }
  end
  m.tanks = tanks
  local bullets, nb = {}, r:u8()
  for i = 1, nb do
    bullets[i] = { id = r:u16(), x = r:pos(), y = r:pos(), angle = r:ang(), kind = r:u8() }
  end
  m.bullets = bullets
  local events, ne = {}, r:u8()
  for i = 1, ne do
    events[i] = { kind = r:u8(), tankId = r:u16(), extra = r:u16(), x = r:pos(), y = r:pos(), extra2 = r:u16() }
  end
  m.events = events
  local ms = { scoreA = r:u16(), scoreB = r:u16(), timeLeft = r:u16() }
  local zones, nz = {}, r:u8()
  for i = 1, nz do zones[i] = { owner = r:u8() } end
  ms.zones = zones
  ms.flagA = r:u16(); ms.flagB = r:u16()
  m.mode = ms
  return m
end

enc[T.MATCH_END] = function(w, m)
  w:u16(m.winner or 0)
  local rows = m.scoreboard or {}
  w:u8(#rows)
  for _, s in ipairs(rows) do
    w:u16(s.id):str(s.name):u8(s.kills or 0):u8(s.deaths or 0)
    w:u16(s.score or 0):u16(s.xp or 0):u16(s.credits or 0)
  end
end
dec[T.MATCH_END] = function(r)
  local m = { winner = r:u16() }
  local rows, n = {}, r:u8()
  for i = 1, n do
    rows[i] = { id = r:u16(), name = r:str(), kills = r:u8(), deaths = r:u8(),
      score = r:u16(), xp = r:u16(), credits = r:u16() }
  end
  m.scoreboard = rows
  return m
end

enc[T.PONG] = function(w, m) w:u32(m.t or 0) end
dec[T.PONG] = function(r) return { t = r:u32() } end

enc[T.RECONNECT_HINT] = function(w, m) w:str(m.info or "") end
dec[T.RECONNECT_HINT] = function(r) return { info = r:str() } end

--=============================================================================
-- Public API
--=============================================================================

function Protocol.encode(msgType, msg)
  local e = enc[msgType]
  if not e then return nil, "no encoder for " .. tostring(msgType) end
  local w = Writer.new()
  w:u8(msgType)
  e(w, msg or {})
  return w:done()
end

-- Decode one message from front of data; returns msgType, msg, bytesConsumed.
function Protocol.decode(data)
  local r = Reader.new(data)
  local msgType = r:u8()
  local d = dec[msgType]
  if not d then return nil, nil, "no decoder for " .. tostring(msgType) end
  local ok, msg = pcall(d, r)
  if not ok then return nil, nil, msg end
  return msgType, msg, r.p - 1   -- bytes consumed (r.p is next-read position)
end

-- Validation / clamping (server-side anti-cheat for loadouts).
Protocol.MAX_UPGRADE = 3

function Protocol.sanitizeLoadout(msg)
  local tankId = tostring(msg.tankId or "scout")
  if not tankId:match("^[%w_]+$") or #tankId > 16 then tankId = "scout" end
  local camoId = tostring(msg.camoId or "none")
  if not camoId:match("^[%w_]+$") or #camoId > 16 then camoId = "none" end
  local upg = {}
  for i = 1, 5 do
    upg[i] = math.max(0, math.min(Protocol.MAX_UPGRADE, math.floor(tonumber(msg.upgrades and msg.upgrades[i]) or 0)))
  end
  return tankId, camoId, upg
end

function Protocol.sanitizeName(name)
  name = tostring(name or ""):gsub("[^%w _%-]", "")
  name = name:sub(1, 16)
  if #name < 2 then name = "Player" end
  return name
end

function Protocol.sanitizeChat(text)
  text = tostring(text or ""):gsub("[%c]", ""):sub(1, 120)
  return text
end

return Protocol
