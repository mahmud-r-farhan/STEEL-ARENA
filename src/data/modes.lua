--=============================================================================
-- Game mode definitions: rules, score limits, team layout, bot support.
--=============================================================================

local Modes = {
  list = {},
  byId = {},
}

Modes.definitions = {
  dm = {
    id = "dm", name = "Deathmatch",
    short = "FFA",
    teams = false,
    minPlayers = 2, maxPlayers = 12,
    scoreLimit = 15,          -- kills to win
    timeLimit = 420,          -- seconds
    desc = "Everyone vs everyone. First to 15 kills.",
    scoreLabel = "KILLS",
  },
  tdm = {
    id = "tdm", name = "Team Deathmatch",
    short = "TDM",
    teams = true,
    minPlayers = 2, maxPlayers = 12,
    scoreLimit = 25,
    timeLimit = 480,
    desc = "Red vs Blue. First team to 25 kills.",
    scoreLabel = "KILLS",
  },
  ctf = {
    id = "ctf", name = "Capture the Flag",
    short = "CTF",
    teams = true,
    minPlayers = 2, maxPlayers = 12,
    scoreLimit = 3,           -- captures to win
    timeLimit = 600,
    desc = "Steal the enemy flag, return it to your base.",
    scoreLabel = "CAPS",
  },
  control = {
    id = "control", name = "Control Points",
    short = "CTRL",
    teams = true,
    minPlayers = 2, maxPlayers = 12,
    scoreLimit = 300,         -- points
    timeLimit = 540,
    tickRate = 1.0,           -- seconds per score tick
    pointsPerTick = 1,
    desc = "Hold zones to bleed score. 300 points wins.",
    scoreLabel = "PTS",
  },
  solo = {
    id = "solo", name = "Solo Assault",
    short = "PVE",
    teams = true,             -- player + allies vs bots
    minPlayers = 1, maxPlayers = 12,
    scoreLimit = 20,          -- bot kills to win
    timeLimit = 480,
    desc = "You (+ optional allies) vs waves of enemy tanks.",
    scoreLabel = "KILLS",
    pve = true,
  },
}

function Modes.init()
  for id, m in pairs(Modes.definitions) do
    m.id = id
    Modes.list[#Modes.list + 1] = m
    Modes.byId[id] = m
  end
  table.sort(Modes.list, function(a, b)
    local order = { dm = 1, tdm = 2, ctf = 3, control = 4, solo = 5 }
    return (order[a.id] or 9) < (order[b.id] or 9)
  end)
end

function Modes.get(id) return Modes.byId[id] or Modes.byId.dm end
function Modes.all() return Modes.list end

return Modes
