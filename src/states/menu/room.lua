--=============================================================================
-- Room lobby: player list, ready toggle, host configuration (mode/map/bots),
-- invite players from lobby, chat, and launch.
--=============================================================================

local Kit   = require("ui.kit")
local Modes = require("data.modes")
local Maps  = require("data.maps")
local Tanks = require("data.tanks")
local States = require("core.state")

local gfx = (love and love.graphics) or nil
if not gfx then
  gfx = setmetatable({}, { __index = function() return function() end end })
end
local W, H = function() return 1280, 720 end, function() return 1280, 720 end

local Room = {}

local S = {}

local function isHost()
  return S.client.room and S.client.room.hostId == S.client.myId
end

function Room.enter(shared, opts)
  S.shared = shared
  S.client = shared.client
  S.chatText = ""
  S.scroll = 0
  S.inviteOpen = false
  if not S.client or S.client.status ~= "connected" then
    States.switch("menu.main")
  end
end

function Room.update(dt)
  Kit.newFrame()
  local c = S.client
  if not c or c.status ~= "connected" then
    States.switch("menu.main")
    return
  end
  c.lobbyRefresh = false
  c:update(dt)
  if c.match then
    States.switch("battle", {})
  elseif not c.room then
    States.switch("menu.play")
  end
end

