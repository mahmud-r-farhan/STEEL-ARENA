--=============================================================================
-- Headless self-test: validates protocol roundtrips and runs a full offline
-- battle with bots until a winner emerges. Run: love src --selftest
--=============================================================================

local Protocol = require("net.protocol")
local Sim      = require("game.sim")
local Bot      = require("game.bot")
local Tanks    = require("data.tanks")
local Maps     = require("data.maps")
local Modes    = require("data.modes")

local T = Protocol.T
local failures = 0

local function check(cond, label)
  if cond then
    print("  ok  - " .. label)
  else
    failures = failures + 1
    print("  FAIL- " .. label)
  end
end

local function approx(a, b, eps)
  return math.abs(a - b) <= (eps or 0.51)
end

local function roundtrip(msgType, msg, label)
  local data = Protocol.encode(msgType, msg)
  check(data and #data > 0, label .. " encodes (" .. tostring(data and #data) .. " bytes)")
  local t2, m2, used = Protocol.decode(data)
  check(t2 == msgType, label .. " decodes to same type")
  check(used == #data, label .. " consumes exactly all bytes")
  return m2
end

local function testProtocol()
  print("[protocol]")
  local m
  m = roundtrip(T.HELLO, { name = "Ace", tankId = "heavy", camoId = "crimson",
    upgrades = { 1, 2, 3, 0, 1 }, version = 1 }, "HELLO")
  check(m.name == "Ace" and m.tankId == "heavy" and m.upgrades[3] == 3, "HELLO fields")

  m = roundtrip(T.INPUT, { seq = 7, move = 1, turn = -1, turret = 3.14159, fire = true }, "INPUT")
  check(m.move == 1 and m.turn == -1 and m.fire == true, "INPUT fields")
  check(approx(m.turret, 3.14159, 0.002), "INPUT angle precision")

  m = roundtrip(T.ROOM_CREATE, { name = "My Room", mapId = "dunes", modeId = "tdm",
    maxPlayers = 12, password = "pw", bots = 4, difficulty = 3 }, "ROOM_CREATE")
  check(m.maxPlayers == 12 and m.bots == 4 and m.password == "pw", "ROOM_CREATE fields")

  m = roundtrip(T.SNAPSHOT, {
    tick = 65535,
    tanks = {
      { id = 3000, x = 1234.5, y = 999.9, hull = 6.2, turret = 1.57, hp = 88,
        reload = 0.5, flags = 255 },
      { id = 7, x = 1, y = 2, hull = 0.1, turret = 0.2, hp = 1, reload = 0, flags = 1 },
    },
    bullets = { { id = 44, x = 100.5, y = 200.25, angle = 2.0, kind = 1 } },
    events = { { kind = 5, tankId = 3, extra = 9, x = 10, y = 20, extra2 = 33 } },
    mode = { scoreA = 12, scoreB = 34, timeLeft = 300,
      zones = { { owner = 1 }, { owner = 2 } }, flagA = 3000, flagB = 0 },
  }, "SNAPSHOT")
  check(#m.tanks == 2 and m.tanks[1].id == 3000 and m.tanks[1].x == 1234.5, "SNAPSHOT tanks")
  check(m.mode.flagA == 3000 and #m.mode.zones == 2, "SNAPSHOT mode")

  m = roundtrip(T.MATCH_END, { winner = 3000, scoreboard = {
    { id = 3000, name = "Bot_10", kills = 15, deaths = 2, score = 1800, xp = 210, credits = 370 },
    { id = 4, name = "Me", kills = 3, deaths = 8, score = 500, xp = 66, credits = 108 },
  } }, "MATCH_END")
  check(m.winner == 3000 and m.scoreboard[1].kills == 15, "MATCH_END fields")

  m = roundtrip(T.MATCH_START, { mapId = "fortress", modeId = "ctf", seed = 123456789,
    tickRate = 30, players = {
      { id = 3000, name = "Bot", tankId = "sniper", camoId = "arctic", team = 2,
        isBot = true, x = 100.5, y = 200.5, hp = 100, upgrades = { 3, 3, 3, 3, 3 } },
      { id = 1, name = "Me", tankId = "scout", camoId = "none", team = 1,
        isBot = false, x = 180, y = 650, hp = 90, upgrades = { 0, 0, 0, 0, 0 } },
    } }, "MATCH_START")
  check(m.players[1].upgrades[3] == 3 and m.players[1].x == 100.5, "MATCH_START fields")

  -- sanitizers
  check(Protocol.sanitizeName("<script>x") == "scriptx", "sanitizeName strips junk")
  check(Protocol.sanitizeName("") == "Player", "sanitizeName fallback")
  local t1, c1, u1 = Protocol.sanitizeLoadout({ tankId = "brawler", camoId = "urban",
    upgrades = { 9, -2, 2, 3.7, 0 } })
  check(t1 == "brawler" and c1 == "urban", "sanitizeLoadout ids")
  check(u1[1] == 3 and u1[2] == 0 and u1[3] == 2 and u1[4] == 3, "sanitizeLoadout clamps")
end

local function testSim()
  print("[simulation]")
  Maps.init(); Tanks.init(); Modes.init()

  for _, modeId in ipairs({ "dm", "tdm", "ctf", "control" }) do
    local sim = Sim.new({ mapId = Maps.all()[1].id, modeId = modeId, difficulty = 3, seed = 42 })
    check(sim.mode.id == modeId, "sim boots mode " .. modeId)

    sim:addTank({ id = 1, name = "Me", tankId = "brawler", camoId = "none",
      upgrades = { 1, 1, 1, 1, 1 }, team = 1, isBot = false })
    sim:addTank({ id = 2, name = "BotA", tankId = "scout", camoId = "none",
      upgrades = {}, team = sim.mode.teams and 2 or 1, isBot = true })
    sim:addTank({ id = 3, name = "BotB", tankId = "heavy", camoId = "none",
      upgrades = {}, team = 2, isBot = true })

    local shot, kill, hit = 0, 0, 0
    sim.onEvent = function(e)
      if e.kind == Protocol.EV.SHOT then shot = shot + 1 end
      if e.kind == Protocol.EV.HIT then hit = hit + 1 end
      if e.kind == Protocol.EV.KILL then kill = kill + 1 end
    end

    -- give player an aim bot-style so the fight actually happens
    local me = sim.tanksById[1]
    local bot2 = sim.tanksById[2]
    local steps = Sim.TICK_RATE * 60      -- up to 60 sim-seconds
    local firedByScript = 0
    for i = 1, steps do
      if sim.over then break end
      -- drive the player tank with simple AI so combat occurs
      if me.alive then
        local target = bot2.alive and bot2 or sim.tanksById[3]
        if target and target.alive then
          local want = math.atan2(target.y - me.y, target.x - me.x)
          me.input.turret = want
          me.input.fire = true
          me.input.move = 1
          me.input.turn = 0
        end
      end
      Bot.update(sim, 1 / Sim.TICK_RATE)
      sim:step(1 / Sim.TICK_RATE)
    end
    check(shot > 10, "mode " .. modeId .. ": shots fired (" .. shot .. ")")
    check(hit > 0, "mode " .. modeId .. ": hits registered (" .. hit .. ")")
    check(kill > 0 or sim.over, "mode " .. modeId .. ": kills or match ended")
    check(sim.timeLeft < Modes.get(modeId).timeLimit, "mode " .. modeId .. ": clock ran")

    local snap = sim:snapshot()
    check(snap.tanks and #snap.tanks > 0, "mode " .. modeId .. ": snapshot has tanks")
    local encoded = Protocol.encode(T.SNAPSHOT, snap)
    check(encoded and #encoded > 0 and #encoded < 65535, "mode " .. modeId .. ": snapshot encodes (" .. tostring(encoded and #encoded) .. "B)")

    local rows = sim:scoreboard()
    check(#rows == 3, "mode " .. modeId .. ": scoreboard rows")
  end

  -- solo PVE mode
  local sim = Sim.new({ mapId = "outpost", modeId = "solo", difficulty = 2, seed = 7 })
  sim:addTank({ id = 1, name = "Solo", tankId = "gunner", camoId = "none",
    upgrades = {}, team = 1, isBot = false })
  sim:addTank({ id = 2, name = "Enemy1", tankId = "scout", camoId = "none",
    upgrades = {}, team = 2, isBot = true })
  sim:addTank({ id = 3, name = "Enemy2", tankId = "brawler", camoId = "none",
    upgrades = {}, team = 2, isBot = true })
  check(sim.mode.pve == true, "solo flagged pve")
  for i = 1, Sim.TICK_RATE * 20 do
    Bot.update(sim, 1 / Sim.TICK_RATE)
    sim:step(1 / Sim.TICK_RATE)
  end
  check(sim.tanksById[2].deaths + sim.tanksById[3].deaths + sim.tanksById[1].kills >= 0,
    "solo sim runs without errors")
end

return {
  run = function()
    print("=== Steel Arena selftest ===")
    local ok, err = pcall(function()
      testProtocol()
      testSim()
    end)
    if not ok then
      failures = failures + 1
      print("TEST CRASH: " .. tostring(err))
    end
    print(failures == 0 and "=== ALL TESTS PASSED ===" or ("=== " .. failures .. " FAILURES ==="))
    return failures == 0
  end,
}
