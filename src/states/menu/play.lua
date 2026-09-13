--=============================================================================
-- Multiplayer entry: server browser, quick match, create room.
--=============================================================================

local Kit   = require("ui.kit")
local Modes = require("data.modes")
local Maps  = require("data.maps")
local States = require("core.state")

local gfx = (love and love.graphics) or nil
if not gfx then
  gfx = setmetatable({}, { __index = function() return function() end end })
end
local W, H = function() return 1280, 720 end, function() return 1280, 720 end

local Play = {}

local S = {}

function Play.enter(shared, opts)
  S.shared = shared
  S.client = shared.client
  S.view = "browser"          -- browser | create
  S.scroll = 0
  S.selRoom = nil
  S.pwBuf = ""
  S.creating = {
    name = (shared.save.data.name or "Player") .. "'s room",
    mapId = "outpost", modeId = "dm", maxPlayers = 8,
    password = "", bots = 2, difficulty = 2,
  }
end

function Play.update(dt)
  Kit.newFrame()
  local c = S.client
  if not c or c.status ~= "connected" then
    States.switch("menu.main")
    return
  end
  c.lobbyRefresh = true
  c:update(dt)
  if c.match then
    States.switch("battle", {})
  end
end

function Play.draw()
  local w, h = W(), H()
  gfx.clear(0.06, 0.075, 0.1)
  local c = S.client

  Kit._font(30)
  gfx.setColor(0.92, 0.94, 0.97)
  gfx.printf("MULTIPLAYER", 0, 26, w, "center")

  -- top bar buttons
  local bw = 150
  if Kit.button("back", "BACK", 30, 34, 110, 34) then
    States.switch("menu.main")
  end
  if Kit.button("refresh", "REFRESH", 150, 34, 110, 34) then
    c:requestLobby()
  end
  if Kit.button("create", "CREATE ROOM", w - 320, 34, 130, 34, { color = { 0.2, 0.35, 0.5 } }) then
    S.view = "create"
  end
  if Kit.button("quick", "QUICK MATCH", w - 480, 34, 150, 34, { color = { 0.2, 0.4, 0.25 } }) then
    S.quickMode = (S.quickMode == nil) and true or nil
  end

  -- quick match mode picker
  if S.quickMode then
    local qx, qy = w / 2 - 240, 84
    Kit.panel(qx, qy, 480, 64)
    Kit.text("PICK MODE:", qx + 14, qy + 10, 12, { 0.6, 0.64, 0.7 })
    local bx = qx + 14
    for _, m in ipairs(Modes.all()) do
      if m.id ~= "solo" then
        if Kit.button("qm" .. m.id, m.short, bx, qy + 30, 80, 26, { fontSize = 12,
          color = { 0.2, 0.35, 0.45 } }) then
          c:quickMatch(m.id)
          S.quickMode = nil
        end
        bx = bx + 85
      end
    end
  end

  if S.view == "browser" then
    -- room list
    local lx, ly, lw, lh = 30, 120, w - 60, h - 160
    Kit.panel(lx, ly, lw, lh)
    if #c.lobbyRooms == 0 then
      Kit.text("No rooms yet. CREATE ROOM or QUICK MATCH to start one.",
        lx + 20, ly + 20, 14, { 0.7, 0.74, 0.8 })
      Kit.text("Tip: run  love src --server  in another terminal to host a server.",
        lx + 20, ly + 44, 13, { 0.55, 0.6, 0.66 })
    else
      local rowH = 40
      local contentH = #c.lobbyRooms * rowH
      S.scroll = Kit.scrollArea("rooms", lx + 8, ly + 8, lw - 16, lh - 16, contentH, S.wheel, S.scroll)
      local visible = math.ceil((lh - 16) / rowH) + 1
      for i, room in ipairs(c.lobbyRooms) do
        if i >= math.floor(S.scroll / rowH) + 1 and i <= math.floor(S.scroll / rowH) + visible then
          local ry = ly + 8 + (i - 1) * rowH - S.scroll
          local clicked = Kit.listRow("room" .. room.id, lx + 16, ry, lw - 40, rowH - 6)
          gfx.setColor(room.status == 1 and { 0.5, 0.4, 0.2 } or { 0.16, 0.2, 0.26 })
          gfx.rectangle("fill", lx + 16, ry, lw - 40, rowH - 6, 6)
          local mode = Modes.get(room.modeId)
          Kit.text("#" .. room.id .. "  " .. room.name, lx + 28, ry + 10, 14,
            { 0.9, 0.92, 0.95 })
          Kit.text(mode.name .. " - " .. Maps.get(room.mapId).name,
            lx + 300, ry + 12, 13, { 0.65, 0.7, 0.78 })
          Kit.text(room.players .. "/" .. room.maxPlayers, lx + 560, ry + 12, 13, { 0.8, 0.85, 0.9 })
          Kit.text(room.status == 1 and "IN BATTLE" or "LOBBY",
            lx + 640, ry + 12, 13, room.status == 1 and { 1, 0.7, 0.3 } or { 0.4, 0.9, 0.5 })
          if room.hasPassword then
            Kit.text("LOCKED", lx + 740, ry + 12, 13, { 1, 0.6, 0.3 })
          end
          if clicked then S.selRoom = room end
        end
      end
      Kit.endScroll()
    end

    -- join bar
    if S.selRoom then
      local jy = h - 76
      Kit.panel(30, jy, w - 60, 56)
      Kit.text("JOIN: #" .. S.selRoom.id .. " " .. S.selRoom.name, 46, jy + 8, 14, { 0.9, 0.95, 1 })
      if S.selRoom.hasPassword then
        S.pwBuf = Kit.textInput("pw", 400, jy + 14, 180, 26, S.pwBuf, "password")
      end
      if Kit.button("dojoin", "JOIN", w - 200, jy + 12, 150, 32, { color = { 0.2, 0.4, 0.25 } }) then
        c:joinRoom(S.selRoom.id, S.pwBuf)
        S.selRoom = nil
        S.pwBuf = ""
      end
    end
  elseif S.view == "create" then
    drawCreatePanel(w, h)
  end

  -- toasts/errors
  if c.toast then
    Kit.text(c.toast.text, 30, h - 26, 14, { 1, 0.9, 0.5 })
  end
