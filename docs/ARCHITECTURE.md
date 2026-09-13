# STEEL ARENA — Architecture & Developer Guide

How the game is built, why, and how to extend it.

## 1. Big picture

```
┌────────────────────────────  CLIENT (LÖVE)  ────────────────────────────┐
│  states/   menu.main → menu.play → menu.room → battle → results          │
│     │  input @30Hz (move/turn/turret/fire)      ▲ snapshots @30Hz        │
│     ▼                                           │                        │
│  game/client.lua ──► net/transport.lua (UDP) ───┘                        │
│     │ buffers snapshots, interpolates 120ms behind                      │
│     ▼                                                                    │
│  render/world.lua + ui/kit.lua   (battle draw loop)                      │
└──────────────────────────────────────────────────────────────────────────┘
                     ▲ HELLO/ROOM_*/INPUT            │ SNAPSHOT/EVENTS
                     │                               ▼
┌────────────────────────────  SERVER (headless LÖVE or plain Lua)  ───────┐
│  server/app.lua    rooms, invites, quick match, match lifecycle, rewards │
│        │ drives @30Hz:                                                   │
│        ▼                                                                 │
│  game/bot.lua (AI brains) ─► game/sim.lua (authoritative physics/combat) │
└──────────────────────────────────────────────────────────────────────────┘
```

**Solo mode** reuses the exact same `game/sim.lua` but runs it locally inside
`game/client.lua` (`localSim`) — same code path, no server.

## 2. Module map

| Module | Responsibility |
|---|---|
| `core/state.lua` | Screen stack with push/pop (pause menus overlay), input routing |
| `core/save.lua` | Account: credits, XP, owned tanks, upgrades, camos, career stats |
| `core/settings.lua` | Volumes, toggles, callsign; persisted separately from account |
| `core/audio.lua` | Procedural SFX synthesized into SoundData at boot; volume buses |
| `data/tanks.lua` | Tank defs, upgrade parts/prices, camo catalog, `statsFor()` |
| `data/maps.lua` | 4 maps: walls (rects), team/FFA spawns, flags, zones, power-up pads |
| `data/modes.lua` | 5 modes: team layout, score limits, time limits, PvE flag |
| `net/protocol.lua` | Message IDs, binary Writer/Reader, per-message enc/dec, sanitizers |
| `net/transport.lua` | UDP with magic/connId/seq/ackBase header, dedup, timeout kick |
| `game/sim.lua` | Authoritative sim: movement, collisions, bullets, damage, objectives |
| `game/bot.lua` | Difficulty profiles, target scoring, LOS raycasts, state machine |
| `game/client.lua` | Handshake, room ops, snapshot ring + interpolation, local solo host |
| `render/world.lua` | Map draw, tank sprites, particles, shake, minimap |
| `ui/kit.lua` | Immediate-mode widgets; headless-safe graphics stub |
| `server/app.lua` | Rooms, host migration, bot spawning, rewards, flood guard |
| `states/*` | Screens: menu, browser, room, store, garage, settings, battle |

## 3. Wire protocol

Every packet: `magic(2) connId(2) seq(2) ackBase(2) payload` — 8-byte header.

Payload starts with a `u8` message type. Numbers are quantized: positions are
`u16 = value*10` (0.1 precision), angles `u16 = radians*1000`. Strings are `len+bytes` (max 255).

Key messages (both sides validated):

| ID | Name | Direction | Purpose |
|---|---|---|---|
| 1 | HELLO | C→S | name+tank+camo+upgrades+version; server assigns playerId |
| 2 | INPUT | C→S | seq, move(-1/0/1), turn, turret angle, fire bit |
| 4 | LOBBY_LIST | C→S/S→C | room browser |
| 5/6 | ROOM_CREATE/JOIN | C→S | host/join with password |
| 9/10 | INVITE_SEND/ACCEPT | C→S | lobby invite flow |
| 11/12 | SET_LOADOUT / SET_READY | C→S | garage sync / ready flag |
| 15 | QUICK_MATCH | C→S | auto-join or create room |
| 19 | LOBBY_PLAYERS | C→S/S→C | directory of roomless players (invite UI) |
| 64 | WELCOME | S→C | playerId + motd |
| 66 | ROOM_STATE | S→C | full room roster/config; broadcast on any change |
| 71 | MATCH_START | S→C | map, mode, seed, roster with spawn positions |
| 72 | SNAPSHOT | S→C | per-tank state + K/D + bullets + events + mode state |
| 73 | MATCH_END | S→C | winner + scoreboard + XP/CR rewards |

