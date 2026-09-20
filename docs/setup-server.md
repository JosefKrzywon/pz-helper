# Setup: Self-Hosted Server

Run your own password-protected server on your local machine, NAS, or VPS.

## Features

- Simple Node.js server (no dependencies!)
- Basic Auth protection
- Progress stored as JSON file
- Works on any platform with Node.js

## Prerequisites

- Node.js 18+ installed

## Quick Start

```bash
cd server
PASSWORD=yourpassword node server.js
```

Then open http://localhost:3000 in your browser.

Login with:
- **Username:** `admin`
- **Password:** the password you set

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `PORT` | 3000 | Server port |
| `USERNAME` | admin | Basic auth username |
| `PASSWORD` | (required) | Basic auth password |
| `DATA_DIR` | ./data | Directory for progress files |

### Examples

```bash
# Custom port and username
PORT=8080 USERNAME=josef PASSWORD=secret node server.js

# Custom data directory
DATA_DIR=/path/to/data PASSWORD=secret node server.js
```

## Running as a Service

### Linux (systemd)

Create `/etc/systemd/system/pz-helper.service`:

```ini
[Unit]
Description=PZ Helper Server
After=network.target

[Service]
Type=simple
User=youruser
WorkingDirectory=/path/to/pz-helper/server
Environment=PASSWORD=yourpassword
ExecStart=/usr/bin/node server.js
Restart=always

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl enable pz-helper
sudo systemctl start pz-helper
```

### Docker

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY server/ ./server/
COPY index-server.html ./
EXPOSE 3000
CMD ["node", "server/server.js"]
```

```bash
docker build -t pz-helper .
docker run -d -p 3000:3000 -e PASSWORD=secret -v pz-data:/app/server/data pz-helper
```

### Windows (Task Scheduler)

1. Create a batch file `start-server.bat`:
   ```batch
   @echo off
   cd /d "C:\path\to\pz-helper\server"
   set PASSWORD=yourpassword
   node server.js
   ```

2. Open Task Scheduler → Create Task
3. Trigger: At startup
4. Action: Start program → select `start-server.bat`

## Reverse Proxy (HTTPS)

For secure access over the internet, put nginx or Caddy in front:

### Caddy (automatic HTTPS)

```
pz.example.com {
    reverse_proxy localhost:3000
}
```

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

## Data Backup

Progress is stored in `server/data/progress_<username>.json`.

Backup this file to preserve your progress.

## Troubleshooting

### "PASSWORD environment variable is required"

You must set a password:
```bash
PASSWORD=yourpassword node server.js
```

### "EADDRINUSE: address already in use"

Port is already used. Change it:
```bash
PORT=3001 PASSWORD=secret node server.js
```

### Browser asks for password repeatedly

- Check username/password (case-sensitive)
- Clear browser cache
- Try incognito mode
