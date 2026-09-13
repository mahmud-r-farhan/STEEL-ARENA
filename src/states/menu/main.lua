--=============================================================================
-- Main menu: first screen. Player name, server connect, solo, meta screens.
--=============================================================================

local Kit   = require("ui.kit")
local Modes = require("data.modes")
local Maps  = require("data.maps")
local ClientMod = require("game.client")
local States = require("core.state")

local function States_switch(name, opts)
  States.switch(name, opts)
end

local gfx = love.graphics
local W, H = gfx.getWidth, gfx.getHeight

local Main = {}

local S = {}

function Main.enter(shared, opts)
  S.shared = shared
  if not shared.client then
    shared.client = ClientMod.new(shared)
  end
  S.client = shared.client
  S.error = opts and opts.error
  S.nameBuf = shared.save.data.name or ""
  S.hostBuf = shared.settings.data.last_server or "127.0.0.1"
  S.showSoloCfg = false
  S.solo = { modeId = "solo", mapId = "outpost", enemies = 4, allies = 1, difficulty = 2, tankId = shared.save.data.selected }
end

function Main.update(dt)
  Kit.newFrame()
  local c = S.client
  if c.status == "connected" and not (c.room) then
    -- auto-refresh lobby while browsing
    c.lobbyRefresh = true
  end
  if c.status == "connected" then
    c:update(dt)
  end
  -- wait for match start -> jump to battle
  if c.match then
    States_switch("battle", {})
  end
end

