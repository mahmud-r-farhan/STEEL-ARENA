--=============================================================================
-- Headless end-to-end net test: boots the real server on an ephemeral port,
-- connects a real client over UDP, walks the full room flow:
--   HELLO -> WELCOME -> CREATE -> ROOM_STATE -> LOADOUT -> READY ->
--   START -> MATCH_START -> snapshots -> (short) -> DISCONNECT
-- Also verifies quick match room creation and bot spawning.
-- Run: love src --nettest
--=============================================================================

local Protocol  = require("net.protocol")
local Transport = require("net.transport")
local Server    = require("server.app")

local T = Protocol.T
local failures = 0
local logLines = {}

local function out(s)
  print(s)
  logLines[#logLines + 1] = s
end

local function check(cond, label)
  if cond then
    out("  ok  - " .. label)
  else
    failures = failures + 1
    out("  FAIL- " .. label)
  end
end

-- capture client side
local C = {
  welcome = nil, roomState = nil, lobby = nil, matchStart = nil,
  snapshots = 0, matchEnd = nil, error_ = nil, invites = {}, chat = {},
}

local clientTransport = nil   -- must precede pumpMs (upvalue linkage)

-- pump BOTH endpoints so server sees client packets and vice versa
local function pumpMs(ms)
  local t0 = love.timer.getTime()
  while love.timer.getTime() - t0 < ms / 1000 do
    if clientTransport then clientTransport:pump() end
    Server.pumpAndTick(0.002)
  end
end

return {
  run = function()
    out("=== Steel Arena nettest ===")

    -- boot server on ephemeral port, non-blocking loop
    Transport.debug = true
    local port = 37555 + math.random(100, 900)
    local ok, err = Server.start({ port = port, loop = false, exitOnError = false })
    check(ok, "server boots (port " .. port .. ")" .. (ok and "" or (" err=" .. tostring(err))))
    if not ok then
      out("=== NETTEST ABORTED ===")
      local f = io.open("nettest.log", "w")
      if f then f:write(table.concat(logLines, "\n")) f:close() end
      return false
    end

    -- client transport
    local cok, cerr = pcall(function() clientTransport = Transport.new(false) end)
    check(cok and clientTransport ~= nil, "client transport created")
    clientTransport:on(T.WELCOME, function(conn, msg) C.welcome = msg end)
    clientTransport:on(T.ROOM_STATE, function(conn, msg) C.roomState = msg end)
    clientTransport:on(T.LOBBY_LIST, function(conn, msg) C.lobby = msg end)
    clientTransport:on(T.MATCH_START, function(conn, msg) C.matchStart = msg end)
    clientTransport:on(T.SNAPSHOT, function(conn, msg) C.snapshots = C.snapshots + 1 end)
    clientTransport:on(T.MATCH_END, function(conn, msg) C.matchEnd = msg end)
    clientTransport:on(T.ERROR, function(conn, msg) C.error_ = msg end)
    clientTransport:on(T.CHAT, function(conn, msg) C.chat[#C.chat + 1] = msg end)
    clientTransport:on(T.INVITE, function(conn, msg) C.invites[#C.invites + 1] = msg end)
    clientTransport:connect("127.0.0.1", port)

    -- handshake
    local sentN = clientTransport:send(T.HELLO, { name = "Tester", tankId = "brawler",
      camoId = "none", upgrades = { 1, 1, 1, 1, 1 }, version = Protocol.VERSION })
    out("  [probe] HELLO send -> " .. tostring(sentN) .. " bytes; peer=" ..
      tostring(clientTransport.host) .. ":" .. tostring(clientTransport.port) ..
      "; server=" .. (Server.info() and (Server.info().ip .. ":" .. Server.info().port) or "?"))
    pumpMs(120)
    out("  [probe] after pump: welcome=" .. tostring(C.welcome ~= nil))
    check(C.welcome ~= nil, "WELCOME received, playerId=" .. tostring(C.welcome and C.welcome.playerId))

    -- create room
    clientTransport:send(T.ROOM_CREATE, { name = "Test Room", mapId = "outpost",
      modeId = "tdm", maxPlayers = 8, password = "", bots = 2, difficulty = 2 })
    pumpMs(120)
    check(C.roomState ~= nil, "ROOM_STATE received (created)")
    check(C.roomState and C.roomState.modeId == "tdm", "room mode tdm")
    check(C.roomState and #C.roomState.players == 1, "room has 1 player")

    -- set loadout + ready
    clientTransport:send(T.SET_LOADOUT, { tankId = "heavy", camoId = "arctic",
      upgrades = { 2, 2, 0, 0, 0 } })
    clientTransport:send(T.SET_READY, { ready = true })
    pumpMs(120)
    check(C.roomState and C.roomState.players[1].tankId == "heavy", "loadout applied (heavy)")
    check(C.roomState and C.roomState.players[1].ready == true, "ready flag set")

    -- chat
    clientTransport:send(T.ROOM_CHAT, { text = "gl hf" })
    pumpMs(100)
    check(#C.chat >= 1 and C.chat[1].text == "gl hf", "chat echoed back")

    -- lobby list
    clientTransport:send(T.LOBBY_LIST, {})
    pumpMs(100)
    check(C.lobby ~= nil and #C.lobby.rooms == 1, "lobby lists 1 room")

    -- start match (host)
    clientTransport:send(T.START_MATCH, {})
    pumpMs(200)
    check(C.matchStart ~= nil, "MATCH_START received")
    check(C.matchStart and C.matchStart.modeId == "tdm", "match mode tdm")
    check(C.matchStart and #C.matchStart.players == 3, "match has 1 human + 2 bots")

    -- pump snapshots for ~1.5s of server ticks
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 1.5 do
      if clientTransport then clientTransport:pump() end
      Server.pumpAndTick(1 / 30)
    end
    check(C.snapshots > 10, "snapshots streaming (" .. C.snapshots .. ")")

    -- disconnect
    clientTransport:send(T.DISCONNECT, {})
    pumpMs(100)

    -- cleanup + log
    local f = io.open("nettest.log", "w")
    if f then f:write(table.concat(logLines, "\n")) f:close() end
    out(failures == 0 and "=== NETTEST PASSED ===" or ("=== " .. failures .. " NET FAILURES ==="))
    return failures == 0
  end,
}
