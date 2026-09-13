# STEEL ARENA — Player Manual

Everything you need to go from first launch to online victory.

## 1. Starting the game

Run `love src` (or double-click the game if packaged). The **main menu** shows your
profile level and credits on the right panel.

### First launch checklist
1. Type a **callsign** (2–16 characters) in the left panel.
2. Leave the server as `127.0.0.1` for solo play, or enter a friend's server IP.
3. Press **CONNECT** only when you want to play multiplayer — solo works offline.

Your callsign, credits, tanks and upgrades are saved automatically
(`%APPDATA%/LOVE/steel_arena/` on Windows).

## 2. Game modes

| Mode | Teams | How to win |
|---|---|---|
| **Deathmatch** | No | First player to 15 kills |
| **Team Deathmatch** | Blue vs Red | First team to 25 kills |
| **Capture the Flag** | Blue vs Red | Steal the enemy flag, carry it to your base while your own flag is home — 3 captures |
| **Control Points** | Blue vs Red | Hold zones to gain points per second — 300 points |
| **Solo Assault** | You (+ally bots) vs enemy bots | Destroy the enemy force; enemy waves keep pressure via respawns |

## 3. The Store

Open **STORE** from the main menu.

- **Tanks tab** — five hulls, from the 1500-CR starter Scorpion to the 6000-CR Bastion heavy.
  Buying a tank makes it yours forever; press **EQUIP** to make it your loadout.
- **Camouflage tab** — pick a tank you own, then buy/equip paints (Desert, Arctic, Urban,
  Crimson). Cosmetics are per-tank.

Earning credits: every battle pays 40 CR base + 22 per kill + 120 win bonus + damage bonus.
Winning also grants bonus XP; levels cost 100 XP each (a bit more each level).

## 4. The Garage

Open **GARAGE** to tune your tank. Select any tank you own on the left.

Five upgrade parts, three levels each:

| Part | Effect per level |
|---|---|
| Engine | +10 % top speed |
| Armor | +12 % hit points |
| Auto-loader | −8 % reload time |
| Main gun | +8 % shell damage |
| Optics | +12 % turret traverse |

Prices scale with the tank's tier. Stat bars update live — the **DPS** bar is a good
cross-tank comparison. Changes sync to the server automatically (visible in the room lobby).

## 5. Multiplayer flow

1. **CONNECT** on the main menu.
2. **MULTIPLAYER LOBBY** opens the browser.
3. Either:
   - **QUICK MATCH** → pick a mode → you are placed into an open room (or a new one is created),
   - **CREATE ROOM** → choose mode, map, max players, bots, bot skill, optional password,
   - or click a room in the list → **JOIN** (enter the password if prompted).
4. In the **room lobby**:
   - READY UP when your loadout is final.
   - Hosts can change mode/map/bots/skill anytime, and kick players.
   - INVITE lists everyone currently connected to the server without a room — one click sends them an invite.
5. Host presses **START BATTLE**. Rooms need 2+ players **or bots** to start.

## 6. Battle basics

- **Driving**: tanks accelerate and slide a little; walls and other tanks block you.
- **Aiming**: the turret follows your mouse at the tank's traverse speed — flanking beats tracking.
- **Firing**: cannons have a reload bar (bottom-left); the Hornet's autocannon
  overheats after a long burst — ease off to cool it.
- **Power-ups** spawn on glowing pads: Repair Kit, Shield Cell (−50 % damage taken),
  Rapid Fire, HE Shells (+50 % damage), Nitro (+45 % speed). Each lasts 25 s.
- **Spawning**: destroyed tanks respawn after 3 s with 2 s of invulnerability (shimmering ring).
- **Bullets do not hurt teammates** in team modes — use them as cover.

### HUD reference
- Top center: score/clock.
- Bottom left: HP and reload bars, active power-up icons.
- Bottom right: minimap (objectives, teammates, enemies).
- Top right: killfeed.
- Crosshair turns into a red **hit marker** when your shells connect.

## 7. Settings

Audio volumes (master/effects/music), FPS counter, screen shake, callsign, career stats,
and WIPE SAVE (starts a fresh account). Settings apply instantly and persist.

## 8. Keyboard shortcuts in battle

| Key | Action |
|---|---|
| TAB | Hold to show scoreboard |
| ENTER | Open/close chat |
| ESC | Pause menu (resume / settings / leave) |
| Mouse wheel | Zoom |

## 9. Troubleshooting

| Problem | Fix |
|---|---|
| "LuaSocket not available" | Your LÖVE build lacks socket support — use the official 11.5 package. |
| Can't connect | Check the host IP, and that UDP **37555** is open (host side) and not blocked by firewall/VPN. |
| "need 2 players (or add bots)" | Rooms can start with bots: host sets BOTS ≥ 1, or invite friends. |
| Sound but no enemies in solo | Increase ENEMIES in the solo setup panel; enemy count 1–10. |
| Save seems lost | The save lives in the LOVE save dir; do not change `t.identity` in `conf.lua`. |
