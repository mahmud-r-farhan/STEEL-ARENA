--=============================================================================
-- Authoritative battle simulation: physics, combat, powerups, win conditions.
-- Runs on the server; also runs locally for instant solo/offline play.
-- No LÖVE dependencies: pure Lua, deterministic-ish with injected RNG.
--=============================================================================

local Protocol = require("net.protocol")
local Tanks    = require("data.tanks")
local Maps     = require("data.maps")
local Modes    = require("data.modes")

local Sim = {}
Sim.__index = Sim

-- constants -------------------------------------------------------------
Sim.TICK_RATE      = 30
Sim.TANK_ACCEL     = 900      -- px/s^2
Sim.TANK_FRICTION  = 700
Sim.BULLET_LIFE    = 1.6
Sim.BULLET_RADIUS  = 3
Sim.MG_SPREAD      = 0.045
Sim.CANNON_SPREAD  = 0.012
Sim.RESPAWN_TIME   = 3.0
Sim.RESPAWN_INVULN = 2.0
Sim.TANK_DMG_MULT  = 1.0      -- vs tanks
Sim.SELF_DMG_MULT  = 0.4
Sim.POWERUP_TIME   = 25.0
Sim.OVERHEAT_MG    = 14       -- consecutive MG rounds before cooldown lock
Sim.COOL_PER_SEC   = 9

-- powerup kinds
Sim.POWERUPS = {
  repair   = { name = "Repair Kit",  color = {0.2,0.9,0.3}, apply = "repair" },
  shield   = { name = "Shield Cell", color = {0.3,0.6,1.0}, apply = "shield" },
  rapid    = { name = "Rapid Fire",  color = {1.0,0.8,0.2}, apply = "rapid" },
  damage   = { name = "HE Shells",   color = {1.0,0.3,0.2}, apply = "damage" },
  speed    = { name = "Nitro",       color = {0.9,0.4,1.0}, apply = "speed" },
}
Sim.POWERUP_KEYS = { "repair", "shield", "rapid", "damage", "speed" }

local TAU = math.pi * 2

local function angDiff(a, b)
  local d = (b - a) % TAU
  if d > math.pi then d = d - TAU end
  return d
end

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

local function spawnPointsFor(map, teams)
  if teams then return map.spawnsA, map.spawnsB end
  return map.spawnsFfa, map.spawnsFfa
end

