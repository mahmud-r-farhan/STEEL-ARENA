--=============================================================================
-- Client network layer. Wraps Transport for the UI states:
-- handshake, lobby list, rooms, invites, chat, loadout sync, ready, start.
-- Buffers snapshots and interpolates for smooth rendering.
-- Also hosts a local simulation for offline solo play.
--=============================================================================

local Protocol  = require("net.protocol")
local Transport = require("net.transport")
local Sim       = require("game.sim")
local Bot       = require("game.bot")
local Tanks     = require("data.tanks")
local Modes     = require("data.modes")
local Maps      = require("data.maps")

local T = Protocol.T

local Client = {}
Client.__index = Client

local INTERP_DELAY = 0.12
local SNAP_BUFFER = 12

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

function Client.new(services)
  local c = setmetatable({}, Client)
  c.save = services.save
  c.settings = services.settings
  c.audio = services.audio

  c.status = "offline"      -- offline|connecting|connected|disconnected
  c.error = nil
  c.myId = 0
  c.motd = ""
  c.ping = 0

  c.lobbyRooms = {}
  c.room = nil              -- last ROOM_STATE
  c.chatLog = {}            -- {name=, text=, system=bool}
  c.invites = {}            -- active invites
  c.toast = nil             -- {text, until}

  c.match = nil             -- {mapId, modeId, players={[id]={...}}}
  c.snapshots = {}          -- ring of {t=, data=}
  c.results = nil           -- MATCH_END payload
  c.eventQueue = {}         -- snapshot events pending fx/audio

  c.localSim = nil          -- local solo sim
  c.sendAcc = 0
  c.pingAcc = 0
  c.inputSeq = 0
  c.lastInput = { move = 0, turn = 0, turret = 0, fire = false }
  return c
end

function Client:toast(text, secs)
  self.toast = { text = text, expire = love.timer.getTime() + (secs or 3) }
end

