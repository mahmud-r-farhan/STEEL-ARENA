--=============================================================================
-- Dedicated server application: lobby, rooms, invites, chat, quick match,
-- match lifecycle (start, tick, snapshots, end, rewards), bot filling.
-- Run headless:  love src --server
--=============================================================================

local Protocol  = require("net.protocol")
local Transport = require("net.transport")
local Sim       = require("game.sim")
local Bot       = require("game.bot")
local Tanks     = require("data.tanks")
local Maps      = require("data.maps")
local Modes     = require("data.modes")

local socket = require("socket")

local Server = {
  rooms = {},          -- roomId -> room
  playersByConn = {},  -- conn -> player
  nextRoomId = 1,
  nextPlayerId = 1,
  nextBotId = 900,
  invites = {},        -- inviteId -> {from, roomId, expires}
  nextInviteId = 1,
}

local T = Protocol.T
local E = Protocol.ERRORS
local MAX_ROOMS = 32
local TICK_DT = 1 / Sim.TICK_RATE
local transport   -- created in Server.start()

local function log(fmt, ...)
  print(os.date("%H:%M:%S") .. " " .. string.format(fmt, ...))
end

local function sendTo(conn, msgType, msg)
  if conn and transport then transport:sendTo(conn, msgType, msg) end
end

local function sendError(conn, code, text)
  sendTo(conn, T.ERROR, { code = code, msg = text or "" })
end

local function roomPlayerCount(room)
  local n = 0
  for _ in pairs(room.players) do n = n + 1 end
  return n
end

local function roomPlayersList(room)
  local out = {}
  for _, p in pairs(room.players) do
    out[#out + 1] = {
      id = p.id, name = p.name, tankId = p.tankId, camoId = p.camoId,
      ready = p.ready, team = p.team, isBot = p.isBot, level = p.level,
    }
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

local function roomStateMsg(room)
  return {
    roomId = room.id, name = room.name, hostId = room.hostId,
    modeId = room.modeId, mapId = room.mapId,
    bots = room.bots, difficulty = room.difficulty,
    status = room.status == "live" and 1 or 0,
    hasPassword = room.password ~= nil and room.password ~= "",
    players = roomPlayersList(room),
  }
end

local function broadcastRoomState(room)
  local msg = roomStateMsg(room)
  for _, p in pairs(room.players) do
    if p.conn then sendTo(p.conn, T.ROOM_STATE, msg) end
  end
end

local function lobbyListMsg()
  local rooms = {}
  for _, room in pairs(Server.rooms) do
    rooms[#rooms + 1] = {
      id = room.id, name = room.name, modeId = room.modeId, mapId = room.mapId,
      players = roomPlayerCount(room), maxPlayers = room.maxPlayers,
      status = room.status == "live" and 1 or 0,
      hasPassword = room.password ~= nil and room.password ~= "",
    }
  end
  table.sort(rooms, function(a, b) return a.id < b.id end)
  return { rooms = rooms }
end

local function playerById(id)
  for _, p in pairs(Server.playersByConn) do
    if p.id == id then return p end
  end
end

local function removePlayer(p, reason)
  if p.room then
    local room = Server.rooms[p.room]
    if room then
      room.players[p.id] = nil
      if room.sim then room.sim:removeTank(p.id) end
      if room.hostId == p.id then
        local nextHost
        for _, other in pairs(room.players) do
          if not other.isBot then nextHost = other; break end
        end
        if nextHost then
          room.hostId = nextHost.id
          if nextHost.conn then
            sendTo(nextHost.conn, T.CHAT, { playerId = 0, name = "SERVER",
              text = "You are now the host." })
          end
        else
          Server.rooms[room.id] = nil
          log("room #%d destroyed", room.id)
        end
      end
      if Server.rooms[room.id] then broadcastRoomState(room) end
    end
  end
  if p.conn then
    Server.playersByConn[p.conn] = nil
    transport:dropConn(p.conn)
  end
  log("player %s left (%s)", p.name, reason or "?")
end

--=============================================================================
-- Match lifecycle
--=============================================================================

local function clampRoomConfig(cfg)
  cfg.maxPlayers = math.max(2, math.min(12, math.floor(cfg.maxPlayers or 8)))
  cfg.bots = math.max(0, math.min(10, math.floor(cfg.bots or 0)))
  cfg.difficulty = math.max(1, math.min(4, math.floor(cfg.difficulty or 1)))
  cfg.name = tostring(cfg.name or "Room"):sub(1, 24)
  if #cfg.name < 1 then cfg.name = "Room" end
  cfg.mapId = Maps.byId[cfg.mapId] and cfg.mapId or "outpost"
  cfg.modeId = Modes.byId[cfg.modeId] and cfg.modeId or "dm"
  return cfg
