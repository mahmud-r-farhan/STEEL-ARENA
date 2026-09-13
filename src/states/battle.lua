--=============================================================================
-- Battle state: live gameplay. Handles input, camera, world rendering, HUD,
-- killfeed, scoreboard, chat, pause and the results overlay.
--=============================================================================

local Kit    = require("ui.kit")
local Maps   = require("data.maps")
local Tanks  = require("data.tanks")
local Modes  = require("data.modes")
local World  = require("render.world")
local Protocol = require("net.protocol")
local States = require("core.state")

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

local gfx = love.graphics
local W, H = gfx.getWidth, gfx.getHeight

local Battle = {}

local EV = Protocol.EV
local POWER_KEYS = { "repair", "shield", "rapid", "damage", "speed" }

local S = {}   -- state locals

function Battle.enter(shared, opts)
  S.shared = shared
  S.client = shared.client
  S.audio  = shared.audio
  S.world  = shared.world or World.new()
  shared.world = S.world

  S.opts = opts or {}
  S.cam = { x = 0, y = 0, zoom = 1 }
  S.chatOpen = false
  S.chatText = ""
  S.paused = false
  S.showScore = false
  S.killfeed = {}         -- {text, t, color}
  S.hitMarker = 0
  S.hurtFlash = 0
  S.myLastHp = nil
  S.respawnWas = false
  S.resultsAck = false
  S.time = 0
  S.camInit = false

  if S.opts.mode == "solo" then
    local cfg = S.opts.config or {}
    S.client:startLocalSolo({
      mapId = cfg.mapId or "outpost",
      modeId = cfg.modeId or "solo",
      difficulty = cfg.difficulty or 2,
      enemies = cfg.enemies or 4,
      allies = cfg.allies or 0,
      tankId = cfg.tankId,
    })
  end
end

function Battle.leave()
  if S.client then
    -- leaving state mid-match (via pause quit): drop local sim only
    S.client:leaveMatch()
  end
end

function Battle.resume()
  S.paused = false
end

--=============================================================================
-- Input
--=============================================================================

local function screenToWorld(sx, sy)
  local w, h = W(), H()
  return (sx - w / 2) / S.cam.zoom + S.cam.x, (sy - h / 2) / S.cam.zoom + S.cam.y
end

local function myTank()
  local c = S.client
  if c.localSim then return c.localSim.tanksById[1] end
  if c.match then
    for _, t in ipairs(c:renderState()) do
      if t.id == c.myId then return t end
    end
  end
end

local function buildInput()
  local k = love.keyboard.isDown
  local move = 0
  if k("w") or k("up") then move = move + 1 end
  if k("s") or k("down") then move = move - 1 end
  local turn = 0
  if k("d") or k("right") then turn = turn + 1 end
  if k("a") or k("left") then turn = turn - 1 end

  local mx, my = love.mouse.getPosition()
  local wx, wy = screenToWorld(mx, my)
  local me = myTank()
  local turret = (me and me.turret) or 0
  if me then
    turret = atan2(wy - me.y, wx - me.x)
  end
  local fire = love.mouse.isDown(1) or k("space")
  if S.chatOpen or S.paused then
    move, turn, fire = 0, 0, false
  end
  return { move = move, turn = turn, turret = turret, fire = fire }
end

--=============================================================================
-- Events -> fx/audio/feed
--=============================================================================

local function nameOf(id)
  local c = S.client
  if id == 0 then return "" end
  if c.match and c.match.players[id] then return c.match.players[id].name end
  return "?"
end

local function teamOf(id)
  local c = S.client
  local p = c.match and c.match.players[id]
  return p and p.team or 0
end