function Client:systemChat(text)
  self.chatLog[#self.chatLog + 1] = { name = "SERVER", text = text, system = true }
  if #self.chatLog > 60 then table.remove(self.chatLog, 1) end
end

--=============================================================================
-- Connection
--=============================================================================

function Client:connect(host, port)
  self:disconnect()
  local ok, tr = pcall(function() return Transport.new(false) end)
  if not ok or not tr then
    self.error = "LuaSocket not available in this LÖVE build"
    return false
  end
  self.transport = tr
  tr:on(T.WELCOME, function(conn, msg)
    self.myId = msg.playerId
    self.motd = msg.motd or ""
    self.status = "connected"
    self:pushLoadout()
  end)
  tr:on(T.ERROR, function(conn, msg)
    self.error = msg.msg or "error " .. tostring(msg.code)
    self:toast(self.error)
  end)
  tr:on(T.LOBBY_LIST, function(conn, msg)
    self.lobbyRooms = msg.rooms or {}
  end)
  tr:on(T.ROOM_STATE, function(conn, msg)
    self.room = msg
  end)
  tr:on(T.CHAT, function(conn, msg)
    self.chatLog[#self.chatLog + 1] = { name = msg.name, text = msg.text }
    if #self.chatLog > 60 then table.remove(self.chatLog, 1) end
  end)
  tr:on(T.INVITE, function(conn, msg)
    self.invites[#self.invites + 1] = msg
    self:toast(msg.fromName .. " invited you to " .. msg.roomName, 6)
  end)
  tr:on(T.KICKED, function(conn, msg)
    self.room = nil
    self.match = nil
    self.status = "disconnected"
    self.kickReason = msg.reason or "kicked"
  end)
  tr:on(T.MATCH_START, function(conn, msg)
    self:beginMatch(msg)
  end)
  tr:on(T.SNAPSHOT, function(conn, msg)
    self:onSnapshot(msg)
  end)
  tr:on(T.MATCH_END, function(conn, msg)
    self.results = msg
    self:applyRewards(msg)
  end)
  tr:on(T.PONG, function(conn, msg)
    self.ping = math.floor((love.timer.getTime() - msg.t / 1000) * 1000)
  end)

  tr:connect(host, port or Protocol.DEFAULT_PORT)
  self.status = "connecting"
  self.serverHost, self.serverPort = host, port or Protocol.DEFAULT_PORT
  -- send hello immediately (and retry a few times in update until WELCOME)
  self:sendHello()
  return true
end

function Client:sendHello()
  local name = self.save.data.name or ("Player" .. math.random(10, 99))
  self:sendRaw(T.HELLO, {
    name = name,
    tankId = self.save.data.selected or "scout",
    camoId = self.save.data.camo_sel[self.save.data.selected] or "none",
    upgrades = self:currentUpgrades(),
    version = Protocol.VERSION,
  })
end

function Client:currentUpgrades()
  local tankId = self.save.data.selected or "scout"
  local out = {}
  local parts = Tanks.parts
  for i, part in ipairs(parts) do
    out[i] = self.save.upgradeLevel(tankId, part.id)
  end
  return out
end

function Client:pushLoadout()
  local tankId = self.save.data.selected or "scout"
  self:sendRaw(T.SET_LOADOUT, {
    tankId = tankId,
    camoId = (self.save.data.camo_sel and self.save.data.camo_sel[tankId]) or "none",
    upgrades = self:currentUpgrades(),
  })
end

function Client:disconnect()
  if self.transport then
    pcall(function() self:sendRaw(T.DISCONNECT, {}) end)
    pcall(function() self.transport:close() end)
  end
  self.transport = nil
  self.status = "offline"
  self.myId = 0
  self.room = nil
  self.match = nil
  self.results = nil
  self.snapshots = {}
  self.lobbyRooms = {}
  self.invites = {}
end

function Client:isInMatch()
  return self.match ~= nil
end

--=============================================================================
-- Room / lobby operations
--=============================================================================

function Client:sendRaw(t, msg)
  if not self.transport then return false end
  local ok, err = pcall(function() self.transport:send(t, msg) end)
  return ok
end

function Client:requestLobby() self:sendRaw(T.LOBBY_LIST, {}) end
function Client:quickMatch(modeId) self:sendRaw(T.QUICK_MATCH, { modeId = modeId }) end
function Client:createRoom(cfg) self:sendRaw(T.ROOM_CREATE, cfg) end
function Client:joinRoom(id, password) self:sendRaw(T.ROOM_JOIN, { roomId = id, password = password or "" }) end
function Client:leaveRoom() self:sendRaw(T.ROOM_LEAVE, {}) self.room = nil end
function Client:setReady(b) self:sendRaw(T.SET_READY, { ready = b }) end
function Client:setConfig(cfg) self:sendRaw(T.ROOM_CONFIG, cfg) end
function Client:sendChat(text) self:sendRaw(T.ROOM_CHAT, { text = text }) end
function Client:invite(playerId) self:sendRaw(T.INVITE_SEND, { targetId = playerId }) end
function Client:acceptInvite(inviteId) self:sendRaw(T.INVITE_ACCEPT, { inviteId = inviteId }) end
function Client:startMatch() self:sendRaw(T.START_MATCH, {}) end
function Client:kick(playerId) self:sendRaw(T.KICK, { playerId = playerId }) end

--=============================================================================
-- Local solo play
--=============================================================================

function Client:startLocalSolo(opts)
  self:disconnect()
  Maps.init(); Tanks.init(); Modes.init()
  local tankId = opts.tankId or "scout"
  local upgrades = {}
  local parts = Tanks.parts
  for i, part in ipairs(parts) do
    upgrades[i] = self.save.upgradeLevel(tankId, part.id)
  end
  local sim = Sim.new({
    mapId = opts.mapId or "outpost",
    modeId = opts.modeId or "solo",
    difficulty = opts.difficulty or 2,
    seed = os.time() % 2147483647,
  })
  sim.onEvent = function(e)
    self.eventQueue[#self.eventQueue + 1] = e
  end
  local enemyTeam = 2
  sim:addTank({ id = 1, name = self.save.data.name or "You", tankId = tankId,
    camoId = (self.save.data.camo_sel and self.save.data.camo_sel[tankId]) or "none",
    upgrades = upgrades, team = 1, isBot = false })

  local names = { "Rex", "Ivan", "Hank", "Bolt", "Sarge", "Roland", "Sable", "Grit", "Vulcan", "Moose" }
  local tankPool = { "scout", "gunner", "brawler", "sniper", "heavy" }
  local nextId = 100
  local function spawnBot(team, forcedTank)
    local id = nextId; nextId = nextId + 1
    sim:addTank({
      id = id,
      name = names[(id % #names) + 1] .. "_" .. (id % 90 + 10),
      tankId = forcedTank or tankPool[sim.rng:next(1, #tankPool)],
      camoId = "none", upgrades = {}, team = team, isBot = true,
    })
  end
  for i = 1, (opts.allies or 0) do spawnBot(1) end
  for i = 1, (opts.enemies or 3) do spawnBot(enemyTeam) end

  self.localSim = sim
  self.match = {
    mapId = sim.map.id, modeId = sim.mode.id, local_ = true,
    players = {},
  }
  for _, t in pairs(sim.tanksById) do
    self.match.players[t.id] = {
      id = t.id, name = t.name, tankId = t.tankId, team = t.team,
      isBot = t.isBot, camoId = t.camoId or "none", upgrades = t.upgrades,
    }
  end
  self.results = nil
  self.snapshots = {}
  self.status = "connected"
  return true
end

--=============================================================================
-- Match data + snapshots
--=============================================================================

function Client:beginMatch(msg)
  self.match = {
    mapId = msg.mapId, modeId = msg.modeId,
    tickRate = msg.tickRate or 30,
    players = {},
  }
  for _, p in ipairs(msg.players) do
    self.match.players[p.id] = p
  end
  self.results = nil
  self.snapshots = {}
  self.eventQueue = {}
  self.status = "connected"
end

function Client:onSnapshot(snap)
  snap.recvAt = love.timer.getTime()
  self.snapshots[#self.snapshots + 1] = snap
  if #self.snapshots > SNAP_BUFFER then table.remove(self.snapshots, 1) end
  -- queue events for fx/audio
  for _, e in ipairs(snap.events or {}) do
    self.eventQueue[#self.eventQueue + 1] = e
  end
end

-- interpolated tank states for rendering
function Client:renderState()
  if self.localSim then
    -- local sim: render directly (no interp needed)
    local out = {}
    for _, t in pairs(self.localSim.tanksById) do
      out[#out + 1] = {
        id = t.id, x = t.x, y = t.y, hull = t.hull, turret = t.turret,
        hp = t.hp, maxHp = t.maxHp, reload = 1 - t.reloadLeft / math.max(0.01, t.stats.reload),
        flags = self:flagsFor(t),
      }
    end
    local bullets = {}
    for _, b in ipairs(self.localSim.bullets) do
      bullets[#bullets + 1] = { id = b.id, x = b.x, y = b.y, angle = atan2(b.dy, b.dx), kind = b.kind }
    end
    return out, bullets, self:simModeState()
  end

  if #self.snapshots == 0 then return {}, {}, nil end
  local now = love.timer.getTime()
  local target = now - INTERP_DELAY
  local a, b
  for i = #self.snapshots, 2, -1 do
    if self.snapshots[i - 1].recvAt <= target then a = self.snapshots[i - 1]; b = self.snapshots[i]; break end
  end
  if not a then a = self.snapshots[1]; b = self.snapshots[#self.snapshots] end
  local span = b.recvAt - a.recvAt
  local alpha = span > 0.0001 and math.min(1, math.max(0, (target - a.recvAt) / span)) or 1

  local byIdA, byIdB = {}, {}
  for _, t in ipairs(a.tanks) do byIdA[t.id] = t end
  for _, t in ipairs(b.tanks) do byIdB[t.id] = t end

  local function lerpAngle(x, y, k)
    local d = (y - x) % (math.pi * 2)
    if d > math.pi then d = d - math.pi * 2 end
    return x + d * k
  end

  local out = {}
  for id, tb in pairs(byIdB) do
    local ta = byIdA[id] or tb
    out[#out + 1] = {
      id = id,
      x = ta.x + (tb.x - ta.x) * alpha,
      y = ta.y + (tb.y - ta.y) * alpha,
      hull = lerpAngle(ta.hull, tb.hull, alpha),
      turret = lerpAngle(ta.turret, tb.turret, alpha),
      hp = tb.hp, maxHp = self:maxHpFor(id),
      reload = tb.reload, flags = tb.flags,
      kills = tb.kills, deaths = tb.deaths,
    }
  end
  local bullets = {}
  for _, bl in ipairs(b.bullets or {}) do
    bullets[#bullets + 1] = bl
  end
  return out, bullets, b.mode
end

function Client:flagsFor(t)
  local f = 0
  if t.alive then f = f + 1 end
  if t.hasFlag then f = f + 2 end
  if t.invuln > 0 then f = f + 4 end
  if t.fxShield > 0 then f = f + 8 end
  if t.fxRapid > 0 then f = f + 16 end
  if t.fxDamage > 0 then f = f + 32 end
  if t.fxSpeed > 0 then f = f + 64 end
  return f
end

function Client:maxHpFor(id)
  local p = self.match and self.match.players[id]
  if p then
    local st = Tanks.statsFor(p.tankId, p.upgrades)
    return st.hp
  end
  return 100
end

function Client:simModeState()
  local sim = self.localSim
  local zones = {}
  for _, z in ipairs(sim.zones) do zones[#zones + 1] = { owner = z.owner } end
  return {
    scoreA = sim.scoreA, scoreB = sim.scoreB,
    timeLeft = math.floor(sim.timeLeft),
    zones = zones,
    flagA = sim.flags.a and (sim.flags.a.carrier == 0 and (sim.flags.a.atBase and 0 or 65535) or sim.flags.a.carrier) or 0,
    flagB = sim.flags.b and (sim.flags.b.carrier == 0 and (sim.flags.b.atBase and 0 or 65535) or sim.flags.b.carrier) or 0,
  }
end

--=============================================================================
-- Per-frame update
--=============================================================================

function Client:update(dt, input)
  local now = love.timer.getTime()
  if self.toast and now > self.toast.expire then self.toast = nil end

  -- local solo sim
  if self.localSim then
    local sim = self.localSim
    if input then
      sim:setInput(1, input, 0)
    end
    Bot.update(sim, dt)
    sim:step(dt)
    -- surface sim events
    -- (sim:onEvent was replaced below; here we pull from eventQueue filled by hook)
    if sim.over and not self.results then
      self:finishLocalMatch()
    end
    return
  end

  if not self.transport then return end
  self.transport:pump()

  -- retry hello while connecting
  if self.status == "connecting" then
    self.helloAcc = (self.helloAcc or 0) + dt
    if self.helloAcc > 0.5 then
      self.helloAcc = 0
      self:sendHello()
    end
    if now - (self.connectStart or now) > 6 then
      self.status = "disconnected"
      self.error = self.error or "connection timed out"
    end
  end

  -- input streaming at 30hz while in a live match
  if input and self.match and not self.results then
    self.sendAcc = self.sendAcc + dt
    if self.sendAcc >= 1 / 30 then
      self.sendAcc = self.sendAcc - 1 / 30
      self.inputSeq = (self.inputSeq + 1) % 256
      self:sendRaw(T.INPUT, {
        seq = self.inputSeq,
        move = input.move, turn = input.turn,
        turret = input.turret or 0, fire = input.fire,
      })
    end
  end

  -- ping keepalive
  self.pingAcc = self.pingAcc + dt
  if self.pingAcc > 2 then
    self.pingAcc = 0
    self:sendRaw(T.PING, { t = math.floor(now * 1000) })
  end

  -- lobby list refresh while browsing
  if self.lobbyRefresh then
    self.lobbyRefreshAcc = (self.lobbyRefreshAcc or 0) + dt
    if self.lobbyRefreshAcc > 2.5 then
      self.lobbyRefreshAcc = 0
      self:requestLobby()
    end
  end

  if not self.transport:service(dt) then
    self.status = "disconnected"
    self.error = "disconnected from server"
    self.room = nil
    self.match = nil
  end
end

-- local match completion: compute rewards, write to save
function Client:finishLocalMatch()
  local sim = self.localSim
  local rows = sim:scoreboard()
  local winner = sim.winner or 0
  local myRow
  for _, r in ipairs(rows) do
    if r.id == 1 then myRow = r end
  end
  local won = false
  if sim.mode.teams then
    local myTank = sim.tanksById[1]
    won = winner ~= 0 and myTank and myTank.team == winner
  else
    won = winner == 1
  end
  local credits = 40 + (myRow and myRow.kills or 0) * 22 + (won and 120 or 0)
  local xp = 30 + (myRow and myRow.kills or 0) * 12 + (won and 60 or 0)
  local out = { winner = winner, scoreboard = {} }
  for _, r in ipairs(rows) do
    out.scoreboard[#out.scoreboard + 1] = {
      id = r.id, name = r.name, kills = r.kills, deaths = r.deaths,
      score = r.score,
      xp = (r.id == 1) and xp or 0,
      credits = (r.id == 1) and credits or 0,
    }
  end
  self.results = out
  -- persist economy + stats
  self.save.grantCredits(credits)
  self.save.addXp(xp)
  self.save.data.stats.battles = self.save.data.stats.battles + 1
  if won then self.save.data.stats.wins = self.save.data.stats.wins + 1 end
  self.save.data.stats.kills = self.save.data.stats.kills + (myRow and myRow.kills or 0)
  self.save.data.stats.deaths = self.save.data.stats.deaths + (myRow and myRow.deaths or 0)
  self.save.dirty = true
end

function Client:applyRewards(msg)
  for _, row in ipairs(msg.scoreboard or {}) do
    if row.id == self.myId then
      self.save.grantCredits(row.credits or 0)
      self.save.addXp(row.xp or 0)
      self.save.data.stats.battles = self.save.data.stats.battles + 1
      self.save.dirty = true
    end
  end
end

function Client:leaveMatch()
  if self.localSim then
    self.localSim = nil
    self.match = nil
    self.results = nil
    return
  end
  self.match = nil
  self.results = nil
  self.snapshots = {}
end

return Client
