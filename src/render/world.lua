--=============================================================================
-- World renderer: maps, tanks, bullets, powerups, zones, flags, particles.
-- Consumes render states from game.client (interpolated snapshots or local
-- sim) and produces explosions, muzzle flashes, tracers, screen shake.
--=============================================================================

local Maps  = require("data.maps")
local Tanks = require("data.tanks")

local gfx = love.graphics
local TAU = math.pi * 2

local _fonts = {}
local function font(size)
  if not _fonts[size] then _fonts[size] = gfx.newFont(size) end
  gfx.setFont(_fonts[size])
  return _fonts[size]
end

-- centered text helper (world space)
local function centerText(text, x, y, size, color)
  local f = font(size or 12)
  gfx.setColor(color or { 1, 1, 1 })
  gfx.print(text, x - f:getWidth(text) / 2, y)
end

local World = {}
World.__index = World

function World.new()
  local self = setmetatable({}, World)
  self.particles = {}
  self.floaters = {}      -- damage numbers
  self.shake = 0
  self.time = 0
  return self
end

function World:spawnExplosion(x, y, size)
  size = size or 1
  for i = 1, math.floor(18 * size) do
    local a = love.math.random() * TAU
    local sp = 40 + love.math.random() * 160 * size
    self.particles[#self.particles + 1] = {
      x = x, y = y,
      vx = math.cos(a) * sp, vy = math.sin(a) * sp,
      life = 0.4 + love.math.random() * 0.5,
      maxLife = 0.9,
      size = 2 + love.math.random() * 4 * size,
      color = { 1, 0.55 + love.math.random() * 0.3, 0.15 },
    }
  end
  self.shake = math.min(10, self.shake + 5 * size)
end

function World:spawnMuzzle(x, y, angle, small)
  for i = 1, small and 4 or 9 do
    local a = angle + (love.math.random() - 0.5) * 0.7
    local sp = 90 + love.math.random() * 130
    self.particles[#self.particles + 1] = {
      x = x, y = y,
      vx = math.cos(a) * sp, vy = math.sin(a) * sp,
      life = 0.12 + love.math.random() * 0.12,
      maxLife = 0.24,
      size = 1.5 + love.math.random() * 2.5,
      color = { 1, 0.8, 0.35 },
    }
    -- tracer line
    self.particles[#self.particles + 1] = {
      x = x, y = y, vx = math.cos(a) * 700, vy = math.sin(a) * 700,
      life = 0.05, maxLife = 0.05, size = 1.2,
      color = { 1, 0.9, 0.5 }, line = true, len = small and 12 or 26,
    }
  end
  self.shake = math.min(10, self.shake + (small and 0.4 or 1.6))
  self.flash = { x = x, y = y, t = 0.06, angle = angle }
end

function World:spawnHitFx(x, y, ricochet)
  for i = 1, 7 do
    local a = love.math.random() * TAU
    local sp = 60 + love.math.random() * 120
    self.particles[#self.particles + 1] = {
      x = x, y = y,
      vx = math.cos(a) * sp, vy = math.sin(a) * sp,
      life = 0.25, maxLife = 0.25, size = 1.5 + love.math.random() * 2,
      color = ricochet and { 0.8, 0.85, 0.9 } or { 1, 0.6, 0.25 },
    }
  end
end

