# STEEL ARENA — 2D Tank Battle

A fast top-down multiplayer tank shooter built in **Lua** on the [LÖVE 2D](https://love2d.org) framework.
Internet play with an authoritative UDP server, persistent progression, five game modes and 12-player rooms.

![status](https://img.shields.io/badge/tests-passing-brightgreen) ![love](https://img.shields.io/badge/L%C3%96VE-11.5-blue)

## Features

| Area | What you get |
|---|---|
| **Multiplayer** | Authoritative UDP server, 2–12 players per room, quick match, password rooms, invites, in-game chat |
| **Solo (PvE)** | Instant offline battle vs AI tanks with configurable enemies, allies, difficulty and map |
| **Game modes** | Deathmatch, Team Deathmatch, Capture the Flag, Control Points, Solo Assault |
| **Tanks** | 5 classes — Scorpion (light), Hornet (MG), Rampart (medium), Longshot (sniper), Bastion (heavy) |
| **Progression** | Credits + XP from battles, 5-part upgrade tree (3 levels each), 5 camouflages, persistent account |
| **Combat feel** | Turret traversal, reload bars, hit markers, damage numbers, ricochets, power-ups (repair/shield/rapid/HE/nitro), screen shake |
| **Maps** | 4 handcrafted arenas: Outpost, Dunes, Foundry, Fortress |

## Quick start

1. **Install LÖVE 11.5** → https://love2d.org (or let the dev script fetch it — see `tools/fetch-love.sh`).
2. **Play solo right away**

   ```bash
   love src
   ```

   Click **SOLO ASSAULT (PvE)** → pick map/enemies/difficulty → **DEPLOY**.
3. **Play online (same PC test)**

   ```bash
   # terminal 1 — server
   love src --server
   # terminal 2 — client
   love src        # CONNECT to 127.0.0.1 → MULTIPLAYER LOBBY
   ```

4. **Play online (friends over the internet)**

   - Host runs `love src --server` and forwards **UDP port 37555** to their machine.
   - Friends enter the host's public IP in the main menu and CONNECT.

> Windows tip: `love src` means running `C:\path\to\love.exe` with the project's `src` folder.
> See **docs/PLAYER_MANUAL.md** for the full walkthrough.

## Controls

| Input | Action |
|---|---|
| **W / S** or **↑ / ↓** | Drive forward / reverse |
| **A / D** or **← / →** | Rotate hull |
| **Mouse** | Aim turret |
| **Left click / Space** | Fire |
| **Mouse wheel** | Zoom camera |
| **TAB** (hold) | Scoreboard |
| **ENTER** | Chat (battles + room lobby) |
| **ESC** | Pause / back |

## Testing

The project ships with three self-verification modes (no display needed for the first two):

```bash
love src --selftest   # 90+ checks: all modules, protocol roundtrips, AI battles in every mode
love src --nettest    # end-to-end: real server+client over UDP, full room flow, snapshot stream
love src --smoke      # windowed: boots the menu, renders and updates for 3 seconds
```

`--selftest` and `--nettest` exit `0` on success — wire them into CI directly.

## Project layout

```
src/
  main.lua            entry point (+ --server / --selftest / --nettest / --smoke flags)
  conf.lua            LÖVE boot config, headless detection
  core/               state machine, save/settings persistence, audio synth, tests
  data/               tanks, upgrade parts, camos, maps, game modes
  net/                binary protocol (encode/decode), UDP transport
  game/               authoritative sim, bot AI, client net layer
  render/             world renderer (map, tanks, fx, minimap)
  server/             dedicated server app (rooms, invites, quick match)
  states/             menu/battle screens
docs/                 player manual, architecture, hosting guide
```

## Design notes

- **Authoritative server**: clients send 30 Hz input packets; the server simulates physics/combat and broadcasts snapshots. Loadouts are sanitized server-side (anti-cheat).
- **Compact wire format**: fixed-point positions/angles (u16), per-message encoders — a full 12-tank snapshot is ~100 bytes.
- **Zero external assets**: all sound effects are procedurally synthesized at boot; all visuals are drawn with primitives. Clone-and-run with no downloads beyond LÖVE itself.

## Roadmap

- Reconnect grace period on server-side disconnects
- Ranked ladder + seasonal rewards
- Map editor + workshop sharing
- Replay playback from snapshot logs
- Steam packaging via `love.js`/electron alternatives

## License

MIT — see `LICENSE`.
