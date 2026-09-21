# 📚 PZ Skill Books Checklist

A checklist for all 120 skill books in Project Zomboid (Build 42) — plus a growing calendar for farming.

![Screenshot](docs/screenshot.png)

## ✨ Features

- **24 Skills × 5 Volumes** = 120 books to track
- **Progress indicator** with percentage
- **Search and sorting** (by category or A–Z)
- **Growing calendar** with month filter
- **Mobile-optimized** responsive design
- **Export/Import** for backups
- **Cloud sync** between devices (optional)

---

## 🚀 Deployment Options

| Option | Sync | Cost | Guide |
|--------|------|------|-------|
| **Local** | Browser only | Free | Just open `index.html` |
| **GitHub Gist** | ✅ Cloud | Free | [Setup Guide](docs/setup-gist.md) |
| **Self-Hosted** | ✅ LAN/Server | Free | [Server Guide](server/) |
| **AWS** | ✅ Cloud + Multi-User | ~$0.50/mo | [AWS Guide](aws/) |

### Quick Comparison

| Feature | Local | Gist | Self-Hosted | AWS |
|---------|-------|------|-------------|-----|
| No setup needed | ✅ | | | |
| Sync across devices | | ✅ | ✅ | ✅ |
| Multiple users | | | | ✅ |
| Admin panel | | | | ✅ |
| Custom domain | | | ✅ | ✅ |
| Password protection | | | ✅ | ✅ |

---

## 📦 Files

| File | Description |
|------|-------------|
| `index.html` | Local version (localStorage) |
| `index-gist.html` | GitHub Gist sync |
| `index-server.html` | Self-hosted server |
| `aws/website/` | AWS version |

---

## 🔐 Security

| Version | Auth Method | Password Storage |
|---------|-------------|------------------|
| **Local** | None | N/A |
| **Gist** | GitHub Token | Browser localStorage |
| **Self-Hosted** | HTTP Basic Auth | Plaintext comparison |
| **AWS** | Cookie-based sessions | SHA256 + salt in DynamoDB |

The AWS version is the most secure option with proper password hashing and encrypted transport.

---

## 💰 Costs

All versions are free except AWS with a custom domain:

| Version | Monthly Cost |
|---------|--------------|
| Local | $0 |
| GitHub Gist | $0 |
| Self-Hosted | $0 |
| AWS (CloudFront URL) | ~$0 |
| **AWS (custom domain)** | **~$0.50** |

---

## 🛠️ Development

Want to customize skills, crops, or contribute?

→ **[Development Guide](docs/DEVELOPMENT.md)**

---

## 📜 License

MIT — do whatever you want with it.

---

## 🧟 Good luck surviving!

*"You have a new skill to read."*

---

## Credits

- Skill book data: [Project Zomboid Wiki](https://pzwiki.net/)
- Growing calendar: Build 42 in-game data
