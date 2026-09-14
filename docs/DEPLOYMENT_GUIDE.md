# STEEL ARENA — Production Deployment & Server Operations Guide

This guide details hosting dedicated authoritative servers for Steel Arena, running Docker containers, systemd service setup, firewall configuration, and operational monitoring.

---

## 1. Dedicated Server Architecture

The Steel Arena server (`server/app.lua`) runs headlessly without graphics or audio modules. It handles:
- Room lifecycle & lobby directory
- Password protection & room management
- Authoritative 30 Hz simulation (movement, hit detection, objectives)
- Client input validation and loadout anti-cheat sanitization
- Periodic binary snapshot broadcasts to connected clients

---

## 2. Server Requirements

- **OS**: Linux (Ubuntu 22.04/24.04, Debian 11/12, Alpine), macOS, or Windows Server.
- **Runtime**: LÖVE 11.5 or standalone Lua 5.1/LuaJIT + LuaSocket.
- **Network**: Inbound UDP port `37555` (default).

---

## 3. Launching the Server

### Direct Execution
```bash
love src --server
```

### Custom Port & Bind Options
```bash
STEEL_PORT=38000 love src --server
```

---

## 4. Docker Container Deployment

### Containerizing the Server

Create a `Dockerfile`:
```dockerfile
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    love \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY src/ /app/src/

EXPOSE 37555/udp

ENTRYPOINT ["love", "src", "--server"]
```

### Building & Running

```bash
# Build image
docker build -t steel-arena-server .

# Run container (UDP port mapping is required)
docker run -d \
  --name steel-server \
  -p 37555:37555/udp \
  --restart unless-stopped \
  steel-arena-server
```

---

## 5. Linux Systemd Service Setup

Create `/etc/systemd/system/steel-arena.service`:

```ini
[Unit]
Description=Steel Arena Dedicated Server
After=network.target

[Service]
Type=simple
User=game-server
WorkingDirectory=/opt/steel-arena
ExecStart=/usr/bin/love /opt/steel-arena/src --server
Restart=always
RestartSec=5
Environment=STEEL_PORT=37555

[Install]
WantedBy=multi-user.target
```

Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable steel-arena
sudo systemctl start steel-arena
sudo systemctl status steel-arena
```

---

## 6. Firewall & Network Setup

### UFW (Ubuntu/Debian)
```bash
sudo ufw allow 37555/udp comment 'Steel Arena Dedicated Server'
sudo ufw reload
```

### iptables
```bash
sudo iptables -A INPUT -p udp --dport 37555 -j ACCEPT
```

---

## 7. Performance & Security Best Practices

1. **Security & Sanitization**:
   - The server validates all incoming packets (`net/protocol.lua`).
   - Player names and chat messages are sanitized and rate-limited.
   - Loadout stats are sanitized server-side; clients cannot alter hit points, damage, or speeds beyond standard upgrade trees.
2. **Monitoring**:
   - Inspect live logs with `journalctl -u steel-arena -f` or `docker logs -f steel-server`.
   - Rooms auto-destroy when empty; inactive players time out after 12 seconds.
