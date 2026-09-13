--=============================================================================
-- Tank definitions, upgrade tree and camouflage catalog.
-- Pure data + pure functions: usable on client AND dedicated server.
--
-- Stats model (per level, max 3):
--   engine -> +10% speed      armor  -> +12% max hp
--   loader -> -8% reload      gun    -> +8% damage
--   optics -> +12% turret turn rate
--=============================================================================

local Tanks = {
  list = {},
  byId = {},
  maxUpgradeLevel = 3,
}

local PARTS = {
  { id = "engine", name = "Engine",     desc = "+10% top speed per level" },
  { id = "armor",  name = "Armor",      desc = "+12% hit points per level" },
  { id = "loader", name = "Auto-loader",desc = "-8% reload time per level" },
  { id = "gun",    name = "Main gun",   desc = "+8% shell damage per level" },
  { id = "optics", name = "Optics",     desc = "+12% turret speed per level" },
}
Tanks.parts = PARTS

Tanks.definitions = {
  scout = {
    name = "Scorpion", class = "Light",
    price = 0,
    radius = 14,
    hp = 90,  speed = 230, turn = 3.4, turret = 4.0,
    reload = 1.15, damage = 22, bulletSpeed = 640,
    fireMode = "cannon",
    desc = "Fast recon. Blink in, shoot first, blink out.",
    color = { body = {0.36,0.62,0.32}, track = {0.22,0.22,0.22}, accent = {0.85,0.85,0.6} },
  },
  gunner = {
    name = "Hornet", class = "TD",
    price = 2500,
    radius = 15,
    hp = 110, speed = 190, turn = 3.0, turret = 4.4,
    reload = 0.16, damage = 7, bulletSpeed = 760,
    fireMode = "mg",
    desc = "Belt-fed autocannon. Melts light armor up close.",
    color = { body = {0.55,0.45,0.28}, track = {0.2,0.2,0.2}, accent = {0.9,0.75,0.35} },
  },
  brawler = {
    name = "Rampart", class = "Medium",
    price = 3200,
    radius = 16,
    hp = 150, speed = 170, turn = 2.6, turret = 3.2,
    reload = 1.7, damage = 38, bulletSpeed = 600,
    fireMode = "cannon",
    desc = "Balanced medium. Wins brawls behind cover.",
    color = { body = {0.45,0.48,0.52}, track = {0.18,0.18,0.2}, accent = {0.75,0.78,0.82} },
  },
  sniper = {
    name = "Longshot", class = "Sniper",
    price = 4500,
    radius = 15,
    hp = 100, speed = 160, turn = 2.4, turret = 2.1,
    reload = 2.6, damage = 72, bulletSpeed = 980,
    fireMode = "cannon",
    desc = "One shot, one wreck. Keep your distance.",
    color = { body = {0.32,0.42,0.5}, track = {0.16,0.16,0.18}, accent = {0.6,0.85,0.95} },
  },
  heavy = {
    name = "Bastion", class = "Heavy",
    price = 6000,
    radius = 19,
    hp = 230, speed = 130, turn = 2.0, turret = 2.4,
    reload = 2.3, damage = 52, bulletSpeed = 560,
    fireMode = "cannon",
    desc = "Walking bunker. Slow, angry, very hard to kill.",
    color = { body = {0.4,0.34,0.3}, track = {0.15,0.15,0.15}, accent = {0.8,0.6,0.4} },
  },
}

Tanks.camos = {
  none    = { name = "Factory",   price = 0,    body = nil,                       accent = nil },
  desert  = { name = "Desert",    price = 600,  body = {0.72,0.62,0.4},  accent = {0.9,0.85,0.65} },
  arctic  = { name = "Arctic",    price = 600,  body = {0.82,0.86,0.9},  accent = {0.55,0.7,0.85} },
  urban   = { name = "Urban",     price = 800,  body = {0.42,0.44,0.48}, accent = {0.7,0.72,0.75} },
  crimson = { name = "Crimson",   price = 1200, body = {0.55,0.14,0.16}, accent = {1.0,0.75,0.3} },
}

function Tanks.init()
  for id, def in pairs(Tanks.definitions) do
    def.id = id
    Tanks.list[#Tanks.list + 1] = def
    Tanks.byId[id] = def
  end
  table.sort(Tanks.list, function(a, b) return a.price < b.price end)
end

function Tanks.get(id) return Tanks.byId[id] end

function Tanks.all() return Tanks.list end

-- Compute final stats from base + upgrade levels table {[partId]=lvl}.
function Tanks.statsFor(tankId, upgradeLevels)
  local def = Tanks.byId[tankId] or Tanks.byId.scout
  local u = upgradeLevels or {}
  local function lvl(part) return math.min(Tanks.maxUpgradeLevel, u[part] or 0) end

  local s = {
    id = def.id,
    name = def.name,
    class = def.class,
    radius = def.radius,
    hp       = def.hp * (1 + 0.12 * lvl("armor")),
    speed    = def.speed * (1 + 0.10 * lvl("engine")),
    turn     = def.turn,
    turret   = def.turret * (1 + 0.12 * lvl("optics")),
    reload   = def.reload * (1 - 0.08 * lvl("loader")),
    damage   = def.damage * (1 + 0.08 * lvl("gun")),
    bulletSpeed = def.bulletSpeed,
    fireMode = def.fireMode,
    color = def.color,
  }
  return s
end

-- Preview stats at hypothetical upgrade levels (garage UI).
function Tanks.previewStats(tankId, levels)
  return Tanks.statsFor(tankId, levels)
end

function Tanks.upgradePrice(tankId, partId, currentLevel)
  local mult = 1
  local def = Tanks.byId[tankId]
  if def and def.price and def.price > 0 then mult = 1 + def.price / 8000 end
  return math.floor(350 * (currentLevel + 1) * mult / 10) * 10
end

function Tanks.camouflageFor(tankId, ownedCamos, selectedCamos)
  local def = Tanks.byId[tankId]
  local camoId = selectedCamos and selectedCamos[tankId]
  local camo = camoId and Tanks.camos[camoId]
  if not def then return nil end
  local c = {
    body   = (camo and camo.body)   or def.color.body,
    track  = def.color.track,
    accent = (camo and camo.accent) or def.color.accent,
  }
  return c
end

return Tanks
