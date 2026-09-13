--=============================================================================
-- Bot AI: difficulty-graded tank brains.
-- Behaviors: SEEK -> ENGAGE -> STRAFE/FLANK -> RETREAT, plus CTF flag runs,
-- control-zone holding, powerup grabbing, shot leading and dodging.
-- Pure functions of (sim, dt) so it runs identically on server or local.
--=============================================================================

local Maps  = require("data.maps")
local Modes = require("data.modes")

local Bot = {
  -- difficulty profiles: 1 easy, 2 normal, 3 hard, 4 veteran
  profiles = {
    [1] = { aimError = 0.22, lead = 0.3, reactMin = 0.45, reactMax = 0.9,
            fov = math.rad(120), aggression = 0.4, dodge = 0.15, name = "Rookie" },
    [2] = { aimError = 0.11, lead = 0.65, reactMin = 0.28, reactMax = 0.55,
            fov = math.rad(150), aggression = 0.65, dodge = 0.4, name = "Regular" },
    [3] = { aimError = 0.05, lead = 0.9, reactMin = 0.15, reactMax = 0.3,
            fov = math.rad(180), aggression = 0.8, dodge = 0.7, name = "Veteran" },
    [4] = { aimError = 0.02, lead = 1.0, reactMin = 0.08, reactMax = 0.18,
            fov = math.rad(200), aggression = 0.95, dodge = 0.9, name = "Ace" },
  },
}

local TAU = math.pi * 2

