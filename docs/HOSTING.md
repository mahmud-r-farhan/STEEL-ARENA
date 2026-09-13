# STEEL ARENA — Hosting Guide

How to run a server for friends, LAN parties, or the public internet.

## 1. Requirements

- Any PC running Windows/Linux/macOS with LÖVE 11.5 installed
  (or plain Lua 5.1+ / LuaJIT with LuaSocket — no LÖVE needed headless).
- Outbound internet + one inbound **UDP port** (default **37555**).

## 2. Start a server

```bash
# with LÖVE
love src --server

# headless with plain Lua (servers don't need a GPU)
cd src
lua server/bootstrap.lua

# custom port
STEEL_PORT=38000 love src --server
```

You should see:

```
HH:MM:SS Steel Arena server listening on UDP 37555
```

The same machine can host **and** play: just run both — clients connect to `127.0.0.1`.

## 3. LAN party

1. Host: `love src --server` (note the host's LAN IP, e.g. `192.168.1.20`).
2. Players: main menu → SERVER `192.168.1.20` → CONNECT.
3. No router changes needed on a LAN.

## 4. Internet play

1. **Port forward** UDP 37555 on your router to the hosting PC
   (router admin page → NAT/Port Forwarding → protocol **UDP**).
2. Allow the port through the PC firewall (Windows Defender → Inbound Rules).
3. Share your **public IP** (whatismyip) with friends; they type it as SERVER.
4. Optionally change the port with `STEEL_PORT` and share that too.

### Security notes

- The protocol is game-specific binary; there is no shell/FS access from packets.
- Chat is sanitized and rate-limited (0.4 s cooldown), names stripped to `[%w _-]`.
- Loadouts are clamped server-side — hacked clients can't grant stats.
- There is no account auth yet: anyone who can reach the port can play.
  For public servers, run behind a community with rules rather than open internet.

## 5. Server administration

- Logs print to stdout with timestamps (`player X connected`, `room #N match started`,
  `match over, winner=...`).
- Server max rooms: 32 (change `MAX_ROOMS` in `src/server/app.lua`).
- Players time out after 12 s of silence and are removed from rooms;
  host status migrates to the next human in the room.
- Empty rooms auto-destroy.

## 6. Quick test that your server is reachable

From another machine (needs LÖVE):

```bash
love src --selftest   # offline sanity
# then simply connect from the game to the host IP — if the browser shows
# rooms, UDP works both ways.
```

## 7. Troubleshooting

| Symptom | Likely cause |
|---|---|
| "cannot bind UDP 37555" | Port in use — another server running, or set `STEEL_PORT`. |
| Clients see "connection timed out" | Router not forwarding UDP, firewall blocking, or wrong IP. |
| Clients connect but no snapshots | Server tick loop stalled — check for errors in server console. |
| Works on LAN, not internet | ISP CGNAT — use a VPN like Tailscale/ZeroTier with your friends, or rent a VPS. |