function Main.draw()
  local w, h = W(), H()
  gfx.clear(0.06, 0.075, 0.1)
  local save = S.shared.save

  -- animated background strip of tanks
  local t = love.timer.getTime()
  gfx.setColor(0.08, 0.1, 0.13)
  gfx.rectangle("fill", 0, h - 120, w, 120)
  for i = 0, 7 do
    local x = (t * 40 + i * 200) % (w + 200) - 100
    local scale = 1.6
    gfx.push()
    gfx.translate(x, h - 45)
    gfx.scale(scale, scale)
    gfx.setColor(0.18, 0.22, 0.26)
    gfx.rectangle("fill", -14, -10, 28, 16, 3)
    gfx.rectangle("fill", -4, -14, 10, 8, 2)
    gfx.pop()
  end

  -- title
  Kit._font(46)
  gfx.setColor(0.95, 0.55, 0.2)
  gfx.printf("STEEL ARENA", 0, 60, w, "center")
  Kit._font(15)
  gfx.setColor(0.6, 0.65, 0.72)
  gfx.printf("2D multiplayer tank battles", 0, 112, w, "center")

  -- status line
  local statusText = ({
    offline = "OFFLINE - enter name + server, then CONNECT",
    connecting = "Connecting...",
    connected = "Connected (" .. (S.client.room and "in room" or "lobby") .. ")",
    disconnected = "Disconnected: " .. tostring(S.client.error or "unknown"),
  })[S.client.status] or ""
  local colMap = { offline = { 0.8, 0.6, 0.3 }, connecting = { 0.9, 0.8, 0.3 },
    connected = { 0.4, 0.9, 0.5 }, disconnected = { 1, 0.4, 0.4 } }
  Kit.text(statusText, 30, 160, 14, colMap[S.client.status] or { 0.8, 0.8, 0.8 })

  -- left column: profile
  local px, py = 30, 200
  Kit.panel(px, py, 380, 240)
  Kit.text("CALLSIGN", px + 16, py + 14, 12, { 0.6, 0.64, 0.7 })
  S.nameBuf = Kit.textInput("name", px + 16, py + 32, 200, 28, S.nameBuf, "your name")
  Kit.text("SERVER", px + 16, py + 74, 12, { 0.6, 0.64, 0.7 })
  S.hostBuf = Kit.textInput("host", px + 16, py + 92, 200, 28, S.hostBuf, "ip or host")
  Kit.text("profile L" .. save.data.level .. "   " .. save.data.credits .. " CR",
    px + 16, py + 130, 13, { 1, 0.85, 0.35 })

  if S.client.status == "connected" then
    if Kit.button("disc", "DISCONNECT", px + 16, py + 156, 200, 32) then
      S.client:disconnect()
    end
    if Kit.button("lobby", "MULTIPLAYER LOBBY", px + 16, py + 196, 200, 32, { color = { 0.2, 0.4, 0.25 } }) then
      States_switch("menu.play")
    end
  else
    if Kit.button("connect", "CONNECT", px + 16, py + 156, 200, 32, { color = { 0.2, 0.35, 0.5 } }) then
      local name = S.nameBuf:match("^%s*(.-)%s*$")
      if #name >= 2 then
        S.shared.save.data.name = name
        S.shared.save.dirty = true
        S.shared.settings.data.last_server = S.hostBuf
        S.shared.settings.save()
        S.client:connect(S.hostBuf)
      else
        S.error = "Name needs 2+ characters"
      end
    end
  end

  -- right column: quick actions
  local qx, qy = w - 430, 200
  Kit.panel(qx, qy, 400, 240)
  Kit.text("QUICK PLAY", qx + 16, qy + 14, 12, { 0.6, 0.64, 0.7 })
  if Kit.button("solo", "SOLO ASSAULT (PvE)", qx + 16, qy + 36, 200, 34) then
    S.showSoloCfg = not S.showSoloCfg
  end
  if Kit.button("hostinfo", "HOST A SERVER", qx + 16, qy + 78, 200, 30) then
    S.showHostInfo = not S.showHostInfo
  end
  if Kit.button("store", "STORE", qx + 16, qy + 116, 96, 32, { color = { 0.35, 0.28, 0.12 } }) then
    States_switch("menu.store")
  end
  if Kit.button("garage", "GARAGE", qx + 122, qy + 116, 94, 32, { color = { 0.12, 0.28, 0.35 } }) then
    States_switch("menu.garage")
  end
  if Kit.button("settings", "SETTINGS", qx + 16, qy + 156, 96, 32) then
    States.push("menu.settings")
  end
  if Kit.button("quit", "QUIT", qx + 122, qy + 156, 94, 32, { color = { 0.4, 0.15, 0.15 } }) then
    love.event.quit()
  end

  -- solo config panel
  if S.showSoloCfg then
    local cx, cy = w / 2 - 240, 460
    Kit.panel(cx, cy, 480, 190)
    Kit.text("SOLO SETUP", cx + 16, cy + 12, 13, { 0.9, 0.9, 0.95 })
    Kit.text("MAP", cx + 16, cy + 44, 12, { 0.6, 0.64, 0.7 })
    local maps = Maps.all()
    local bx = cx + 16
    for i, m in ipairs(maps) do
      if Kit.button("map" .. i, m.name, bx, cy + 38, 105, 26, { fontSize = 12,
        color = (m.id == S.solo.mapId) and { 0.2, 0.4, 0.5 } or nil }) then
        S.solo.mapId = m.id
      end
      bx = bx + 110
    end
    Kit.text("ENEMIES: " .. S.solo.enemies, cx + 16, cy + 84, 13)
    S.solo.enemies = math.floor(Kit.slider("enemies", cx + 110, cy + 80, 180, S.solo.enemies, 1, 10))
    Kit.text("ALLIES: " .. S.solo.allies, cx + 16, cy + 114, 13)
    S.solo.allies = math.floor(Kit.slider("allies", cx + 110, cy + 110, 180, S.solo.allies, 0, 3))
    local diffs = { "Easy", "Normal", "Hard", "Ace" }
    Kit.text("DIFFICULTY: " .. diffs[S.solo.difficulty], cx + 16, cy + 144, 13)
    local dx = cx + 16
    for i = 1, 4 do
      if Kit.button("diff" .. i, diffs[i], dx, cy + 158, 80, 24, { fontSize = 12,
        color = (S.solo.difficulty == i) and { 0.2, 0.4, 0.5 } or nil }) then
        S.solo.difficulty = i
      end
      dx = dx + 85
    end
    if Kit.button("sologo", "DEPLOY", cx + 360, cy + 90, 100, 40, { color = { 0.2, 0.45, 0.25 } }) then
      States_switch("battle", { mode = "solo", config = {
        mapId = S.solo.mapId, modeId = "solo", enemies = S.solo.enemies,
        allies = S.solo.allies, difficulty = S.solo.difficulty, tankId = S.shared.save.data.selected,
      } })
    end
  end

  -- host info popup
  if S.showHostInfo then
    local hx, hy = w / 2 - 260, 460
    Kit.panel(hx, hy, 520, 150, { 0.09, 0.11, 0.14, 0.97 })
    Kit.text("To host multiplayer:", hx + 16, hy + 12, 14, { 0.95, 0.8, 0.4 })
    Kit.text("love src --server        (or: lua server/bootstrap.lua)",
      hx + 16, hy + 40, 13, { 0.85, 0.88, 0.92 })
    Kit.text("Friends connect to your IP, port " .. tostring(require("net.protocol").DEFAULT_PORT) .. " (UDP).",
      hx + 16, hy + 64, 13, { 0.7, 0.74, 0.8 })
    Kit.text("You can also play + host from the same machine (127.0.0.1).",
      hx + 16, hy + 84, 13, { 0.7, 0.74, 0.8 })
    if Kit.button("closehost", "CLOSE", hx + 400, hy + 108, 100, 28) then
      S.showHostInfo = false
    end
  end

  if S.error then
    Kit.text(S.error, 30, h - 30, 14, { 1, 0.4, 0.4 })
  end
  if S.client.toast then
    Kit.text(S.client.toast.text, 30, h - 52, 14, { 1, 0.9, 0.5 })
  end
end

function Main.mousepressed(x, y, b) Kit.mousepressed(x, y, b) end
function Main.mousereleased(x, y, b) Kit.mousereleased(x, y, b) end
function Main.mousemoved(x, y) Kit.mousemoved(x, y) end
function Main.keypressed(key, sc)
  if key == "escape" then love.event.quit() end
end
function Main.textinput(text)
  if Kit.textCapture == "name" then
    if #S.nameBuf < 16 then S.nameBuf = S.nameBuf .. text end
  elseif Kit.textCapture == "host" then
    if #S.hostBuf < 40 then S.hostBuf = S.hostBuf .. text end
  end
end

return Main