local function feed(text, color)
  S.killfeed[#S.killfeed + 1] = { text = text, t = 5, color = color or { 0.9, 0.92, 0.95 } }
  if #S.killfeed > 6 then table.remove(S.killfeed, 1) end
end

local function distVol(x, y)
  local d = math.sqrt((x - S.cam.x) ^ 2 + (y - S.cam.y) ^ 2)
  return math.max(0.15, 1 - d / 1100)
end

local function consumeEvents()
  local c = S.client
  for _, e in ipairs(c.eventQueue) do
    if e.kind == EV.SHOT then
      S.world:spawnMuzzle(e.x, e.y, 0, e.extra == 1)
      S.world.flash.angle = 0
      S.audio.play(e.extra == 1 and "fire_mg" or "fire", nil)
      -- volume by distance: clone pitch trick not needed; just play
    elseif e.kind == EV.HIT then
      if e.extra2 and e.extra2 > 0 then
        S.world:spawnHitFx(e.x, e.y, false)
        S.world:spawnDamageNumber(e.x, e.y, e.extra2)
        S.audio.play("hit", nil)
        if e.extra == (c.myId) and e.tankId ~= c.myId then
          S.hitMarker = 0.25
        end
      else
        S.world:spawnHitFx(e.x, e.y, true)
      end
    elseif e.kind == EV.RICOCHET then
      S.world:spawnHitFx(e.x, e.y, true)
      S.audio.play("ricochet", nil)
    elseif e.kind == EV.EXPLODE then
      S.world:spawnExplosion(e.x, e.y, 1.4)
      S.audio.play("explosion", nil)
    elseif e.kind == EV.KILL then
      local killer, victim = nameOf(e.tankId), nameOf(e.extra)
      if e.tankId == 0 then
        feed(victim .. " was destroyed", { 0.8, 0.8, 0.8 })
      else
        feed(killer .. "  >>  " .. victim, {
          (teamOf(e.tankId) == 1) and { 0.4, 0.7, 1 } or { 1, 0.5, 0.5 }
        })
      end
    elseif e.kind == EV.PICKUP then
      if e.extra2 and e.extra2 >= 1 then
        if e.tankId == 0 then
          -- powerup spawned; subtle
        else
          S.audio.play("pickup", nil)
          if e.tankId == c.myId then
            local key = POWER_KEYS[e.extra2] or "repair"
            S.client:toast("Picked up: " .. key:upper(), 2)
          end
        end
      end
    elseif e.kind == EV.FLAG_TAKEN then
      feed(nameOf(e.tankId) .. " took the flag!", { 1, 0.9, 0.3 })
    elseif e.kind == EV.FLAG_DROPPED then
      feed("Flag dropped", { 1, 0.9, 0.3 })
    elseif e.kind == EV.FLAG_CAPTURED then
      feed(nameOf(e.tankId) .. " CAPTURED the flag!", { 1, 0.85, 0.2 })
      S.audio.play("win", nil)
    elseif e.kind == EV.ZONE_CAPTURED then
      feed((e.extra == 1 and "BLUE" or "RED") .. " captured a zone", { 0.7, 0.9, 1 })
    elseif e.kind == EV.RESPAWN then
      S.world:spawnHitFx(e.x, e.y, true)
    end
  end
  c.eventQueue = {}
end

--=============================================================================
-- Update
--=============================================================================

function Battle.update(dt)
  Kit.newFrame()
  S.time = S.time + dt
  local c = S.client

  if S.paused then return end

  local input = buildInput()
  c:update(dt, input)
  consumeEvents()

  -- camera follows my tank
  local me = myTank()
  if me then
    if not S.camInit then
      S.camInit = true
      S.cam.x, S.cam.y = me.x, me.y
    end
    local lerp = 1 - math.pow(0.001, dt)
    S.cam.x = S.cam.x + (me.x - S.cam.x) * lerp
    S.cam.y = S.cam.y + (me.y - S.cam.y) * lerp
    -- hurt flash on hp drop
    if S.myLastHp and me.hp < S.myLastHp - 0.5 then
      S.hurtFlash = math.min(0.8, S.hurtFlash + 0.45)
    end
    S.myLastHp = me.hp
    -- respawn note
  end
  S.world:update(dt)
  S.hitMarker = math.max(0, S.hitMarker - dt)
  S.hurtFlash = math.max(0, S.hurtFlash - dt * 1.4)

  for i = #S.killfeed, 1, -1 do
    S.killfeed[i].t = S.killfeed[i].t - dt
    if S.killfeed[i].t <= 0 then table.remove(S.killfeed, i) end
  end
end

--=============================================================================
-- Drawing
--=============================================================================

local function drawWorldLayer()
  local c = S.client
  local map = Maps.get(c.match and c.match.mapId or "outpost")
  local tanks, bullets, modeState = c:renderState()

  S.world:applyCamera(S.cam, W(), H())
  S.world:drawMap(map)

  -- objectives (local sim objects preferred; online uses mode state + map data)
  local sim = c.localSim
  if sim then
    S.world:drawZones(sim)
    S.world:drawFlags(sim)
    S.world:drawPowerups(sim)
  else
    -- draw zones from map + modeState owners
    if modeState and modeState.zones and #modeState.zones > 0 and map.points then
      local fake = { zones = {} }
      for i, z in ipairs(modeState.zones) do
        local pt = map.points[i]
        if pt then fake.zones[#fake.zones + 1] = { x = pt[1], y = pt[2], r = 110, owner = z.owner } end
      end
      S.world:drawZones(fake)
    end
    -- powerups from map pads (visual only online; active state unknown)
    -- draw pads faintly
    gfx.setColor(1, 1, 1, 0.07)
    for _, pt in ipairs(map.powerups or {}) do
      gfx.circle("fill", pt[1], pt[2], 22)
    end
  end

  -- tanks
  local metaById = c.match and c.match.players or {}
  for _, t in ipairs(tanks) do
    local alive = bit32 and bit32.band(t.flags or 0, 1) ~= 0 or (t.hp or 0) > 0
    if alive then
      local meta = metaById[t.id] or {}
      local camoSel = { [meta.tankId or "scout"] = meta.camoId or "none" }
      local team = meta.team
      local nameColor = (t.id == c.myId) and { 0.5, 1, 0.6 }
        or (team == 1 and { 0.55, 0.75, 1 } or (team == 2 and { 1, 0.6, 0.6 } or { 0.85, 0.87, 0.9 }))
      S.world:drawTank(t, {
        tankId = meta.tankId or "scout",
        camoSel = camoSel,
        team = team,
        name = meta.name,
        nameColor = nameColor,
      })
    end
  end

  S.world:drawBullets(bullets)
  S.world:drawParticles()
  S.world:drawFloaters()
  S.world:popCamera()

  return tanks, modeState
end

local function fmtTime(t)
  local m = math.floor(t / 60)
  local s = math.floor(t % 60)
  return string.format("%d:%02d", m, s)
end

local function drawHUD(tanks, modeState)
  local c = S.client
  local w, h = W(), H()
  local mode = Modes.get(c.match and c.match.modeId or "dm")

  -- top center: score + clock
  if modeState then
    local mx = w / 2 - 130
    Kit.panel(mx, 12, 260, 46)
    Kit._font(18)
    if mode.teams then
      gfx.setColor(0.4, 0.65, 1)
      gfx.printf(tostring(modeState.scoreA), mx, 22, 70, "center")
      gfx.setColor(1, 0.45, 0.45)
      gfx.printf(tostring(modeState.scoreB), mx + 190, 22, 70, "center")
      gfx.setColor(0.9, 0.92, 0.95)
      gfx.printf("/" .. mode.scoreLabel, mx, 22, 260, "center")
      gfx.setColor(1, 1, 1, 0.25)
      gfx.printf("/", mx + 95, 22, 70, "center")
    else
      -- FFA: my kills
      local me = myTank()
      gfx.setColor(0.5, 1, 0.6)
      gfx.printf(tostring(me and me.kills or 0), mx, 22, 70, "center")
      gfx.setColor(0.7, 0.73, 0.78)
      gfx.printf("KILLS / " .. mode.scoreLimit, mx + 65, 22, 190, "left")
    end
    Kit._font(15)
    gfx.setColor(0.85, 0.88, 0.92)
    gfx.printf(fmtTime(modeState.timeLeft or 0), mx, 40, 260, "center")
  end

  -- bottom left: my vitals
  local me = myTank()
  local bw = 240
  local bx, by = 24, h - 86
  Kit.panel(bx, by, bw, 62)
  if me then
    local hpFrac = me.maxHp and me.maxHp > 0 and me.hp / me.maxHp or 0
    Kit.text("HP", bx + 12, by + 10, 13, { 0.7, 0.74, 0.8 })
    Kit.bar(bx + 36, by + 12, bw - 48, 12, hpFrac,
      hpFrac > 0.55 and { 0.3, 0.8, 0.35 } or (hpFrac > 0.25 and { 0.95, 0.75, 0.2 } or { 0.95, 0.3, 0.25 }))
    Kit.text(math.floor(me.hp + 0.5) .. "/" .. math.floor((me.maxHp or 100) + 0.5),
      bx + 36, by + 14, 11, { 0, 0, 0, 0.9 })
    -- reload
    Kit.text("RELOAD", bx + 12, by + 32, 13, { 0.7, 0.74, 0.8 })
    Kit.bar(bx + 36, by + 34, bw - 48, 10, me.reload or 0, { 0.45, 0.7, 0.95 })
    -- powerup timers (local sim has them; online via flags bits)
    local px = bx + 12
    local fx = { shield = 8, rapid = 16, damage = 32, speed = 64 }
    for name, bitv in pairs(fx) do
      local active = bit32 and bit32.band(me.flags or 0, bitv) ~= 0
      if active then
        gfx.setColor(1, 0.85, 0.3, 0.9)
        gfx.circle("fill", px, by + 54, 4)
        Kit.text(name:upper(), px + 8, by + 48, 11, { 1, 0.85, 0.3 })
        px = px + 74
      end
    end
    -- dead overlay note
    local alive = bit32 and bit32.band(me.flags or 0, 1) ~= 0
    if not alive then
      Kit.text("DESTROYED - respawning...", w / 2 - 110, h / 2 + 60, 18, { 1, 0.5, 0.4 })
      if c.localSim and c.localSim.tanksById[1] then
        Kit.text(string.format("%.1fs", math.max(0, c.localSim.tanksById[1].respawnTimer)),
          w / 2 - 8, h / 2 + 82, 14, { 1, 0.7, 0.6 })
      end
    end
  end

  -- minimap bottom right
  local map = Maps.get(c.match and c.match.mapId or "outpost")
  local mw, mh = 190, math.floor(190 * map.h / map.w)
  local modeExtras = { zones = modeState and modeState.zones or nil, meta = c.match and c.match.players or nil }
  -- flags for minimap
  if mode.id == "ctf" then
    local flags = {}
    if c.localSim then
      flags = c.localSim.flags
    else
      local function flagPos(side, carrierVal)
        local home = map.flags[side]
        if carrierVal == 0 then return { x = home[1], y = home[2] }
        elseif carrierVal == 65535 then return nil
        else
          local carrier
          for _, t in ipairs(tanks) do if t.id == carrierVal then carrier = t end end
          if carrier then return { x = carrier.x, y = carrier.y } end
        end
      end
      local fa = modeState and flagPos("a", modeState.flagA or 0)
      local fb = modeState and flagPos("b", modeState.flagB or 0)
      if fa then flags.a = fa end
      if fb then flags.b = fb end
    end
    modeExtras.flags = flags
  end
  S.world:drawMinimap(w - mw - 20, h - mh - 20, mw, mh, map, tanks, c.myId, modeExtras)

  -- killfeed top right
  local ky = 64
  Kit._font(13)
  for i = #S.killfeed, 1, -1 do
    local kf = S.killfeed[i]
    local a = math.min(1, kf.t / 1.2)
    gfx.setColor(kf.color[1], kf.color[2], kf.color[3], a)
    local tw = Kit._font(13):getWidth(kf.text)
    gfx.print(kf.text, w - tw - 30, ky)
    ky = ky + 20
  end

  -- crosshair at mouse
  local mx2, my2 = love.mouse.getPosition()
  gfx.setColor(1, 1, 1, 0.85)
  gfx.setLineWidth(1.5)
  gfx.circle("line", mx2, my2, 9)
  gfx.line(mx2 - 14, my2, mx2 - 5, my2)
  gfx.line(mx2 + 5, my2, mx2 + 14, my2)
  gfx.line(mx2, my2 - 14, mx2, my2 - 5)
  gfx.line(mx2, my2 + 5, mx2, my2 + 14)
  gfx.setLineWidth(1)
  if S.hitMarker > 0 then
    gfx.setColor(1, 0.35, 0.3, S.hitMarker * 4)
    gfx.line(mx2 - 6, my2 - 6, mx2 - 2, my2 - 2)
    gfx.line(mx2 + 6, my2 - 6, mx2 + 2, my2 - 2)
    gfx.line(mx2 - 6, my2 + 6, mx2 - 2, my2 + 2)
    gfx.line(mx2 + 6, my2 + 6, mx2 + 2, my2 + 2)
  end

  -- hurt vignette
  if S.hurtFlash > 0 then
    gfx.setColor(1, 0.1, 0.1, S.hurtFlash * 0.25)
    gfx.rectangle("fill", 0, 0, w, h)
  end

  -- hint bar
  Kit.text("WASD drive   Mouse aim+fire   TAB score   ENTER chat   ESC menu",
    24, h - 18, 12, { 1, 1, 1, 0.35 })

  -- ping (online)
  if not c.localSim and c.status == "connected" then
    Kit.text("ping " .. c.ping .. "ms", w - 90, 20, 12, { 1, 1, 1, 0.4 })
  end

  -- chat log + input (online rooms)
  if c.room or not c.localSim then
    local cy = h - 190
    Kit.beginClip(20, cy - 130, 380, 130)
    local startIdx = math.max(1, #c.chatLog - 6)
    for i = startIdx, #c.chatLog do
      local msg = c.chatLog[i]
      local col = msg.system and { 1, 0.8, 0.3 } or { 0.85, 0.9, 0.95 }
      gfx.setColor(col[1], col[2], col[3], 0.85)
      gfx.print(msg.name .. ": " .. msg.text, 24, cy - 130 + (i - startIdx) * 18)
    end
    Kit.endClip()
    if S.chatOpen then
      Kit.textInput("bchat", 20, h - 46, 360, 26, S.chatText, "say something...")
      Kit.text("ENTER send / ESC cancel", 390, h - 40, 11, { 1, 1, 1, 0.4 })
    end
  end

  -- toast
  if c.toast then
    Kit._font(15)
    local tw = Kit._font(15):getWidth(c.toast.text)
    Kit.panel(w / 2 - tw / 2 - 14, 84, tw + 28, 30, { 0.1, 0.12, 0.16, 0.9 })
    gfx.setColor(0.95, 0.9, 0.6)
    gfx.printf(c.toast.text, w / 2 - tw / 2, 92, tw + 28, "center")
  end

  -- fps
  if S.shared.settings.data.show_fps then
    Kit.text(tostring(math.floor(1 / math.max(0.0001, love.timer.getDelta()))) .. " fps", 10, 8, 12, { 0.5, 1, 0.5, 0.6 })
  end
end

local function drawScoreboard(tanks)
  local c = S.client
  local w, h = W(), H()
  local sw, sh = 460, 320
  local sx, sy = w / 2 - sw / 2, h / 2 - sh / 2
  Kit.panel(sx, sy, sw, sh)
  Kit.text("SCOREBOARD", sx + 16, sy + 12, 18, { 0.9, 0.93, 0.97 })
  local mode = Modes.get(c.match and c.match.modeId or "dm")

  -- header
  Kit.text("PLAYER", sx + 20, sy + 44, 12, { 0.6, 0.64, 0.7 })
  Kit.text("K", sx + 280, sy + 44, 12, { 0.6, 0.64, 0.7 })
  Kit.text("D", sx + 320, sy + 44, 12, { 0.6, 0.64, 0.7 })
  Kit.text("TEAM", sx + 360, sy + 44, 12, { 0.6, 0.64, 0.7 })

  local rows = {}
  for _, t in ipairs(tanks) do
    local meta = (c.match and c.match.players[t.id]) or {}
    rows[#rows + 1] = {
      name = meta.name or "?", kills = t.kills or 0, deaths = t.deaths or 0,
      team = meta.team, me = (t.id == c.myId), bot = meta.isBot,
    }
  end
  table.sort(rows, function(a, b) return a.kills > b.kills end)
  local y = sy + 66
  for i, r in ipairs(rows) do
    if i > 10 then break end
    if r.me then
      gfx.setColor(0.3, 0.6, 0.9, 0.18)
      gfx.rectangle("fill", sx + 12, y - 4, sw - 24, 22, 4)
    end
    local nameCol = r.me and { 0.5, 1, 0.6 } or (r.team == 1 and { 0.55, 0.75, 1 } or (r.team == 2 and { 1, 0.6, 0.6 } or { 0.9, 0.9, 0.9 }))
    Kit.text((r.bot and "[BOT] " or "") .. r.name, sx + 20, y, 13, nameCol)
    Kit.text(tostring(r.kills), sx + 280, y, 13)
    Kit.text(tostring(r.deaths), sx + 320, y, 13)
    Kit.text(r.team == 1 and "BLUE" or (r.team == 2 and "RED" or "-"), sx + 360, y, 13,
      r.team == 1 and { 0.55, 0.75, 1 } or (r.team == 2 and { 1, 0.6, 0.6 } or { 0.7, 0.7, 0.7 }))
    y = y + 24
  end
end

local function drawResults()
  local c = S.client
  local res = c.results
  if not res then return end
  local w, h = W(), H()
  gfx.setColor(0, 0, 0, 0.55)
  gfx.rectangle("fill", 0, 0, w, h)

  local sw, sh = 520, 420
  local sx, sy = w / 2 - sw / 2, h / 2 - sh / 2
  Kit.panel(sx, sy, sw, sh)

  local mode = Modes.get(c.match and c.match.modeId or "dm")
  local myRow
  for _, r in ipairs(res.scoreboard) do
    if r.id == (c.localSim and 1 or c.myId) then myRow = r end
  end
  local won
  if mode.teams and myRow then
    local myTeam = c.match.players[myRow.id] and c.match.players[myRow.id].team
    won = res.winner ~= 0 and myTeam == res.winner
  elseif myRow then
    won = res.winner == myRow.id
  end

  Kit._font(28)
  gfx.setColor(won and { 0.4, 0.95, 0.5 } or { 1, 0.45, 0.4 })
  gfx.printf(won and "VICTORY" or "DEFEAT", sx, sy + 20, sw, "center")

  -- scoreboard
  local y = sy + 72
  Kit.text("PLAYER", sx + 24, y, 12, { 0.6, 0.64, 0.7 })
  Kit.text("K", sx + 300, y, 12, { 0.6, 0.64, 0.7 })
  Kit.text("D", sx + 340, y, 12, { 0.6, 0.64, 0.7 })
  Kit.text("SCORE", sx + 390, y, 12, { 0.6, 0.64, 0.7 })
  y = y + 22
  for i, r in ipairs(res.scoreboard) do
    if i > 9 then break end
    local isMe = r.id == (c.localSim and 1 or c.myId)
    if isMe then
      gfx.setColor(0.3, 0.6, 0.9, 0.2)
      gfx.rectangle("fill", sx + 14, y - 4, sw - 28, 22, 4)
    end
    Kit.text(r.name, sx + 24, y, 13, isMe and { 0.5, 1, 0.6 } or { 0.88, 0.9, 0.93 })
    Kit.text(tostring(r.kills), sx + 300, y, 13)
    Kit.text(tostring(r.deaths), sx + 340, y, 13)
    Kit.text(tostring(r.score), sx + 390, y, 13)
    y = y + 22
  end

  -- rewards
  if myRow then
    y = y + 12
    Kit.text(string.format("REWARDS   +%d XP    +%d CR", myRow.xp or 0, myRow.credits or 0),
      sx + 24, y, 15, { 1, 0.85, 0.35 })
    y = y + 26
    Kit.text("Credits: " .. S.shared.save.data.credits .. "    Level: " .. S.shared.save.data.level,
      sx + 24, y, 13, { 0.7, 0.74, 0.8 })
  end

  -- buttons
  local byy = sy + sh - 52
  if c.localSim then
    if Kit.button("again", "PLAY AGAIN", sx + 24, byy, 150, 34) then
      States.switch("battle", { mode = "solo", config = S.opts.config })
    end
    if Kit.button("tomenu", "MAIN MENU", sx + 190, byy, 150, 34) then
      States.switch("menu.main")
    end
  else
    if Kit.button("tolobby", "BACK TO LOBBY", sx + 24, byy, 170, 34) then
      States.switch("menu.room")
    end
    if Kit.button("tomenu", "DISCONNECT", sx + 210, byy, 150, 34) then
      S.client:disconnect()
      States.switch("menu.main")
    end
  end
end

local function drawPause()
  local w, h = W(), H()
  gfx.setColor(0, 0, 0, 0.6)
  gfx.rectangle("fill", 0, 0, w, h)
  local pw, ph = 300, 240
  local px, py = w / 2 - pw / 2, h / 2 - ph / 2
  Kit.panel(px, py, pw, ph)
  Kit.text("PAUSED", px, py + 20, 24, { 0.95, 0.95, 0.97 }, "center", pw)
  if Kit.button("resume", "RESUME", px + 40, py + 70, pw - 80, 36) then
    S.paused = false
  end
  if Kit.button("settings", "SETTINGS", px + 40, py + 116, pw - 80, 36) then
    States.push("menu.settings", { fromPause = true })
  end
  local leaveLabel = S.client.localSim and "QUIT TO MENU" or "LEAVE TO LOBBY"
  if Kit.button("leave", leaveLabel, px + 40, py + 162, pw - 80, 36) then
    if S.client.localSim then
      States.switch("menu.main")
    else
      States.switch("menu.room")
    end
  end
end

function Battle.draw()
  local w, h = W(), H()
  gfx.clear(0.05, 0.06, 0.08)
  if not S.client.match then
    Kit.text("Waiting for match data...", w / 2 - 90, h / 2, 16)
    return
  end
  local tanks, modeState = drawWorldLayer()
  drawHUD(tanks, modeState)
  if S.showScore then
    drawScoreboard(tanks)
  end
  if S.client.results then
    drawResults()
  elseif S.paused then
    drawPause()
  end
end

--=============================================================================
-- Input events
--=============================================================================

function Battle.keypressed(key)
  if S.client.results then return end
  if key == "escape" then
    if S.chatOpen then
      S.chatOpen = false
      S.chatText = ""
    else
      S.paused = not S.paused
    end
  elseif key == "tab" then
    S.showScore = true
  elseif key == "return" or key == "kpenter" then
    if not S.paused then
      S.chatOpen = not S.chatOpen
      if not S.chatOpen and S.chatText ~= "" then
        S.client:sendChat(S.chatText)
        S.chatText = ""
      elseif not S.chatOpen then
        S.chatText = ""
      end
    end
  elseif S.chatOpen then
    if key == "backspace" then
      S.chatText = S.chatText:sub(1, -2)
    end
  end
end

function Battle.keyreleased(key)
  if key == "tab" then S.showScore = false end
end

function Battle.textinput(text)
  if S.chatOpen and #S.chatText < 110 then
    S.chatText = S.chatText .. text
  end
end

function Battle.mousepressed(x, y, button)
  Kit.mousepressed(x, y, button)
end

function Battle.mousereleased(x, y, button)
  Kit.mousereleased(x, y, button)
end

function Battle.mousemoved(x, y)
  Kit.mousemoved(x, y)
end

function Battle.resize()
end

return Battle