function Room.draw()
  local w, h = W(), H()
  gfx.clear(0.06, 0.075, 0.1)
  local c = S.client
  local room = c.room
  if not room then return end
  local host = isHost()

  Kit._font(30)
  gfx.setColor(0.92, 0.94, 0.97)
  local mode = Modes.get(room.modeId)
  local map = Maps.get(room.mapId)
  gfx.printf("ROOM: " .. room.name, 0, 26, w, "center")
  Kit._font(14)
  gfx.setColor(0.65, 0.7, 0.78)
  gfx.printf(mode.name .. "  -  " .. map.name .. "  -  " ..
    #room.players .. "/" .. room.maxPlayers ..
    (room.hasPassword and "  [LOCKED]" or ""), 0, 66, w, "center")

  if Kit.button("leave", "LEAVE ROOM", 30, 34, 120, 34, { color = { 0.4, 0.15, 0.15 } }) then
    c:leaveRoom()
    States.switch("menu.play")
  end

  -- players panel (left)
  local lx, ly, lw, lh = 30, 120, 380, h - 240
  Kit.panel(lx, ly, lw, lh)
  Kit.text("PLAYERS " .. #room.players .. "/" .. room.maxPlayers, lx + 16, ly + 12, 14, { 0.85, 0.88, 0.92 })
  local y = ly + 40
  for _, p in ipairs(room.players) do
    local col = p.id == room.hostId and { 1, 0.85, 0.4 } or { 0.85, 0.88, 0.92 }
    local tankDef = Tanks.get(p.tankId) or Tanks.get("scout")
    Kit.text((p.id == room.hostId and "[HOST] " or "") .. p.name, lx + 16, y, 14, col)
    Kit.text(tankDef.name, lx + 170, y, 13, { 0.6, 0.7, 0.8 })
    Kit.text(p.ready and "READY" or "not ready", lx + 270, y, 13,
      p.ready and { 0.4, 0.9, 0.5 } or { 0.6, 0.64, 0.7 })
    if host and p.id ~= c.myId and not p.isBot then
      if Kit.button("kick" .. p.id, "X", lx + lw - 36, y - 4, 24, 22, { fontSize = 11,
        color = { 0.45, 0.15, 0.15 } }) then
        c:kick(p.id)
      end
    end
    y = y + 28
  end

  -- config panel (right) - host editable, others read-only
  local rx, ry = 440, 120
  local rw, rh = w - rx - 30, h - 240
  Kit.panel(rx, ry, rw, rh)
  Kit.text(host and "MATCH SETTINGS (host)" or "MATCH SETTINGS", rx + 16, ry + 12, 14, { 0.85, 0.88, 0.92 })

  local cfgY = ry + 42
  Kit.text("MODE", rx + 16, cfgY, 12, { 0.6, 0.64, 0.7 })
  local bx = rx + 70
  for _, m in ipairs(Modes.all()) do
    if m.id ~= "solo" then
      local enabled = host
      if Kit.button("rm" .. m.id, m.short, bx, cfgY - 6, 78, 26, { fontSize = 12,
        color = (room.modeId == m.id) and { 0.2, 0.4, 0.5 } or nil }) then
        if host then c:setConfig({ modeId = m.id, mapId = room.mapId,
          maxPlayers = room.maxPlayers, bots = room.bots, difficulty = room.difficulty }) end
      end
      bx = bx + 83
    end
  end

  cfgY = cfgY + 40
  Kit.text("MAP", rx + 16, cfgY, 12, { 0.6, 0.64, 0.7 })
  bx = rx + 70
  for _, m in ipairs(Maps.all()) do
    if Kit.button("rmap" .. m.id, m.name, bx, cfgY - 6, 96, 26, { fontSize = 12,
      color = (room.mapId == m.id) and { 0.2, 0.4, 0.5 } or nil }) then
      if host then c:setConfig({ modeId = room.modeId, mapId = m.id,
        maxPlayers = room.maxPlayers, bots = room.bots, difficulty = room.difficulty }) end
    end
    bx = bx + 101
  end

  cfgY = cfgY + 40
  Kit.text("BOTS: " .. room.bots, rx + 16, cfgY, 13)
  if host then
    local nb = math.floor(Kit.slider("rbots", rx + 90, cfgY - 4, 160, room.bots, 0, 10))
    if nb ~= room.bots then
      c:setConfig({ modeId = room.modeId, mapId = room.mapId,
        maxPlayers = room.maxPlayers, bots = nb, difficulty = room.difficulty })
    end
  end

  cfgY = cfgY + 36
  local diffs = { "Easy", "Normal", "Hard", "Ace" }
  Kit.text("BOT SKILL: " .. diffs[room.difficulty], rx + 16, cfgY, 13)
  if host then
    bx = rx + 130
    for i = 1, 4 do
      if Kit.button("rd" .. i, diffs[i], bx, cfgY - 6, 72, 24, { fontSize = 11,
        color = (room.difficulty == i) and { 0.2, 0.4, 0.5 } or nil }) then
        c:setConfig({ modeId = room.modeId, mapId = room.mapId,
          maxPlayers = room.maxPlayers, bots = room.bots, difficulty = i })
      end
      bx = bx + 77
    end
  end

  -- loadout summary + ready
  local me
  for _, p in ipairs(room.players) do
    if p.id == c.myId then me = p end
  end
  cfgY = cfgY + 44
  if me then
    local td = Tanks.get(me.tankId) or Tanks.get("scout")
    Kit.text("YOUR LOADOUT: " .. td.name .. " (" .. td.class .. ")",
      rx + 16, cfgY, 14, { 0.9, 0.92, 0.95 })
    if Kit.button("garage", "CHANGE IN GARAGE", rx + 16, cfgY + 24, 180, 30) then
      States.push("menu.garage")
    end
  end

  -- bottom action bar
  local by = h - 100
  Kit.panel(30, by, w - 60, 76)
  local meReady = me and me.ready
  if Kit.button("ready", meReady and "UNREADY" or "READY UP", 46, by + 20, 140, 36,
    { color = meReady and { 0.35, 0.3, 0.15 } or { 0.2, 0.45, 0.25 } }) then
    c:setReady(not meReady)
  end
  if Kit.button("invite", "INVITE", 200, by + 20, 110, 36) then
    S.inviteOpen = not S.inviteOpen
  end
  if host then
    local canStart = #room.players >= (mode.minPlayers or 2)
    if Kit.button("start", "START BATTLE", w - 220, by + 20, 170, 36,
      { color = canStart and { 0.2, 0.45, 0.25 } or { 0.35, 0.2, 0.15 } }) then
      c:startMatch()
    end
    if not canStart then
      Kit.text("need " .. (mode.minPlayers or 2) .. "+ players (add bots!)",
        w - 220, by + 60, 12, { 1, 0.6, 0.4 })
    end
  else
    Kit.text("waiting for host to start...", w - 260, by + 28, 13, { 0.6, 0.64, 0.7 })
  end

  -- chat (bottom left)
  local cy = h - 200
  Kit.beginClip(30, cy - 90, 380, 88)
  local startIdx = math.max(1, #c.chatLog - 4)
  for i = startIdx, #c.chatLog do
    local msg = c.chatLog[i]
    gfx.setColor(0.85, 0.9, 0.95, 0.9)
    gfx.print(msg.name .. ": " .. msg.text, 38, cy - 90 + (i - startIdx) * 17)
  end
  Kit.endClip()
  if Kit.textCapture == "rchat" then
    Kit.textInput("rchat", 30, h - 112, 360, 24, S.chatText, "")
    Kit.text("ENTER send", 398, h - 106, 11, { 1, 1, 1, 0.4 })
  end

  -- invite overlay
  if S.inviteOpen then
    local iw, ih = 360, 300
    local ix, iy = w / 2 - iw / 2, h / 2 - ih / 2
    Kit.panel(ix, iy, iw, ih)
    Kit.text("INVITE PLAYERS", ix + 16, iy + 12, 16, { 0.92, 0.94, 0.97 })
    Kit.text("Players currently in the server lobby (not in a room):",
      ix + 16, iy + 40, 12, { 0.6, 0.64, 0.7 })
    local oy = iy + 62
    local any = false
    -- NOTE: full server-wide player list is not exposed by LOBBY_LIST;
    -- inviting works from the PLAY screen player directory or via room code.
    Kit.text("Ask friends to join, or share the room id #" .. room.id,
      ix + 16, oy, 13, { 0.85, 0.9, 0.95 })
    Kit.text("They will see this room in the browser.", ix + 16, oy + 22, 13, { 0.7, 0.74, 0.8 })
    if Kit.button("iclose", "CLOSE", ix + iw - 100, iy + ih - 40, 84, 28) then
      S.inviteOpen = false
    end
  end
end

function Room.mousepressed(x, y, b) Kit.mousepressed(x, y, b) end
function Room.mousereleased(x, y, b) Kit.mousereleased(x, y, b) end
function Room.mousemoved(x, y) Kit.mousemoved(x, y) end

function Room.keypressed(key)
  if key == "escape" then
    if Kit.textCapture then
      Kit.textCapture = nil
    else
      S.client:leaveRoom()
      States.switch("menu.play")
    end
  elseif (key == "return" or key == "kpenter") then
    if Kit.textCapture == "rchat" then
      if S.chatText ~= "" then
        S.client:sendChat(S.chatText)
        S.chatText = ""
      end
      Kit.textCapture = nil
    else
      Kit.textCapture = "rchat"
    end
  elseif key == "backspace" and Kit.textCapture == "rchat" then
    S.chatText = S.chatText:sub(1, -2)
  end
end

function Room.textinput(text)
  if Kit.textCapture == "rchat" and #S.chatText < 110 then
    S.chatText = S.chatText .. text
  end
end

function Room.resize()
end

return Room