function World:spawnDamageNumber(x, y, amount)
  self.floaters[#self.floaters + 1] = { x = x, y = y - 20, text = tostring(math.floor(amount + 0.5)), life = 0.8, maxLife = 0.8 }
end

function World:update(dt)
  self.time = self.time + dt
  self.shake = math.max(0, self.shake - dt * 26)
  if self.flash then
    self.flash.t = self.flash.t - dt
    if self.flash.t <= 0 then self.flash = nil end
  end
  for i = #self.particles, 1, -1 do
    local p = self.particles[i]
    p.life = p.life - dt
    if p.life <= 0 then
      self.particles[i] = self.particles[#self.particles]
      self.particles[#self.particles] = nil
    else
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vx = p.vx * (1 - 2.4 * dt)
      p.vy = p.vy * (1 - 2.4 * dt)
    end
  end
  for i = #self.floaters, 1, -1 do
    local f = self.floaters[i]
    f.life = f.life - dt
    f.y = f.y - 34 * dt
    if f.life <= 0 then
      self.floaters[i] = self.floaters[#self.floaters]
      self.floaters[#self.floaters] = nil
    end
  end
end

--=============================================================================
-- Camera
--=============================================================================

function World:applyCamera(cam, w, h)
  local sx = (love.math.random() - 0.5) * self.shake
  local sy = (love.math.random() - 0.5) * self.shake
  gfx.push()
  gfx.translate(w / 2, h / 2)
  gfx.scale(cam.zoom or 1)
  gfx.translate(-cam.x + sx, -cam.y + sy)
end

function World:popCamera()
  gfx.pop()
end

--=============================================================================
-- Map
--=============================================================================

function World:drawMap(map)
  -- ground
  gfx.setColor(map.theme.ground)
  gfx.rectangle("fill", 0, 0, map.w, map.h)

  -- subtle grid
  local grid = map.theme.grid
  gfx.setColor(grid[1], grid[2], grid[3], 0.5)
  gfx.setLineWidth(1)
  for gx = 0, map.w, 100 do
    gfx.line(gx, 0, gx, map.h)
  end
  for gy = 0, map.h, 100 do
    gfx.line(0, gy, map.w, gy)
  end

  -- walls with pseudo-3d top
  for _, wl in ipairs(map.walls) do
    gfx.setColor(0, 0, 0, 0.35)
    gfx.rectangle("fill", wl.x + 5, wl.y + 7, wl.w, wl.h, 3)
    gfx.setColor(map.theme.wall)
    gfx.rectangle("fill", wl.x, wl.y, wl.w, wl.h, 3)
    gfx.setColor(map.theme.wallTop)
    gfx.rectangle("fill", wl.x + 2, wl.y + 2, wl.w - 4, wl.h - 4, 3)
  end
end

--=============================================================================
-- Entities
--=============================================================================

function World:drawTank(ent, meta)
  -- meta: {camo colors, name, team, isMyTank, isBot}
  local body, track, accent
  local def = Tanks.get(meta.tankId) or Tanks.get("scout")
  local camo = Tanks.camouflageFor(meta.tankId, nil, meta.camoSel or {})
  body, track, accent = camo.body, camo.track, camo.accent

  gfx.push()
  gfx.translate(ent.x, ent.y)

  -- team ring / selection ring
  if meta.team then
    gfx.setColor(meta.team == 1 and { 0.25, 0.55, 1, 0.85 } or { 1, 0.3, 0.3, 0.85 })
    gfx.setLineWidth(2)
    gfx.circle("line", 0, 0, def.radius + 7)
  end

  -- shadow
  gfx.setColor(0, 0, 0, 0.3)
  gfx.ellipse("fill", 3, 4, def.radius + 4, def.radius + 2)

  -- tracks
  gfx.push()
  gfx.rotate(ent.hull)
  gfx.setColor(track[1], track[2], track[3])
  gfx.rectangle("fill", -def.radius - 2, -def.radius - 3, (def.radius + 2) * 2, 7, 2)
  gfx.rectangle("fill", -def.radius - 2, def.radius - 4, (def.radius + 2) * 2, 7, 2)
  -- track links
  gfx.setColor(0.1, 0.1, 0.1, 0.6)
  local step = 7
  local phase = (self.time * 40) % step
  local inv = 1
  for lx = -def.radius - 2 + phase, def.radius + 2, step do
    gfx.rectangle("fill", lx, -def.radius - 3, 2, 7)
    gfx.rectangle("fill", lx, def.radius - 4, 2, 7)
  end
  gfx.pop()

  -- hull
  gfx.push()
  gfx.rotate(ent.hull)
  gfx.setColor(body[1], body[2], body[3])
  gfx.rectangle("fill", -def.radius, -def.radius * 0.78, def.radius * 2, def.radius * 1.56, 4)
  gfx.setColor(1, 1, 1, 0.12)
  gfx.rectangle("line", -def.radius, -def.radius * 0.78, def.radius * 2, def.radius * 1.56, 4)
  gfx.pop()

  -- turret + barrel
  gfx.push()
  gfx.rotate(ent.turret)
  gfx.setColor(body[1] * 0.85, body[2] * 0.85, body[3] * 0.85)
  gfx.rectangle("fill", -5, -5, 10, 10, 3)
  gfx.setColor(accent[1], accent[2], accent[3])
  if meta.tankId == "gunner" then
    gfx.rectangle("fill", 4, -2, def.radius + 12, 3)      -- mg barrel
    gfx.rectangle("fill", 4, -1, def.radius + 6, 3)
  else
    gfx.rectangle("fill", 4, -2.5, def.radius + 10, 5, 2) -- cannon
    gfx.setColor(body[1] * 0.6, body[2] * 0.6, body[3] * 0.6)
    gfx.rectangle("fill", def.radius + 6, -3.5, 5, 7)     -- muzzle brake
  end
  gfx.pop()

  -- invulnerability shimmer
  if bit32 and bit32.band(ent.flags or 0, 4) ~= 0 then
    gfx.setColor(0.7, 0.85, 1, 0.25 + 0.15 * math.sin(self.time * 12))
    gfx.circle("line", 0, 0, def.radius + 10)
  end
  -- shield fx
  if bit32 and bit32.band(ent.flags or 0, 8) ~= 0 then
    gfx.setColor(0.3, 0.6, 1, 0.3 + 0.1 * math.sin(self.time * 8))
    gfx.circle("fill", 0, 0, def.radius + 8)
  end
  -- rapid/damage/speed indicators
  if bit32 and bit32.band(ent.flags or 0, 16) ~= 0 then
    gfx.setColor(1, 0.8, 0.2, 0.8)
    gfx.circle("fill", -def.radius - 6, -def.radius - 6, 3)
  end
  if bit32 and bit32.band(ent.flags or 0, 32) ~= 0 then
    gfx.setColor(1, 0.3, 0.2, 0.8)
    gfx.circle("fill", -def.radius - 6, -def.radius - 6, 3)
  end
  if bit32 and bit32.band(ent.flags or 0, 64) ~= 0 then
    gfx.setColor(1, 0.4, 1, 0.8)
    gfx.circle("fill", -def.radius - 6, -def.radius - 6, 3)
  end
  -- flag carrier marker
  if bit32 and bit32.band(ent.flags or 0, 2) ~= 0 then
    gfx.setColor(1, 0.9, 0.3)
    gfx.push()
    gfx.rotate(-ent.hull)
    gfx.polygon("fill", 0, -def.radius - 18, 7, -def.radius - 10, 0, -def.radius - 2, -7, -def.radius - 10)
    gfx.pop()
  end

  gfx.pop()

  -- hp bar + name
  local hpFrac = (ent.maxHp and ent.maxHp > 0) and (ent.hp / ent.maxHp) or 1
  local barW = def.radius * 2
  local yOff = def.radius + 12
  gfx.setColor(0, 0, 0, 0.55)
  gfx.rectangle("fill", ent.x - barW / 2 - 1, ent.y - yOff - 1, barW + 2, 6, 2)
  local hpColor = hpFrac > 0.55 and { 0.3, 0.85, 0.35 } or (hpFrac > 0.25 and { 0.95, 0.75, 0.2 } or { 0.95, 0.3, 0.25 })
  gfx.setColor(hpColor)
  gfx.rectangle("fill", ent.x - barW / 2, ent.y - yOff, barW * hpFrac, 4, 2)

  if meta.name then
    centerText(meta.name, ent.x, ent.y + def.radius + 4, 12, meta.nameColor or { 0.9, 0.92, 0.95 })
  end
end

-- bullets
function World:drawBullets(bullets)
  for _, b in ipairs(bullets) do
    if b.kind == 1 then
      gfx.setColor(1, 0.9, 0.4)
      local tl = 14
      gfx.setLineWidth(2)
      gfx.line(b.x - math.cos(b.angle) * tl, b.y - math.sin(b.angle) * tl, b.x, b.y)
    else
      gfx.setColor(1, 0.75, 0.3)
      gfx.circle("fill", b.x, b.y, 3.5)
      gfx.setColor(1, 0.6, 0.15, 0.4)
      gfx.circle("fill", b.x - math.cos(b.angle) * 6, b.y - math.sin(b.angle) * 6, 2.5)
    end
  end
  gfx.setLineWidth(1)
end

-- powerups
function World:drawPowerups(sim)
  if not sim then return end
  for _, p in ipairs(sim.powerups) do
    if p.active and p.kind then
      local spec = require("game.sim").POWERUPS[p.kind]
      local pulse = 1 + 0.12 * math.sin(self.time * 5)
      gfx.setColor(0, 0, 0, 0.3)
      gfx.ellipse("fill", p.x, p.y + 8, 14, 5)
      gfx.setColor(spec.color[1], spec.color[2], spec.color[3], 0.9)
      gfx.push()
      gfx.translate(p.x, p.y)
      gfx.rotate(self.time * 1.2)
      gfx.rectangle("fill", -9 * pulse, -9 * pulse, 18 * pulse, 18 * pulse, 3)
      gfx.setColor(1, 1, 1, 0.85)
      gfx.rectangle("fill", -3.5, -3.5, 7, 7, 2)
      gfx.pop()
      -- icon glyph: repair cross, shield dot, etc. keep simple: white square
    end
  end
end

-- zones (control)
function World:drawZones(sim)
  if not sim or not sim.zones then return end
  for _, z in ipairs(sim.zones) do
    local col = z.owner == 0 and { 0.8, 0.8, 0.8, 0.14 }
      or (z.owner == 1 and { 0.25, 0.55, 1, 0.2 } or { 1, 0.3, 0.3, 0.2 })
    gfx.setColor(col)
    gfx.circle("fill", z.x, z.y, z.r)
    gfx.setColor(z.owner == 1 and { 0.35, 0.6, 1 } or (z.owner == 2 and { 1, 0.4, 0.4 } or { 0.7, 0.7, 0.7 }))
    gfx.setLineWidth(2)
    gfx.circle("line", z.x, z.y, z.r)
    gfx.setLineWidth(1)
    centerText("ZONE", z.x, z.y - 8, 11, { 1, 1, 1, 0.4 })
  end
end

-- flags (ctf)
function World:drawFlags(sim)
  if not sim or not sim.flags then return end
  for side, f in pairs(sim.flags) do
    local color = (side == "a") and { 0.3, 0.6, 1 } or { 1, 0.35, 0.35 }
    gfx.setColor(0, 0, 0, 0.3)
    gfx.ellipse("fill", f.x, f.y + 10, 10, 4)
    gfx.setColor(0.45, 0.35, 0.2)
    gfx.rectangle("fill", f.x - 1.5, f.y - 26, 3, 36)
    gfx.setColor(color)
    gfx.polygon("fill", f.x + 1.5, f.y - 26, f.x + 20, f.y - 19, f.x + 1.5, f.y - 12)
  end
end

--=============================================================================
-- Minimap
--=============================================================================

function World:drawMinimap(x, y, w, h, map, tanks, myId, modeExtras)
  gfx.setColor(0.05, 0.07, 0.09, 0.85)
  gfx.rectangle("fill", x, y, w, h, 6)
  local sx = w / map.w
  local sy = h / map.h
  local wallCol = map.theme.wall
  gfx.push()
  gfx.translate(x, y)
  gfx.scale(sx, sy)
  gfx.setColor(wallCol[1], wallCol[2], wallCol[3], 1)
  for _, wl in ipairs(map.walls) do
    gfx.rectangle("fill", wl.x, wl.y, wl.w, wl.h)
  end
  gfx.pop()
  -- zones
  if modeExtras and modeExtras.zones then
    for i, z in ipairs(modeExtras.zones or {}) do
      local pt = map.points[i]
      if pt then
        gfx.setColor(z.owner == 1 and { 0.35, 0.6, 1, 0.8 } or (z.owner == 2 and { 1, 0.4, 0.4, 0.8 } or { 0.8, 0.8, 0.8, 0.5 }))
        gfx.circle("fill", x + pt[1] * sx, y + pt[2] * sy, 6)
      end
    end
  end
  -- flags
  if modeExtras and modeExtras.flags then
    for side, f in pairs(modeExtras.flags) do
      gfx.setColor((side == "a") and { 0.35, 0.6, 1 } or { 1, 0.4, 0.4 })
      gfx.circle("fill", x + f.x * sx, y + f.y * sy, 4)
    end
  end
  -- tanks
  for _, t in ipairs(tanks) do
    local isMe = (t.id == myId)
    local meta = modeExtras and modeExtras.meta and modeExtras.meta[t.id]
    local team = meta and meta.team
    local col = isMe and { 0.2, 1, 0.4 } or (team == 1 and { 0.35, 0.6, 1 } or (team == 2 and { 1, 0.4, 0.4 } or { 0.9, 0.9, 0.9 }))
    gfx.setColor(col)
    gfx.circle("fill", x + t.x * sx, y + t.y * sy, isMe and 4 or 3)
  end
  gfx.setColor(1, 1, 1, 0.15)
  gfx.setLineWidth(1)
  gfx.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6)
end

--=============================================================================
-- Particles overlay (screen space after camera pop)
--=============================================================================

-- draw inside camera transform (world space fx)
function World:drawParticles()
  for _, p in ipairs(self.particles) do
    local a = math.min(1, p.life / p.maxLife * 1.6)
    if p.line then
      local pa = p.angle or math.atan2(p.vy or 0, p.vx or 1)
      gfx.setColor(p.color[1], p.color[2], p.color[3], a)
      gfx.setLineWidth(p.size)
      gfx.line(p.x, p.y, p.x - math.cos(pa) * (p.len or 20), p.y - math.sin(pa) * (p.len or 20))
    else
      gfx.setColor(p.color[1], p.color[2], p.color[3], a)
      gfx.circle("fill", p.x, p.y, p.size * (0.5 + a * 0.5))
    end
  end
  gfx.setLineWidth(1)
  if self.flash then
    gfx.setColor(1, 0.85, 0.4, 0.5)
    gfx.circle("fill", self.flash.x, self.flash.y, 10)
  end
end

function World:drawFloaters()
  font(14)
  for _, f in ipairs(self.floaters) do
    local a = f.life / f.maxLife
    gfx.setColor(1, 0.9, 0.4, a)
    gfx.print(f.text, f.x, f.y)
  end
end

return World