local function angDiff(a, b)
  local d = (b - a) % TAU
  if d > math.pi then d = d - TAU end
  return d
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- line of sight through walls
local function hasLos(sim, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local d = dist(x0, y0, x1, y1)
  if d < 1 then return true end
  dx, dy = dx / d, dy / d
  local wx = sim:raycastWalls(x0, y0, dx, dy, d - 4)
  return wx == nil
end

--=============================================================================
-- Per-bot memory
--=============================================================================

function Bot.brainFor(sim, tank, difficulty)
  tank.bot = {
    profile = Bot.profiles[difficulty] or Bot.profiles[2],
    state = "seek",
    stateTimer = 0,
    target = 0,
    react = 0,
    wanderX = nil,
    wanderY = nil,
    strafeDir = (tank.id % 2 == 0) and 1 or -1,
    nextRepathTick = 0,
    aimBias = 0,
    aimTimer = 0,
  }
  return tank.bot
end

local function pickTarget(sim, tank, brain)
  local best, bestScore = nil, -math.huge
  local prof = brain.profile
  for _, e in pairs(sim.tanksById) do
    if e.alive and e.team ~= tank.team then
      local d = dist(tank.x, tank.y, e.x, e.y)
      local los = hasLos(sim, tank.x, tank.y, e.x, e.y)
      local facing = math.abs(angDiff(tank.turret, math.atan2(e.y - tank.y, e.x - tank.x)))
      local score = 900 - d
      + (los and 400 or 0)
      + (d < 500 and 200 or 0)
      - facing * 40
        + (e.hasFlag and 350 or 0)
        + (e.hp / e.maxHp < 0.35 and 250 or 0)
      if score > bestScore then bestScore, best = score, e end
    end
  end
  return best
end

local function nearestPowerup(sim, tank)
  local best, bd = nil, math.huge
  for _, p in ipairs(sim.powerups) do
    if p.active and p.kind == "repair" then
      local d = dist(tank.x, tank.y, p.x, p.y)
      if d < bd then best, bd = p, d end
    end
  end
  return best, bd
end

--=============================================================================
-- Movement goal computation per state
--=============================================================================

local function seekGoal(sim, tank, brain)
  -- wander toward map center-ish with repulsion from walls
  if not brain.wanderX or dist(tank.x, tank.y, brain.wanderX, brain.wanderY) < 80
     or sim.tick > (brain.nextRepathTick or 0) then
    local m = sim.map
    local tx, ty
    local tries = 0
    repeat
      tx = 100 + sim.rng:next(0, m.w - 200)
      ty = 100 + sim.rng:next(0, m.h - 200)
      tries = tries + 1
    until not Maps.solidAt(m, tx, ty, 40) or tries > 8
    brain.wanderX, brain.wanderY = tx, ty
    brain.nextRepathTick = sim.tick + 180   -- ~6s at 30hz
  end
  return brain.wanderX, brain.wanderY
end

local function engageGoal(sim, tank, brain, target)
  local d = dist(tank.x, tank.y, target.x, target.y)
  local ideal = tank.stats.fireMode == "mg" and 180 or 320
  -- strafe around target while keeping range
  local baseA = math.atan2(tank.y - target.y, tank.x - target.x)
  local a = baseA + brain.strafeDir * 0.6
  local wantDist = d > ideal * 1.25 and -1 or (d < ideal * 0.75 and 1 or 0)
  local gx = target.x + math.cos(a) * ideal
  local gy = target.y + math.sin(a) * ideal
  -- if we're too far, cut the angle; too close, back off
  if wantDist ~= 0 then
    gx = tank.x + (target.x - tank.x) * 0.5 + math.cos(a) * 100
    gy = tank.y + (target.y - tank.y) * 0.5 + math.sin(a) * 100
  end
  return gx, gy
end

local function retreatGoal(sim, tank, brain)
  local pu, pd = nearestPowerup(sim, tank)
  if pu and pd < 700 then return pu.x, pu.y end
  -- run away from target
  local target = brain.target and sim.tanksById[brain.target]
  if target and target.alive then
    local a = math.atan2(tank.y - target.y, tank.x - target.x)
    return tank.x + math.cos(a) * 300, tank.y + math.sin(a) * 300
  end
  return seekGoal(sim, tank, brain)
end

local function objectiveGoal(sim, tank, brain)
  local mode = sim.mode.id
  if mode == "ctf" then
    -- go for enemy flag; if carrying, run home
    if tank.hasFlag then
      local base = (tank.team == 1) and sim.map.flags.a or sim.map.flags.b
      return base[1], base[2]
    end
    local enemyFlag = (tank.team == 1) and sim.flags.b or sim.flags.a
    if enemyFlag.carrier == 0 then
      return enemyFlag.x, enemyFlag.y
    end
    -- hunt the carrier
    local carrier = sim.tanksById[enemyFlag.carrier]
    if carrier and carrier.alive then return carrier.x, carrier.y end
  elseif mode == "control" then
    -- nearest non-owned or contested zone
    local best, bd = nil, math.huge
    for _, z in ipairs(sim.zones) do
      local want = (z.owner ~= tank.team)
      if want then
        local d = dist(tank.x, tank.y, z.x, z.y)
        if d < bd then best, bd = z, d end
      end
    end
    if best then return best.x, best.y end
  end
  return nil
end

--=============================================================================
-- Main think
--=============================================================================

function Bot.update(sim, dt)
  local now = sim.timeLeft  -- countdown works as a clock
  for _, tank in pairs(sim.tanksById) do
    if tank.isBot and tank.alive then
      local brain = tank.bot or Bot.brainFor(sim, tank, sim.difficulty)
      local prof = brain.profile

      brain.stateTimer = brain.stateTimer - dt
      brain.react = math.max(0, brain.react - dt)

      local target = pickTarget(sim, tank, brain)
      local d = target and dist(tank.x, tank.y, target.x, target.y) or math.huge
      local los = target and hasLos(sim, tank.x, tank.y, target.x, target.y) or false

      -- state transitions
      local hpFrac = tank.hp / tank.maxHp
      if brain.stateTimer <= 0 then
        if hpFrac < 0.3 and sim.mode.id ~= "ctf" then
          brain.state = "retreat"
          brain.stateTimer = 2 + sim.rng:next(0, 2)
        elseif target and los and d < 460 then
          brain.state = "engage"
          brain.stateTimer = 1 + sim.rng:next(0, 1.5)
        elseif target and d < 700 then
          brain.state = "chase"
          brain.stateTimer = 1 + sim.rng:next(0, 1)
        else
          local goal = objectiveGoal(sim, tank, brain)
          brain.state = goal and "objective" or "seek"
          brain.stateTimer = 1.5 + sim.rng:next(0, 1.5)
        end
      end

      -- movement goal by state
      local gx, gy
      if brain.state == "engage" and target then
        gx, gy = engageGoal(sim, tank, brain, target)
      elseif brain.state == "chase" and target then
        gx, gy = target.x, target.y
      elseif brain.state == "retreat" then
        gx, gy = retreatGoal(sim, tank, brain)
      elseif brain.state == "objective" then
        gx, gy = objectiveGoal(sim, tank, brain)
        if not gx then brain.state = "seek" end
      end
      if not gx then gx, gy = seekGoal(sim, tank, brain) end

      -- drive toward goal (simple obstacle avoid: probe left/right)
      local toA = math.atan2(gy - tank.y, gx - tank.x)
      local hullDelta = angDiff(tank.hull, toA)
      local turn = 0
      if math.abs(hullDelta) > 0.15 then
        turn = (hullDelta > 0) and 1 or -1
      end
      local move = (math.abs(hullDelta) < 1.1) and 1 or 0.25

      -- wall probe: if wall ahead, steer around
      local probe = tank.stats.radius + 26
      local fx, fy = tank.x + math.cos(tank.hull) * probe, tank.y + math.sin(tank.hull) * probe
      if Maps.solidAt(sim.map, fx, fy, 6) then
        local lx = tank.x + math.cos(tank.hull - 0.9) * probe
        local ly = tank.y + math.sin(tank.hull - 0.9) * probe
        turn = Maps.solidAt(sim.map, lx, ly, 6) and 1 or -1
        move = 0.5
      end

      tank.input.move = move
      tank.input.turn = turn

      -- turret aiming with lead + error
      if target then
        local tvx = (target.vx or 0)
        local tvy = (target.vy or 0)
        local bulletSpeed = tank.stats.bulletSpeed
        local eta = d / bulletSpeed * prof.lead
        local px = target.x + tvx * eta
        local py = target.y + tvy * eta
        local want = math.atan2(py - tank.y, px - tank.x)
        -- random aim bias resampled occasionally
        if not brain.aimTimer or brain.aimTimer <= 0 then
          brain.aimBias = (sim.rng:next() * 2 - 1) * prof.aimError
          brain.aimTimer = 0.4 + sim.rng:next(0, 0.5)
        end
        brain.aimTimer = brain.aimTimer - dt
        tank.input.turret = want + brain.aimBias
        -- fire when roughly on target, in LOS, reaction elapsed
        local aimErr = math.abs(angDiff(tank.turret, want))
        brain.fire = (aimErr < 0.14 + prof.aimError) and los and brain.react <= 0
        if brain.fire then brain.react = prof.reactMin + sim.rng:next(0, prof.reactMax - prof.reactMin) end
      else
        tank.input.turret = toA
        brain.fire = false
      end
      tank.input.fire = brain.fire or false
    end
  end
end

return Bot