end

local function assignTeams(room)
  if not Modes.get(room.modeId).teams then return end
  local a, b = 0, 0
  for _, p in pairs(room.players) do
    if a <= b then p.team = 1; a = a + 1 else p.team = 2; b = b + 1 end
  end
end

local BOT_NAMES = { "Rex", "Ivan", "Hank", "Bolt", "Sarge", "Roland",
  "Sable", "Grit", "Vulcan", "Moose", "Dutch", "Ironside" }
local BOT_TANKS = { "scout", "gunner", "brawler", "sniper", "heavy" }

local function startMatch(room)
  local mode = Modes.get(room.modeId)
  assignTeams(room)

  -- spawn bot participants configured for this room
  local teamA, teamB = 0, 0
  for _, p in pairs(room.players) do
    if mode.teams then
      if p.team == 1 then teamA = teamA + 1 else teamB = teamB + 1 end
    end
  end
  for i = 1, (room.bots or 0) do
    local id = Server.nextBotId
    Server.nextBotId = Server.nextBotId + 1
    local team = 1
    if mode.teams then
      if teamA <= teamB then team = 1; teamA = teamA + 1 else team = 2; teamB = teamB + 1 end
    end
    room.players[id] = {
      id = id,
      name = BOT_NAMES[(id % #BOT_NAMES) + 1] .. "_" .. (id % 90 + 10),
      tankId = BOT_TANKS[(id % #BOT_TANKS) + 1],
      camoId = "none", upgrades = {}, level = 1 + (id % 10),
      ready = true, isBot = true, team = team, conn = nil,
    }
  end

  local sim = Sim.new({
    mapId = room.mapId,
    modeId = room.modeId,
    difficulty = room.difficulty,
    seed = os.time() % 2147483647,
  })

  local startPlayers = {}
  for _, p in pairs(room.players) do
    local tankId, camoId, upg = Protocol.sanitizeLoadout(p)
    sim:addTank({
      id = p.id, name = p.name, tankId = tankId, camoId = camoId,
      upgrades = upg, team = p.team or 1, isBot = p.isBot,
    })
    startPlayers[#startPlayers + 1] = {
      id = p.id, name = p.name, tankId = tankId, camoId = camoId,
      team = p.team or 1, isBot = p.isBot, upgrades = upg,
      x = sim.tanksById[p.id].x, y = sim.tanksById[p.id].y,
      hp = math.floor(sim.tanksById[p.id].hp),
    }
  end
  table.sort(startPlayers, function(a, b) return a.id < b.id end)

  room.sim = sim
  room.status = "live"
  room.scoreSubmitted = false
  room.endTimer = nil

  local startMsg = {
    mapId = room.mapId, modeId = room.modeId,
    seed = sim.seed, tickRate = Sim.TICK_RATE,
    players = startPlayers,
  }
  for _, p in pairs(room.players) do
    if p.conn then sendTo(p.conn, T.MATCH_START, startMsg) end
  end
  log("room #%d match started (%s on %s, %d players)",
    room.id, room.modeId, room.mapId, #startPlayers)
end

local function endMatch(room)
  local sim = room.sim
  local winner = sim.winner or 0
  local rows = {}
  for _, srow in ipairs(sim:scoreboard()) do
    local won
    if sim.mode.teams then
      won = (winner ~= 0) and (srow.team == winner)
    else
      won = (srow.id == winner)
    end
    local credits = 40 + srow.kills * 22 + (won and 120 or 0) + math.floor((srow.damage or 0) / 40)
    local xp = 30 + srow.kills * 12 + (won and 60 or 0)
    rows[#rows + 1] = {
      id = srow.id, name = srow.name, kills = srow.kills, deaths = srow.deaths,
      score = srow.score, xp = math.min(65535, xp), credits = math.min(65535, credits),
    }
    local p = room.players[srow.id]
    if p and not p.isBot and p.statsSink then
      p.statsSink(srow.kills, srow.deaths, won, xp, credits)
    end
  end
  table.sort(rows, function(a, b) return a.score > b.score end)

  local msg = { winner = winner, scoreboard = rows }
  for _, p in pairs(room.players) do
    if p.conn then sendTo(p.conn, T.MATCH_END, msg) end
  end
  log("room #%d match over, winner=%d", room.id, winner)

  room.sim = nil
  room.status = "lobby"
  -- remove bot participants; reset humans
  for id, p in pairs(room.players) do
    if p.isBot then room.players[id] = nil else p.ready = false end
  end
  broadcastRoomState(room)
end

--=============================================================================
-- Handlers
--=============================================================================

local function onHello(conn, msg)
  local p = conn.data
  if msg.version ~= Protocol.VERSION then
    return sendError(conn, E.BAD_VERSION, "version mismatch")
  end
  if p.id ~= 0 then return end
  local name = Protocol.sanitizeName(msg.name)
  for _, other in pairs(Server.playersByConn) do
    if other.name == name then name = name .. "_" .. (Server.nextPlayerId % 99) end
  end
  p.id = Server.nextPlayerId
  Server.nextPlayerId = Server.nextPlayerId + 1
  p.name = name
  p.tankId, p.camoId, p.upgrades = Protocol.sanitizeLoadout(msg)
  p.level = 1
  Server.playersByConn[conn] = p
  sendTo(conn, T.WELCOME, { playerId = p.id, motd = "Welcome to Steel Arena!" })
  log("player %s (#%d) connected", p.name, p.id)
end

local function onInput(conn, msg)
  local p = conn.data
  if not p or not p.room then return end
  local room = Server.rooms[p.room]
  if not room or not room.sim then return end
  room.sim:setInput(p.id, msg, msg.seq)
end

local function onPing(conn, msg)
  sendTo(conn, T.PONG, { t = msg.t })
end

local function onLobbyList(conn)
  sendTo(conn, T.LOBBY_LIST, lobbyListMsg())
end

-- who is connected to the server and not in a room (for invites)
local function onLobbyPlayers(conn)
  local p = conn.data
  if not p or p.id == 0 then return end
  local players = {}
  for _, other in pairs(Server.playersByConn) do
    if not other.room and other.id ~= p.id then
      players[#players + 1] = { id = other.id, name = other.name, level = other.level }
    end
  end
  table.sort(players, function(a, b) return a.id < b.id end)
  sendTo(conn, T.LOBBY_PLAYERS, { players = players })
end

local function onRoomCreate(conn, msg)
  local p = conn.data
  if not p or p.id == 0 then return sendError(conn, E.PROTOCOL, "handshake first") end
  if p.room then return sendError(conn, E.PROTOCOL, "already in a room") end
  local roomCount = 0
  for _ in pairs(Server.rooms) do roomCount = roomCount + 1 end
  if roomCount >= MAX_ROOMS then return sendError(conn, E.FULL, "server full") end

  local cfg = clampRoomConfig(msg)
  local room = {
    id = Server.nextRoomId,
    name = cfg.name, modeId = cfg.modeId, mapId = cfg.mapId,
    maxPlayers = cfg.maxPlayers, bots = cfg.bots, difficulty = cfg.difficulty,
    password = (msg.password and #msg.password > 0) and msg.password or nil,
    hostId = p.id, status = "lobby", players = {},
  }
  Server.nextRoomId = Server.nextRoomId + 1
  Server.rooms[room.id] = room
  room.players[p.id] = p
  p.room = room.id
  p.ready = false
  sendTo(conn, T.ROOM_STATE, roomStateMsg(room))
  log("player %s created room #%d '%s'", p.name, room.id, room.name)
end

local function joinRoom(conn, p, room)
  room.players[p.id] = p
  p.room = room.id
  p.ready = false
  broadcastRoomState(room)
  sendTo(conn, T.ROOM_STATE, roomStateMsg(room))
end

local function onRoomJoin(conn, msg)
  local p = conn.data
  if not p or p.id == 0 then return sendError(conn, E.PROTOCOL, "handshake first") end
  if p.room then return sendError(conn, E.PROTOCOL, "already in a room") end
  local room = Server.rooms[msg.roomId]
  if not room then return sendError(conn, E.NOT_FOUND, "room not found") end
  if room.status == "live" then return sendError(conn, E.IN_MATCH, "match in progress") end
  if roomPlayerCount(room) >= room.maxPlayers then return sendError(conn, E.FULL, "room full") end
  if room.password and room.password ~= "" and room.password ~= msg.password then
    return sendError(conn, E.BAD_PASSWORD, "wrong password")
  end
  joinRoom(conn, p, room)
  log("player %s joined room #%d", p.name, room.id)
end

local function onRoomLeave(conn)
  local p = conn.data
  if not p or not p.room then return end
  local room = Server.rooms[p.room]
  p.room = nil
  if room then
    room.players[p.id] = nil
    if room.sim then room.sim:removeTank(p.id) end
    if room.hostId == p.id then
      local nextHost
      for _, other in pairs(room.players) do
        if not other.isBot then nextHost = other; break end
      end
      if nextHost then room.hostId = nextHost.id
      else Server.rooms[room.id] = nil; room = nil end
    end
    if room then broadcastRoomState(room) end
  end
end

local function onChat(conn, msg)
  local p = conn.data
  if not p or not p.room then return end
  local now = socket.gettime()
  if now - (p.lastChat or 0) < 0.4 then return end
  p.lastChat = now
  local room = Server.rooms[p.room]
  if not room then return end
  local text = Protocol.sanitizeChat(msg.text)
  if #text == 0 then return end
  local chat = { playerId = p.id, name = p.name, text = text }
  for _, other in pairs(room.players) do
    if other.conn then sendTo(other.conn, T.CHAT, chat) end
  end
end

local function onInviteSend(conn, msg)
  local p = conn.data
  if not p or not p.room then return end
  local room = Server.rooms[p.room]
  if not room then return end
  local target = playerById(msg.targetId)
  if not target or target.conn == conn or target.room then
    return sendError(conn, E.NOT_FOUND, "player unavailable")
  end
  local inviteId = Server.nextInviteId % 256
  Server.nextInviteId = Server.nextInviteId + 1
  Server.invites[inviteId] = { from = p.id, roomId = room.id, expires = socket.gettime() + 120 }
  sendTo(target.conn, T.INVITE, {
    inviteId = inviteId, fromId = p.id, fromName = p.name,
    roomId = room.id, roomName = room.name,
  })
  log("invite %d: %s -> %s", inviteId, p.name, target.name)
end

local function onInviteAccept(conn, msg)
  local p = conn.data
  if not p or p.id == 0 then return end
  if p.room then return sendError(conn, E.PROTOCOL, "already in a room") end
  local inv = Server.invites[msg.inviteId]
  if not inv or socket.gettime() > inv.expires then
    return sendError(conn, E.NOT_FOUND, "invite expired")
  end
  Server.invites[msg.inviteId] = nil
  local room = Server.rooms[inv.roomId]
  if not room then return sendError(conn, E.NOT_FOUND, "room gone") end
  if room.status == "live" then return sendError(conn, E.IN_MATCH, "match in progress") end
  if roomPlayerCount(room) >= room.maxPlayers then return sendError(conn, E.FULL, "room full") end
  joinRoom(conn, p, room)
end

local function onLoadout(conn, msg)
  local p = conn.data
  if not p then return end
  p.tankId, p.camoId, p.upgrades = Protocol.sanitizeLoadout(msg)
  if p.room then
    local room = Server.rooms[p.room]
    if room then broadcastRoomState(room) end
  end
end

local function onReady(conn, msg)
  local p = conn.data
  if not p or not p.room then return end
  p.ready = msg.ready and true or false
  local room = Server.rooms[p.room]
  if room then broadcastRoomState(room) end
end

local function onRoomConfig(conn, msg)
  local p = conn.data
  if not p or not p.room then return end
  local room = Server.rooms[p.room]
  if not room or room.hostId ~= p.id then
    return sendError(conn, E.NOT_HOST, "host only")
  end
  local cfg = clampRoomConfig(msg)
  room.modeId, room.mapId = cfg.modeId, cfg.mapId
  room.maxPlayers, room.bots, room.difficulty = cfg.maxPlayers, cfg.bots, cfg.difficulty
  broadcastRoomState(room)
end

local function onKick(conn, msg)
  local p = conn.data
  if not p or not p.room then return end
  local room = Server.rooms[p.room]
  if not room or room.hostId ~= p.id then
    return sendError(conn, E.NOT_HOST, "host only")
  end
  local target = room.players[msg.playerId]
  if target and target.conn and target.conn ~= conn then
    sendTo(target.conn, T.KICKED, { reason = "kicked by host" })
    target.room = nil
    room.players[target.id] = nil
    if room.sim then room.sim:removeTank(target.id) end
    broadcastRoomState(room)
  end
end

local function onQuickMatch(conn, msg)
  local p = conn.data
  if not p or p.id == 0 then return end
  if p.room then return end
  local modeId = Modes.byId[msg.modeId] and msg.modeId or "dm"
  local best
  for _, room in pairs(Server.rooms) do
    if room.modeId == modeId and room.status == "lobby"
       and (not room.password or room.password == "")
       and roomPlayerCount(room) < room.maxPlayers then
      best = room
      break
    end
  end
  if not best then
    best = {
      id = Server.nextRoomId,
      name = "Quick " .. Modes.get(modeId).name,
      modeId = modeId, mapId = "outpost", maxPlayers = 8,
      bots = 3, difficulty = 2,
      password = nil, hostId = p.id, status = "lobby", players = {},
    }
    Server.nextRoomId = Server.nextRoomId + 1
    Server.rooms[best.id] = best
    log("quick match created room #%d", best.id)
  end
  joinRoom(conn, p, best)
end

local function onStartMatch(conn)
  local p = conn.data
  if not p or not p.room then return end
  local room = Server.rooms[p.room]
  if not room or room.hostId ~= p.id then
    return sendError(conn, E.NOT_HOST, "host only")
  end
  if room.status ~= "lobby" then return end
  local mode = Modes.get(room.modeId)
  local n = roomPlayerCount(room)
  -- humans must satisfy minPlayers unless bots will fill the roster
  if (room.bots or 0) == 0 and n < (mode.minPlayers or 2) then
    return sendError(conn, E.PROTOCOL, "need " .. (mode.minPlayers or 2) .. " players (or add bots)")
  end
  startMatch(room)
end

local function onDisconnect(conn)
  local p = conn.data
  if p then removePlayer(p, "client quit") end
end

--=============================================================================
-- Boot + main loop
--=============================================================================

-- non-blocking pump+tick used by the blocking loop and by tests
function Server.pumpAndTick(dt)
  transport:pump()
  for _, room in pairs(Server.rooms) do
    if room.status == "live" and room.sim then
      local sim = room.sim
      Bot.update(sim, dt)
      sim:step(dt)
      local snap = sim:snapshot()
      for _, p in pairs(room.players) do
        if p.conn then transport:sendTo(p.conn, T.SNAPSHOT, snap) end
      end
      if sim.over and not room.scoreSubmitted then
        room.scoreSubmitted = true
        room.endTimer = 2.0
      end
      if room.endTimer then
        room.endTimer = room.endTimer - dt
        if room.endTimer <= 0 then
          room.endTimer = nil
          endMatch(room)
        end
      end
    end
  end
end

function Server.info()
  if transport and transport.udp then
    local ip, port = transport.udp:getsockname()
    return { ip = ip, port = port }
  end
end

function Server.start(opts)
  opts = opts or {}
  local port = opts.port or Protocol.DEFAULT_PORT
  Maps.init(); Tanks.init(); Modes.init()

  if not Transport.available then
    print("FATAL: LuaSocket missing - cannot run server")
    if opts.exitOnError == false then return nil, "no luasocket" end
    os.exit(1)
  end
  local ok, err = pcall(function() transport = Transport.new(true, port) end)
  if not ok or not transport then
    print("FATAL: cannot bind UDP " .. tostring(port) .. ": " .. tostring(err))
    if opts.exitOnError == false then return nil, err end
    os.exit(1)
  end

  -- connection records get a player shell
  local origConn = transport.serverConn
  function transport:serverConn(key, ip, port)
    local c = origConn(self, key, ip, port)
    if not c.data then
      c.data = {
        id = 0, name = "?", conn = c, room = nil,
        tankId = "scout", camoId = "none", upgrades = { 0, 0, 0, 0, 0 },
        level = 1, ready = false, isBot = false, lastChat = 0,
      }
      c.data.conn = c
    end
    return c
  end

  transport:on(T.HELLO, onHello)
  transport:on(T.INPUT, onInput)
  transport:on(T.PING, onPing)
  transport:on(T.LOBBY_LIST, onLobbyList)
  transport:on(T.LOBBY_PLAYERS, onLobbyPlayers)
  transport:on(T.ROOM_CREATE, onRoomCreate)
  transport:on(T.ROOM_JOIN, onRoomJoin)
  transport:on(T.ROOM_LEAVE, onRoomLeave)
  transport:on(T.ROOM_CHAT, onChat)
  transport:on(T.INVITE_SEND, onInviteSend)
  transport:on(T.INVITE_ACCEPT, onInviteAccept)
  transport:on(T.SET_LOADOUT, onLoadout)
  transport:on(T.SET_READY, onReady)
  transport:on(T.ROOM_CONFIG, onRoomConfig)
  transport:on(T.KICK, onKick)
  transport:on(T.QUICK_MATCH, onQuickMatch)
  transport:on(T.START_MATCH, onStartMatch)
  transport:on(T.DISCONNECT, onDisconnect)

  log("Steel Arena server listening on UDP %d", port)

  if opts.loop == false then return true end   -- test mode: caller drives ticks

  local last = socket.gettime()
  local acc = 0
  while true do
    local now = socket.gettime()
    acc = acc + (now - last)
    last = now
    if acc >= TICK_DT then
      Server.pumpAndTick(math.min(acc, 0.25))
      acc = 0
    else
      transport:pump()
    end
    transport:service(0.016)
    socket.sleep(0.001)
  end
end

return Server