function Sim.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Sim)

  self.map      = Maps.get(opts.mapId or "outpost")
  self.mode     = Modes.get(opts.modeId or "dm")
  self.seed     = opts.seed or os.time()
  self.rng      = opts.rng or self:makeRng(self.seed)
  self.difficulty = opts.difficulty or 1
  self.onEvent  = opts.onEvent or function() end
  self.isLocal  = opts.isLocal or false

  self.tanksById  = {}
  self.bullets    = {}
  self.nextBullet = 1
  self.powerups   = {}          -- live pickups {x,y,kind,respawn}
  self.tick       = 0
  self.timeLeft   = self.mode.timeLimit
  self.over       = false
  self.winner     = 0
  self.scoreA     = 0
  self.scoreB     = 0
  self.events     = {}          -- consumed per snapshot

  -- control-point state
  self.zones = {}
  for i, pt in ipairs(self.map.points or {}) do
    self.zones[i] = { x = pt[1], y = pt[2], r = 110, owner = 0, progress = 0 }
  end

  -- flags (ctf)
  self.flags = {}
  if self.mode.id == "ctf" then
    self.flags.a = { home = self.map.flags.a, x = self.map.flags.a[1], y = self.map.flags.a[2], carrier = 0, atBase = true }
    self.flags.b = { home = self.map.flags.b, x = self.map.flags.b[1], y = self.map.flags.b[2], carrier = 0, atBase = true }
  end

  -- spawn powerups
  for _, pt in ipairs(self.map.powerups or {}) do
    self.powerups[#self.powerups + 1] = {
      x = pt[1], y = pt[2], kind = nil, respawn = 0,
      active = false, cycle = self.rng:next(1, #Sim.POWERUP_KEYS),
    }
  end

  return self
end

-- tiny deterministic LCG rng (so server/client can share seed)
function Sim:makeRng(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  local rng = {}
  function rng:next(lo, hi)
    s = (s * 16807) % 2147483647
    local v = (s % 10000) / 10000
    if lo then return lo + math.floor(v * (hi - lo + 1)) end
    return v
  end
  return rng
end

--=============================================================================
-- Tank management
--=============================================================================

function Sim:addTank(player)
  -- player: {id, name, tankId, camoId, upgrades{5}, team, isBot}
  local stats = Tanks.statsFor(player.tankId, player.upgrades)
  local spawnsA, spawnsB = spawnPointsFor(self.map, self.mode.teams)
  local list = (player.team == 2) and spawnsB or spawnsA
  local idx = (#self.tanksById % #list) + 1
  local sp = list[idx]

  local t = {
    id = player.id, name = player.name,
    tankId = stats.id, stats = stats,
    x = sp[1], y = sp[2],
    vx = 0, vy = 0,
    hull = (player.team == 2) and math.pi or 0,
    turret = (player.team == 2) and math.pi or 0,
    hp = stats.hp, maxHp = stats.hp,
    reloadLeft = 0,
    alive = true,
    respawnTimer = 0,
    invuln = Sim.RESPAWN_INVULN,
    team = player.team or 1,
    isBot = player.isBot or false,
    kills = 0, deaths = 0, score = 0, damageDealt = 0,
    fireHeld = false,
    mgBurst = 0, heat = 0,
    -- powerup effects
    fxShield = 0, fxRapid = 0, fxDamage = 0, fxSpeed = 0,
    input = { move = 0, turn = 0, turret = 0, fire = false },
    lastInputSeq = 0,
    hasFlag = false,
  }
  self.tanksById[t.id] = t
  return t
end

function Sim:removeTank(id)
  self.tanksById[id] = nil
end

function Sim:tankList()
  local list = {}
  for _, t in pairs(self.tanksById) do list[#list + 1] = t end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

--=============================================================================
-- Collision helpers
--=============================================================================

function Sim:resolveWallCircle(x, y, r)
  local hit = false
  for _, w in ipairs(self.map.walls) do
    local cx = clamp(x, w.x, w.x + w.w)
    local cy = clamp(y, w.y, w.y + w.h)
    local dx, dy = x - cx, y - cy
    local d2 = dx * dx + dy * dy
    if d2 < r * r then
      hit = true
      local d = math.sqrt(d2)
      if d < 0.001 then
        -- center inside wall: push out along smallest axis
        local left, right = x - w.x, w.x + w.w - x
        local top, bot = y - w.y, w.y + w.h - y
        local m = math.min(left, right, top, bot)
        if m == left then x = w.x - r
        elseif m == right then x = w.x + w.w + r
        elseif m == top then y = w.y - r
        else y = w.y + w.h + r end
      else
        local push = (r - d) / d
        x = x + dx * push
        y = y + dy * push
      end
    end
  end
  return x, y, hit
end

-- raycast vs walls; returns hit point or nil
function Sim:raycastWalls(x0, y0, dx, dy, maxDist)
  local STEP = 12
  local n = math.floor(maxDist / STEP)
  for i = 1, n do
    local x = x0 + dx * i * STEP
    local y = y0 + dy * i * STEP
    if Maps.solidAt(self.map, x, y, 0) then
      return x, y
    end
  end
  return nil
end

function Sim:tankAt(x, y, r, excludeId)
  for _, t in pairs(self.tanksById) do
    if t.id ~= excludeId and t.alive then
      local dx, dy = x - t.x, y - t.y
      if dx * dx + dy * dy < (r + t.stats.radius) ^ 2 then
        return t
      end
    end
  end
end

--=============================================================================
-- Input + combat
--=============================================================================

function Sim:setInput(id, input, seq)
  local t = self.tanksById[id]
  if not t or not t.alive then return end
  t.input.move   = clamp(math.floor(input.move or 0), -1, 1)
  t.input.turn   = clamp(math.floor(input.turn or 0), -1, 1)
  t.input.turret = (input.turret or 0) % TAU
  t.input.fire   = input.fire and true or false
  if seq then t.lastInputSeq = seq end
end

local function effectiveStats(t)
  local s = {
    speed = t.stats.speed * (t.fxSpeed > 0 and 1.45 or 1),
    reload = t.stats.reload * (t.fxRapid > 0 and 0.55 or 1),
    damage = t.stats.damage * (t.fxDamage > 0 and 1.5 or 1),
    bulletSpeed = t.stats.bulletSpeed,
    turret = t.stats.turret,
    fireMode = t.stats.fireMode,
    radius = t.stats.radius,
  }
  return s
end

function Sim:tryFire(t)
  local s = effectiveStats(t)
  if t.reloadLeft > 0 then return end
  if s.fireMode == "mg" then
    if t.heat >= Sim.OVERHEAT_MG then return end
  end
  t.reloadLeft = s.reload
  t.fireHeld = true

  local spread = (s.fireMode == "mg") and Sim.MG_SPREAD or Sim.CANNON_SPREAD
  local a = t.turret + (self.rng:next() * 2 - 1) * spread
  local muzzle = s.radius + 10
  local bx = t.x + math.cos(t.turret) * muzzle
  local by = t.y + math.sin(t.turret) * muzzle

  -- don't fire if muzzle inside a wall
  local wx, wy = self:raycastWalls(t.x, t.y, math.cos(a), math.sin(a), muzzle)
  if wx then
    bx, by = t.x, t.y
  end

  self.bullets[#self.bullets + 1] = {
    id = self.nextBullet, owner = t.id, team = t.team,
    x = bx, y = by,
    dx = math.cos(a), dy = math.sin(a),
    speed = s.bulletSpeed,
    damage = s.damage,
    life = Sim.BULLET_LIFE,
    kind = (s.fireMode == "mg") and 1 or 0,
  }
  self.nextBullet = (self.nextBullet % 60000) + 1

  if s.fireMode == "mg" then
    t.mgBurst = t.mgBurst + 1
    t.heat = t.heat + 1
  else
    t.mgBurst = 0
  end

  -- light recoil
  t.vx = t.vx - math.cos(a) * 30
  t.vy = t.vy - math.sin(a) * 30

  self:onEvent({ kind = Protocol.EV.SHOT, tankId = t.id, x = bx, y = by,
    extra = (s.fireMode == "mg") and 1 or 0 })
end

function Sim:damage(target, amount, attackerId, hx, hy)
  if not target.alive or target.invuln > 0 then
    self:onEvent({ kind = Protocol.EV.RICOCHET, tankId = target.id, x = hx, y = hy })
    return
  end
  local dmg = amount
  if target.fxShield > 0 then dmg = dmg * 0.5 end
  target.hp = target.hp - dmg

  local attacker = self.tanksById[attackerId]
  if attacker and attacker.id ~= target.id then
    attacker.damageDealt = attacker.damageDealt + math.min(dmg, target.hp + dmg)
    attacker.score = attacker.score + math.floor(dmg / 10)
    self:onEvent({ kind = Protocol.EV.HIT, tankId = target.id, extra = attackerId,
      x = hx, y = hy, extra2 = math.floor(dmg) })
  end

  if target.hp <= 0 then
    self:killTank(target, attackerId)
  end
end

function Sim:killTank(target, killerId)
  target.alive = false
  target.hp = 0
  target.deaths = target.deaths + 1
  target.respawnTimer = Sim.RESPAWN_TIME
  target.hasFlag = false

  local killer = self.tanksById[killerId]
  if killer and killer.id ~= target.id then
    killer.kills = killer.kills + 1
    killer.score = killer.score + 100
    -- scoring for modes
    if self.mode.teams then
      if killer.team == 1 then self.scoreA = self.scoreA + 1
      else self.scoreB = self.scoreB + 1 end
    end
  elseif killer and killer.id == target.id then
    -- suicide: no credit, drop a team point in TDM
    if self.mode.teams then
      if target.team == 1 then self.scoreA = math.max(0, self.scoreA - 1)
      else self.scoreB = math.max(0, self.scoreB - 1) end
    end
  end

  self:onEvent({ kind = Protocol.EV.EXPLODE, tankId = target.id, x = target.x, y = target.y })
  self:onEvent({
    kind = Protocol.EV.KILL, tankId = killerId or 0, extra = target.id,
    x = target.x, y = target.y,
  })

  -- drop flag
  for _, f in pairs(self.flags) do
    if f.carrier == target.id then
      f.carrier = 0
      f.x, f.y = target.x, target.y
      self:onEvent({ kind = Protocol.EV.FLAG_DROPPED, tankId = target.id, x = f.x, y = f.y })
    end
  end
end

function Sim:respawn(t)
  local spawnsA, spawnsB = spawnPointsFor(self.map, self.mode.teams)
  local list = (t.team == 2) and spawnsB or spawnsA
  -- pick spawn farthest from living enemies
  local best, bestD = list[1], -1
  for _, sp in ipairs(list) do
    local d = math.huge
    for _, e in pairs(self.tanksById) do
      if e.alive and e.team ~= t.team then
        local dd = (e.x - sp[1]) ^ 2 + (e.y - sp[2]) ^ 2
        if dd < d then d = dd end
      end
    end
    if d > bestD then bestD = d; best = sp end
  end
  t.x, t.y = best[1], best[2]
  t.vx, t.vy = 0, 0
  t.hull = (t.team == 2) and math.pi or 0
  t.turret = t.hull
  t.hp = t.maxHp
  t.alive = true
  t.invuln = Sim.RESPAWN_INVULN
  t.reloadLeft = 0
  t.heat = 0
  t.fxShield, t.fxRapid, t.fxDamage, t.fxSpeed = 0, 0, 0, 0
  self:onEvent({ kind = Protocol.EV.RESPAWN, tankId = t.id, x = t.x, y = t.y })
end

--=============================================================================
-- Powerups
--=============================================================================

function Sim:updatePowerups(dt)
  for _, p in ipairs(self.powerups) do
    if p.active then
      for _, t in pairs(self.tanksById) do
        if t.alive and (t.x - p.x) ^ 2 + (t.y - p.y) ^ 2 < 34 * 34 then
          p.active = false
          p.respawn = 12 + self.rng:next(0, 6)
          p.kind = nil
          self:applyPowerup(t, p.cycle)
          p.cycle = (p.cycle % #Sim.POWERUP_KEYS) + 1
          break
        end
      end
    else
      p.respawn = p.respawn - dt
      if p.respawn <= 0 then
        p.active = true
        p.kind = Sim.POWERUP_KEYS[self.rng:next(1, #Sim.POWERUP_KEYS)]
        self:onEvent({ kind = Protocol.EV.PICKUP, tankId = 0, x = p.x, y = p.y, extra2 = 1 })
      end
    end
  end
end

function Sim:applyPowerup(t, kindIdx)
  local key = Sim.POWERUP_KEYS[kindIdx] or "repair"
  local pk = Sim.POWERUPS[key]
  if key == "repair" then
    t.hp = math.min(t.maxHp, t.hp + t.maxHp * 0.4)
  else
    t["fx" .. key:sub(1,1):upper() .. key:sub(2)] = Sim.POWERUP_TIME
  end
  self:onEvent({ kind = Protocol.EV.PICKUP, tankId = t.id, x = t.x, y = t.y,
    extra2 = kindIdx })
end

--=============================================================================
-- Zones (control mode)
--=============================================================================

function Sim:updateZones(dt)
  if self.mode.id ~= "control" then return end
  for _, z in ipairs(self.zones) do
    local a, b = 0, 0
    for _, t in pairs(self.tanksById) do
      if t.alive and (t.x - z.x) ^ 2 + (t.y - z.y) ^ 2 < z.r * z.r then
        if t.team == 1 then a = a + 1 else b = b + 1 end
      end
    end
    if a > b and b == 0 then
      if z.owner ~= 1 then
        z.progress = z.progress + dt
        if z.progress >= 3 then
          z.owner, z.progress = 1, 0
          self:onEvent({ kind = Protocol.EV.ZONE_CAPTURED, tankId = 0, x = z.x, y = z.y, extra = 1 })
        end
      end
    elseif b > a and a == 0 then
      if z.owner ~= 2 then
        z.progress = z.progress + dt
        if z.progress >= 3 then
          z.owner, z.progress = 2, 0
          self:onEvent({ kind = Protocol.EV.ZONE_CAPTURED, tankId = 0, x = z.x, y = z.y, extra = 2 })
        end
      end
    else
      z.progress = math.max(0, z.progress - dt)
    end
  end
  -- score tick
  self.zoneTick = (self.zoneTick or 0) + dt
  if self.zoneTick >= (self.mode.tickRate or 1) then
    self.zoneTick = self.zoneTick - (self.mode.tickRate or 1)
    for _, z in ipairs(self.zones) do
      if z.owner == 1 then self.scoreA = self.scoreA + (self.mode.pointsPerTick or 1) end
      if z.owner == 2 then self.scoreB = self.scoreB + (self.mode.pointsPerTick or 1) end
    end
  end
end

--=============================================================================
-- Flags (ctf)
--=============================================================================

function Sim:updateFlags(dt)
  if self.mode.id ~= "ctf" then return end
  for side, f in pairs(self.flags) do
    local enemyTeam = (side == "a") and 2 or 1
    if f.carrier == 0 then
      for _, t in pairs(self.tanksById) do
        if t.alive and t.team == enemyTeam and not t.hasFlag
           and (t.x - f.x) ^ 2 + (t.y - f.y) ^ 2 < 40 * 40 then
          f.carrier = t.id
          t.hasFlag = true
          self:onEvent({ kind = Protocol.EV.FLAG_TAKEN, tankId = t.id, x = f.x, y = f.y })
          break
        end
      end
    else        local carrier = self.tanksById[f.carrier]
        local ownFlag = self.flags[(side == "a") and "b" or "a"]
        local ownBase = (side == "a") and self.map.flags.a or self.map.flags.b
        if carrier and carrier.alive then
          f.x, f.y = carrier.x, carrier.y
          -- capture check: carrier of THIS flag enters their own base,
          -- and their own flag is at home
          if ownFlag and ownFlag.atBase then
            local base = (carrier.team == 1) and self.map.flags.a or self.map.flags.b
            if (carrier.x - base[1]) ^ 2 + (carrier.y - base[2]) ^ 2 < 70 * 70 then
              f.carrier = 0
              f.x, f.y = f.home[1], f.home[2]
              f.atBase = true
              carrier.hasFlag = false
              carrier.score = carrier.score + 300
              if carrier.team == 1 then self.scoreA = self.scoreA + 1
              else self.scoreB = self.scoreB + 1 end
              self:onEvent({ kind = Protocol.EV.FLAG_CAPTURED, tankId = carrier.id,
                x = base[1], y = base[2] })
            end
          end
        else
          f.carrier = 0   -- carrier died: flag stays where dropped
        end
    end
  end
end

--=============================================================================
-- Main step
--=============================================================================

function Sim:step(dt)
  dt = math.min(dt, 0.1)
  if self.over then return end
  self.tick = self.tick + 1
  self.timeLeft = math.max(0, self.timeLeft - dt)

  -- tanks
  for _, t in pairs(self.tanksById) do
    t.invuln = math.max(0, t.invuln - dt)
    t.fxShield = math.max(0, t.fxShield - dt)
    t.fxRapid  = math.max(0, t.fxRapid - dt)
    t.fxDamage = math.max(0, t.fxDamage - dt)
    t.fxSpeed  = math.max(0, t.fxSpeed - dt)

    if not t.alive then
      t.respawnTimer = t.respawnTimer - dt
      if t.respawnTimer <= 0 then self:respawn(t) end
    else
      local s = effectiveStats(t)
      -- hull movement
      local accel = (t.input.move or 0) * Sim.TANK_ACCEL
      t.vx = t.vx + math.cos(t.hull) * accel * dt
      t.vy = t.vy + math.sin(t.hull) * accel * dt
      -- friction
      local spd = math.sqrt(t.vx * t.vx + t.vy * t.vy)
      if spd > 0 then
        local drop = Sim.TANK_FRICTION * dt
        local ns = math.max(0, spd - drop)
        t.vx, t.vy = t.vx * ns / spd, t.vy * ns / spd
      end
      -- clamp speed
      spd = math.sqrt(t.vx * t.vx + t.vy * t.vy)
      if spd > s.speed then
        t.vx, t.vy = t.vx * s.speed / spd, t.vy * s.speed / spd
      end
      t.x = t.x + t.vx * dt
      t.y = t.y + t.vy * dt

      -- hull rotation
      t.hull = (t.hull + (t.input.turn or 0) * s.turret * 0.8 * dt) % TAU

      -- wall collision
      local nx, ny = self:resolveWallCircle(t.x, t.y, s.radius)
      if nx ~= t.x or ny ~= t.y then
        t.x, t.y = nx, ny
        t.vx, t.vy = t.vx * 0.5, t.vy * 0.5
      end

      -- turret tracking
      local want = t.input.turret or t.turret
      local d = angDiff(t.turret, want)
      local maxStep = s.turret * dt
      if math.abs(d) <= maxStep then t.turret = want % TAU
      else
        local sgn = (d > 0) and 1 or -1
        t.turret = (t.turret + sgn * maxStep) % TAU
      end

      -- reload
      t.reloadLeft = math.max(0, t.reloadLeft - dt)
      if t.stats.fireMode == "mg" then
        if not t.input.fire then
          t.heat = math.max(0, t.heat - Sim.COOL_PER_SEC * dt * 2)
          if t.heat < 4 then t.mgBurst = 0 end
        end
        if t.heat >= Sim.OVERHEAT_MG and t.reloadLeft <= 0 then
          t.reloadLeft = 1.2   -- overheat penalty
        end
      end
      if t.input.fire then self:tryFire(t) end
    end
  end

  -- tank/tank soft collision
  local list = self:tankList()
  for i = 1, #list do
    for j = i + 1, #list do
      local a, b = list[i], list[j]
      if a.alive and b.alive then
        local dx, dy = b.x - a.x, b.y - a.y
        local rr = a.stats.radius + b.stats.radius
        local d2 = dx * dx + dy * dy
        if d2 < rr * rr and d2 > 0.0001 then
          local d = math.sqrt(d2)
          local push = (rr - d) / d * 0.5
          a.x, a.y = a.x - dx * push, a.y - dy * push
          b.x, b.y = b.x + dx * push, b.y + dy * push
        end
      end
    end
  end

  -- bullets
  for i = #self.bullets, 1, -1 do
    local b = self.bullets[i]
    b.life = b.life - dt
    local dist = b.speed * dt
    local steps = math.max(1, math.ceil(dist / 10))
    local dead = b.life <= 0
    local stepLen = dist / steps
    for sIdx = 1, steps do
      b.x = b.x + b.dx * stepLen
      b.y = b.y + b.dy * stepLen
      -- walls
      if Maps.solidAt(self.map, b.x, b.y, 0) then
        dead = true
        self:onEvent({ kind = Protocol.EV.HIT, tankId = 0, x = b.x, y = b.y, extra2 = 0 })
        break
      end
      -- tanks
      local hit = self:tankAt(b.x, b.y, Sim.BULLET_RADIUS, b.owner)
      if hit then
        dead = true
        self:damage(hit, b.damage, b.owner, b.x, b.y)
        break
      end
    end
    if dead then
      self.bullets[i] = self.bullets[#self.bullets]
      self.bullets[#self.bullets] = nil
    end
  end

  -- enemy flag returning to base when dropped (slow auto-return)
  if self.mode.id == "ctf" then
    for _, f in pairs(self.flags) do
      if f.carrier == 0 and not f.atBase then
        f.returnTimer = (f.returnTimer or 10) - dt
        if f.returnTimer <= 0 then
          f.x, f.y = f.home[1], f.home[2]
          f.atBase = true
          f.returnTimer = nil
          self:onEvent({ kind = Protocol.EV.FLAG_RETURNED, tankId = 0, x = f.x, y = f.y })
        end
      elseif f.atBase then
        f.returnTimer = nil
      end
    end
  end

  self:updatePowerups(dt)
  self:updateZones(dt)
  self:updateFlags(dt)

  -- win conditions
  self:checkWin()
end

function Sim:checkWin()
  local m = self.mode
  local limit = m.scoreLimit
  if m.teams then
    if self.scoreA >= limit or self.scoreB >= limit then
      self.over = true
      self.winner = self.scoreA >= limit and 1 or (self.scoreB >= limit and 2 or 0)
    end
  else
    -- FFA: highest kills
    for _, t in pairs(self.tanksById) do
      if t.kills >= limit then self.over = true; self.winner = t.id; return end
    end
  end
  if self.timeLeft <= 0 then
    self.over = true
    if m.teams then
      self.winner = (self.scoreA > self.scoreB) and 1 or ((self.scoreB > self.scoreA) and 2 or 0)
    else
      local best, bk = 0, 0
      for _, t in pairs(self.tanksById) do
        if t.kills > bk then bk = t.kills; best = t.id end
      end
      self.winner = best
    end
  end
end

-- scoreboard rows sorted
function Sim:scoreboard()
  local rows = {}
  for _, t in pairs(self.tanksById) do
    rows[#rows + 1] = {
      id = t.id, name = t.name, kills = t.kills, deaths = t.deaths,
      score = t.score + t.kills * 100, team = t.team, isBot = t.isBot,
      damage = math.floor(t.damageDealt),
    }
  end
  table.sort(rows, function(a, b)
    if a.kills ~= b.kills then return a.kills > b.kills end
    return a.deaths < b.deaths
  end)
  return rows
end

--=============================================================================
-- Snapshot building
--=============================================================================

function Sim:snapshot()
  local tanks = {}
  for _, t in pairs(self.tanksById) do
    local flags = 0
    if t.alive then flags = flags + 1 end
    if t.hasFlag then flags = flags + 2 end
    if t.invuln > 0 then flags = flags + 4 end
    if t.fxShield > 0 then flags = flags + 8 end
    if t.fxRapid > 0 then flags = flags + 16 end
    if t.fxDamage > 0 then flags = flags + 32 end
    if t.fxSpeed > 0 then flags = flags + 64 end
    tanks[#tanks + 1] = {
      id = t.id, x = t.x, y = t.y, hull = t.hull, turret = t.turret,
      hp = math.max(0, math.floor(t.hp)),
      reload = (t.stats.reload > 0) and (1 - t.reloadLeft / (t.stats.reload * (t.fxRapid > 0 and 0.55 or 1))) or 1,
      flags = flags,
    }
  end
  local bullets = {}
  for _, b in ipairs(self.bullets) do
    bullets[#bullets + 1] = { id = b.id, x = b.x, y = b.y, angle = atan2(b.dy, b.dx), kind = b.kind }
  end
  local events = self.events
  self.events = {}

  local zones = {}
  for _, z in ipairs(self.zones) do zones[#zones + 1] = { owner = z.owner } end

  return {
    tick = self.tick % 65536,
    tanks = tanks,
    bullets = bullets,
    events = events,
    mode = {
      scoreA = self.scoreA, scoreB = self.scoreB,
      timeLeft = math.floor(self.timeLeft),
      zones = zones,
      flagA = self.flags.a and (self.flags.a.carrier == 0 and (self.flags.a.atBase and 0 or 65535) or self.flags.a.carrier) or 0,
      flagB = self.flags.b and (self.flags.b.carrier == 0 and (self.flags.b.atBase and 0 or 65535) or self.flags.b.carrier) or 0,
    },
  }
end

return Sim