end

function drawCreatePanel(w, h)
  local c = S.client
  local pw, ph = 460, 420
  local px, py = w / 2 - pw / 2, h / 2 - ph / 2
  Kit.panel(px, py, pw, ph)
  Kit.text("CREATE ROOM", px + 20, py + 16, 20, { 0.92, 0.94, 0.97 })

  local cfg = S.creating
  Kit.text("ROOM NAME", px + 20, py + 52, 12, { 0.6, 0.64, 0.7 })
  cfg.name = Kit.textInput("rname", px + 20, py + 68, 300, 28, cfg.name, "room name")

  Kit.text("MODE", px + 20, py + 108, 12, { 0.6, 0.64, 0.7 })
  local bx = px + 20
  for _, m in ipairs(Modes.all()) do
    if m.id ~= "solo" then
      if Kit.button("cm" .. m.id, m.short, bx, py + 124, 80, 28, { fontSize = 12,
        color = (cfg.modeId == m.id) and { 0.2, 0.4, 0.5 } or nil }) then
        cfg.modeId = m.id
      end
      bx = bx + 85
    end
  end

  Kit.text("MAP", px + 20, py + 164, 12, { 0.6, 0.64, 0.7 })
  bx = px + 20
  for _, m in ipairs(Maps.all()) do
    if Kit.button("cmap" .. m.id, m.name, bx, py + 180, 100, 28, { fontSize = 12,
      color = (cfg.mapId == m.id) and { 0.2, 0.4, 0.5 } or nil }) then
      cfg.mapId = m.id
    end
    bx = bx + 105
  end

  Kit.text("MAX PLAYERS: " .. cfg.maxPlayers, px + 20, py + 224, 13)
  cfg.maxPlayers = math.floor(Kit.slider("cmax", px + 160, py + 220, 160, cfg.maxPlayers, 2, 12))

  Kit.text("BOTS: " .. cfg.bots, px + 20, py + 252, 13)
  cfg.bots = math.floor(Kit.slider("cbots", px + 160, py + 248, 160, cfg.bots, 0, 10))

  local diffs = { "Easy", "Normal", "Hard", "Ace" }
  Kit.text("BOT SKILL: " .. diffs[cfg.difficulty], px + 20, py + 280, 13)
  bx = px + 20
  for i = 1, 4 do
    if Kit.button("cd" .. i, diffs[i], bx, py + 294, 80, 26, { fontSize = 12,
      color = (cfg.difficulty == i) and { 0.2, 0.4, 0.5 } or nil }) then
      cfg.difficulty = i
    end
    bx = bx + 85
  end

  Kit.text("PASSWORD (optional)", px + 20, py + 330, 12, { 0.6, 0.64, 0.7 })
  cfg.password = Kit.textInput("cpw", px + 20, py + 344, 200, 26, cfg.password, "none")

  if Kit.button("cgo", "CREATE", px + 320, py + 340, 120, 34, { color = { 0.2, 0.45, 0.25 } }) then
    c:createRoom({
      name = cfg.name, mapId = cfg.mapId, modeId = cfg.modeId,
      maxPlayers = cfg.maxPlayers, password = cfg.password,
      bots = cfg.bots, difficulty = cfg.difficulty,
    })
    S.view = "browser"
  end
  if Kit.button("ccancel", "CANCEL", px + 320, py + 52, 120, 30) then
    S.view = "browser"
  end
end

function Play.wheelmoved(x, y)
  S.wheel = y * 40
end

function Play.mousepressed(x, y, b) Kit.mousepressed(x, y, b) end
function Play.mousereleased(x, y, b) Kit.mousereleased(x, y, b) end
function Play.mousemoved(x, y) Kit.mousemoved(x, y) end

function Play.keypressed(key)
  if key == "escape" then
    if S.view == "create" then S.view = "browser"
    else States.switch("menu.main") end
  end
end

function Play.textinput(text)
  if Kit.textCapture == "rname" and #S.creating.name < 24 then
    S.creating.name = S.creating.name .. text
  elseif Kit.textCapture == "cpw" and #S.creating.password < 20 then
    S.creating.password = S.creating.password .. text
  elseif Kit.textCapture == "pw" and #S.pwBuf < 20 then
    S.pwBuf = S.pwBuf .. text
  end
end

return Play