**Server-side validation**: `Protocol.sanitizeLoadout/sanitizeName/sanitizeChat`
clamp every client-provided value. Upgrade levels are clamped 0–3 regardless of
what the client claims; unknown tank ids fall back to scout.

## 4. The 30 Hz tick loop

Server (`server/app.lua`):

```
accumulate real dt → when >= 1/30:
    Bot.update(sim, step)      -- AI decides inputs
    sim:step(step)             -- physics/combat/objectives
    snap = sim:snapshot()      -- + drains event queue
    broadcast to room conns
```

Clients render ~120 ms in the past by interpolating the two snapshots around
`now - 0.12` (see `game/client.lua:renderState`). Bullets are drawn raw (fast movers
interpolate poorly at low snapshot rates).

## 5. Simulation rules worth knowing

- **Movement**: accel `900`, friction `700`, per-tank clamp; walls are resolved by
  circle-vs-rect pushout; tank/tank is symmetric soft pushout.
- **Turret**: shortest-arc tracking with per-tank traverse limit; bots lead shots with
  `eta = dist/bulletSpeed * profile.lead`.
- **Bullets**: substep raycasts (`10px` steps) vs walls and tanks; MG tracers differ
  visually from cannon shells; friendly fire **off** in team modes.
- **Overheat**: Hornet's autocannon locks after 14 consecutive rounds (~1.2 s penalty).
- **Flags**: capture requires *your flag at home*; dropped flags auto-return after 10 s.
- **Zones**: 3 s uncontested capture; +1 pt/s per zone toward 300.
- **Respawn**: 3 s wait, 2 s invulnerability, spawn point chosen farthest from living enemies.
- **Power-ups**: pads cycle kinds deterministically from the match seed; 12–18 s respawn.

## 6. Economy

| Event | Reward |
|---|---|
| Battle | 40 CR + 22/kill + 120 win + dmg/40 |
| XP | 30 + 12/kill + 60 win |

Level N costs `100*N` cumulative XP. Server computes rewards; the local solo host
applies the same formula (see `Client:finishLocalMatch`).

## 7. Extension recipes

**Add a tank** — `data/tanks.lua`: add a definition (stats + colors), the catalog and
pricing update automatically. Add its silhouette tweak in `render/world.lua:drawTank`
if you want a unique barrel.

**Add a map** — `data/maps.lua`: define walls/spawns/flags/points/powerups following the
existing shape; it appears in every picker automatically. Keep rects axis-aligned.

**Add a mode** — `data/modes.lua` definition + `game/sim.lua` objective logic in
`updateZones/updateFlags` style + win condition in `checkWin()` + snapshot fields if needed.

**Add a power-up** — `game/sim.lua` `POWERUPS` table + effect in `applyPowerup()` +
snapshot flag bit + render marker in `render/world.lua`.

**Change tick rate** — `Sim.TICK_RATE` drives server cadence and client send rate.
20 Hz saves bandwidth; 40 Hz feels snappier. The 8-byte header + ~100 B snapshots are
already tiny.

## 8. Testing strategy

| Command | Verifies |
|---|---|
| `love src --selftest` | all 22 modules load (also headless without love.graphics), protocol roundtrips consume exact bytes, bots fight and finish matches in every mode |
| `love src --nettest` | real UDP server+client: handshake → room → loadout → ready → chat → start → snapshot stream (17k+ snapshots in CI run) |
| `love src --smoke` | windowed boot: menu renders + updates 3 s, clean quit |

The module-load check is the highest-value test: it catches syntax errors, Lua 5.1
incompatibilities (e.g. `//` operator) and require-path mistakes across the whole tree.

## 9. Known limitations

- Reliability layer tracks seqs but resends are not implemented (chat/lobby are
  idempotent; snapshots are fire-and-forget by design).
- No NAT traversal / relay; hosting requires a reachable UDP port.
- Interpolation hides up to ~130 ms; higher-latency players will want lag compensation
  for snipers before competitive play.
- Local solo applies rewards with the same formula as the server but is client-trusted
  (fine for PvE; keep it that way).
