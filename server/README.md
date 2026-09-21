# Self-Hosted Server

Run your own password-protected server on your local machine, NAS, or VPS.

**What you get:**
- Simple Node.js server (no external dependencies)
- HTTP Basic Auth protection
- Progress stored as a JSON file on disk
- Works on any platform with Node.js

**Cost:** Free

---

## Prerequisites

### Node.js 18+

The server uses ES modules, which require Node.js 18 or newer.

```bash
node --version
# Should show v18.x.x or higher
```

**Not installed?**
- **Windows/macOS:** [Download from nodejs.org](https://nodejs.org/)
- **Linux:** `sudo apt install nodejs` or use [nvm](https://github.com/nvm-sh/nvm)

---

## Quick Start

```bash
cd server
PASSWORD=your-secret-password node server.js
```

Open http://localhost:3000 and log in with:
- **Username:** `admin`
- **Password:** the password you set above

That's it! Your progress is saved in `server/data/progress_admin.json`.

---

## Configuration

All settings are via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3000` | Server port |
| `USERNAME` | `admin` | Basic Auth username |
| `PASSWORD` | *(required)* | Basic Auth password |
| `DATA_DIR` | `./data` | Directory for progress files |

### Examples

```bash
# Custom port and username
PORT=8080 USERNAME=zombie PASSWORD=secret node server.js

# Custom data directory
DATA_DIR=/mnt/nas/pz-data PASSWORD=secret node server.js
```

---

## Running as a Service

### Linux (systemd)

1. Create `/etc/systemd/system/pz-helper.service`:

```ini
[Unit]
Description=PZ Skill Books Server
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/pz-helper/server
Environment=PASSWORD=your-secret-password
ExecStart=/usr/bin/node server.js
Restart=always

[Install]
WantedBy=multi-user.target
```

2. Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable pz-helper
sudo systemctl start pz-helper
```

3. Check status:

```bash
sudo systemctl status pz-helper
```

### Docker

1. Create `Dockerfile` in repo root:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY server/ ./server/
COPY index-server.html ./
EXPOSE 3000
CMD ["node", "server/server.js"]
```

2. Build and run:

```bash
docker build -t pz-helper .
docker run -d \
  -p 3000:3000 \
  -e PASSWORD=your-secret-password \
  -v pz-data:/app/server/data \
  pz-helper
```

### Windows (Task Scheduler)

1. Create `start-server.bat`:

```batch
@echo off
cd /d "C:\path\to\pz-helper\server"
set PASSWORD=your-secret-password
node server.js
```

2. Task Scheduler → Create Task → Trigger: At startup → Action: Start `start-server.bat`

---

## HTTPS with Reverse Proxy

The server runs HTTP by default, which is fine on a trusted LAN. For internet access, put a reverse proxy in front for HTTPS.

### Caddy (easiest — automatic HTTPS)

```
pz.example.com {
    reverse_proxy localhost:3000
}
```

Caddy automatically obtains and renews SSL certificates.

### nginx

```nginx
server {
    listen 443 ssl;
    server_name pz.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Security Notes

⚠️ **Important:** This version uses HTTP Basic Auth. The password is:
- Sent with every request (Base64-encoded, not encrypted)
- Compared in plaintext on the server (no hashing)

**Recommendations:**
- Use a unique password you don't use elsewhere
- Run over HTTPS if accessible from the internet
- Keep it on a trusted LAN if possible

For a more secure setup with hashed passwords and cookie-based sessions, use the [AWS version](../aws/README.md).

---

## Data & Backup

Progress is stored in:
```
server/data/progress_<username>.json
```

Back up this file (or the whole `data/` directory) to preserve your progress.

---

## Troubleshooting

### "PASSWORD environment variable is required"

Set a password:
```bash
PASSWORD=secret node server.js
```

### "EADDRINUSE: address already in use"

Port 3000 is taken. Use a different port:
```bash
PORT=3001 PASSWORD=secret node server.js
```

### Browser keeps asking for password

- Check username and password (case-sensitive)
- Clear browser cache or try incognito mode
- Make sure you're using the correct URL

---

## API

The server exposes one endpoint:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/progress` | GET | Load progress |
| `/api/progress` | POST | Save progress |

All requests require Basic Auth.
