--=============================================================================
-- Map catalog. Rectangles-only collision geometry (fast + predictable).
-- Each map: world size, walls, team/ffa spawns, powerup pads, mode anchors.
--=============================================================================

local Maps = {
  list = {},
  byId = {},
}

local function border(w, h, t)
  t = t or 40
  return {
    { x = 0,     y = 0,     w = w,   h = t   },
    { x = 0,     y = h - t, w = w,   h = t   },
    { x = 0,     y = 0,     w = t,   h = h   },
    { x = w - t, y = 0,     w = t,   h = h   },
  }
end

local function merge(...)
  local out = {}
  for i = 1, select("#", ...) do
    local arr = select(i, ...)
    for _, v in ipairs(arr) do out[#out + 1] = v end
  end
  return out
end

Maps.definitions = {

  outpost = {
    id = "outpost", name = "Outpost",
    desc = "Small symmetric base. Brawling distance everywhere.",
    w = 1900, h = 1300,
    theme = { ground = {0.16,0.20,0.14}, grid = {0.2,0.26,0.18}, wall = {0.36,0.32,0.28}, wallTop = {0.5,0.46,0.4} },
    spawnsA = { {180, 650}, {120, 420}, {120, 880}, {340, 650} },
    spawnsB = { {1720, 650}, {1780, 420}, {1780, 880}, {1560, 650} },
    spawnsFfa = {
      {180, 650}, {1720, 650}, {180, 160}, {1720, 160},
      {950, 150}, {950, 1150}, {180, 1140}, {1720, 1140},
      {600, 650}, {1300, 650},
    },
    flags = { a = {180, 650}, b = {1720, 650} },
    points = { {950, 650} },
    powerups = { {950, 350}, {950, 950}, {500, 650}, {1400, 650} },
    walls = merge(border(1900, 1300), {
      -- side bunkers
      { x = 420, y = 300, w = 60, h = 260 },
      { x = 420, y = 740, w = 60, h = 260 },
      { x = 1420, y = 300, w = 60, h = 260 },
      { x = 1420, y = 740, w = 60, h = 260 },
      -- center cover
      { x = 780, y = 520, w = 340, h = 60 },
      { x = 780, y = 720, w = 340, h = 60 },
      { x = 900, y = 380, w = 100, h = 60 },
      { x = 900, y = 860, w = 100, h = 60 },
    }),
  },

  dunes = {
    id = "dunes", name = "Dunes",
    desc = "Open sand sea. Long sightlines, ridge-to-ridge duels.",
    w = 2400, h = 1500,
    theme = { ground = {0.42,0.34,0.2}, grid = {0.46,0.38,0.24}, wall = {0.55,0.45,0.28}, wallTop = {0.7,0.6,0.4} },
    spawnsA = { {160, 750}, {140, 500}, {140, 1000}, {320, 750} },
    spawnsB = { {2240, 750}, {2260, 500}, {2260, 1000}, {2080, 750} },
    spawnsFfa = {
      {160, 750}, {2240, 750}, {300, 200}, {2100, 200},
      {1200, 180}, {1200, 1320}, {300, 1300}, {2100, 1300},
      {800, 750}, {1600, 750},
    },
    flags = { a = {160, 750}, b = {2240, 750} },
    points = { {700, 750}, {1700, 750}, {1200, 400} },
    powerups = { {1200, 750}, {600, 400}, {1800, 400}, {600, 1100}, {1800, 1100} },
    walls = merge(border(2400, 1500), {
      -- long ridges
      { x = 500,  y = 380, w = 320, h = 70 },
      { x = 500,  y = 1050, w = 320, h = 70 },
      { x = 1580, y = 380, w = 320, h = 70 },
      { x = 1580, y = 1050, w = 320, h = 70 },
      -- center rocks
      { x = 1130, y = 600, w = 140, h = 90 },
      { x = 900,  y = 900, w = 90, h = 90 },
      { x = 1410, y = 900, w = 90, h = 90 },
      -- flank blocks
      { x = 760, y = 180, w = 70, h = 220 },
      { x = 1570, y = 180, w = 70, h = 220 },
      { x = 760, y = 1100, w = 70, h = 220 },
      { x = 1570, y = 1100, w = 70, h = 220 },
    }),
  },

  foundry = {
    id = "foundry", name = "Foundry",
    desc = "Industrial maze. Corner peeks, ambush lanes, chaos.",
    w = 2200, h = 1500,
    theme = { ground = {0.14,0.15,0.17}, grid = {0.18,0.19,0.22}, wall = {0.3,0.32,0.36}, wallTop = {0.45,0.48,0.53} },
    spawnsA = { {170, 750}, {140, 480}, {140, 1020}, {330, 750} },
    spawnsB = { {2030, 750}, {2060, 480}, {2060, 1020}, {1870, 750} },
    spawnsFfa = {
      {170, 750}, {2030, 750}, {250, 230}, {1950, 230},
      {1100, 200}, {1100, 1300}, {250, 1270}, {1950, 1270},
      {700, 750}, {1500, 750},
    },
    flags = { a = {170, 750}, b = {2030, 750} },
    points = { {1100, 750}, {600, 400}, {1600, 400}, {600, 1100}, {1600, 1100} },
    powerups = { {1100, 300}, {1100, 1200}, {420, 750}, {1780, 750} },
    walls = merge(border(2200, 1500), {
      -- maze lanes
      { x = 450,  y = 250,  w = 60, h = 400 },
      { x = 450,  y = 850,  w = 60, h = 400 },
      { x = 1690, y = 250,  w = 60, h = 400 },
      { x = 1690, y = 850,  w = 60, h = 400 },
      { x = 700,  y = 600,  w = 500, h = 60 },
      { x = 1000, y = 840,  w = 500, h = 60 },
      { x = 1050, y = 250,  w = 60, h = 300 },
      { x = 1050, y = 950,  w = 60, h = 300 },
      { x = 1350, y = 600,  w = 250, h = 60 },
      { x = 600,  y = 840,  w = 250, h = 60 },
      -- pillars
      { x = 300,  y = 300,  w = 90, h = 90 },
      { x = 1810, y = 300,  w = 90, h = 90 },
      { x = 300,  y = 1110, w = 90, h = 90 },
      { x = 1810, y = 1110, w = 90, h = 90 },
    }),
  },

  fortress = {
    id = "fortress", name = "Fortress",
    desc = "Twin forts, contested courtyard. Objective play decided center.",
    w = 2300, h = 1500,
    theme = { ground = {0.18,0.22,0.24}, grid = {0.22,0.27,0.29}, wall = {0.4,0.38,0.34}, wallTop = {0.55,0.52,0.47} },
    spawnsA = { {220, 750}, {170, 520}, {170, 980}, {400, 750} },
    spawnsB = { {2080, 750}, {2130, 520}, {2130, 980}, {1900, 750} },
    spawnsFfa = {
      {220, 750}, {2080, 750}, {220, 220}, {2080, 220},
      {1150, 200}, {1150, 1300}, {220, 1280}, {2080, 1280},
      {750, 750}, {1550, 750},
    },
    flags = { a = {220, 750}, b = {2080, 750} },
    points = { {1150, 750}, {750, 400}, {1550, 400}, {750, 1100}, {1550, 1100} },
    powerups = { {1150, 420}, {1150, 1080}, {620, 750}, {1680, 750} },
    walls = merge(border(2300, 1500), {
      -- fort A walls
      { x = 480, y = 480, w = 60, h = 220 },
      { x = 480, y = 800, w = 60, h = 220 },
      { x = 480, y = 480, w = 240, h = 60 },
      { x = 480, y = 960, w = 240, h = 60 },
      -- fort B walls
      { x = 1760, y = 480, w = 60, h = 220 },
      { x = 1760, y = 800, w = 60, h = 220 },
      { x = 1580, y = 480, w = 240, h = 60 },
      { x = 1580, y = 960, w = 240, h = 60 },
      -- courtyard
      { x = 1000, y = 300, w = 90, h = 90 },
      { x = 1210, y = 300, w = 90, h = 90 },
      { x = 1000, y = 1110, w = 90, h = 90 },
      { x = 1210, y = 1110, w = 90, h = 90 },
      { x = 1090, y = 640, w = 120, h = 220 },
    }),
  },
}

function Maps.init()
  for id, m in pairs(Maps.definitions) do
    m.id = id
    Maps.list[#Maps.list + 1] = m
    Maps.byId[id] = m
  end
  table.sort(Maps.list, function(a, b) return a.w * a.h < b.w * b.h end)
end

function Maps.get(id) return Maps.byId[id] or Maps.byId.outpost end

function Maps.all() return Maps.list end

-- Point vs walls test (used by AI line-of-sight and bullet raycast).
function Maps.solidAt(map, x, y, pad)
  pad = pad or 0
  for _, w in ipairs(map.walls) do
    if x >= w.x - pad and x <= w.x + w.w + pad and y >= w.y - pad and y <= w.y + w.h + pad then
      return true
    end
  end
  return false
end

return Maps
