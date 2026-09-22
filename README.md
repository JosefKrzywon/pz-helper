# 🧟 Zomboid Helper

A companion checklist for Project Zomboid (Build 42): track skill books, VHS
tapes and recipe magazines, browse a growing calendar, and note your run's
emergency radio frequency.

![Screenshot](docs/screenshot.png)

## ✨ Features

- **Skill Books** — 24 skills × 5 volumes = 120 books to track, with progress
  indicator, search and sorting (by category or A–Z), plus visible I–V volume
  markers so you can see which volumes you own at a glance
- **Growing Calendar** — plant windows, water needs and frost hardiness with a
  month filter
- **VHS Tapes** — 61 skill-giving tapes (Build 42.19): the skill(s) and base XP
  each grants, recipe unlocks, sortable by skill or by tape/series
- **Recipe Magazines** — all 84 recipe magazines (Build 42.19) grouped by
  category or by name, showing the recipes each one unlocks
- **PZ Wiki links** — skill, crop, tape and magazine names link to their wiki page
- **Emergency Frequency** — note the run's random emergency broadcast frequency
- **Export/Import** for backups, **mobile-optimized** responsive design
- **Cloud sync** between devices (optional, depending on the variant)

All four standalone variants share the same feature set — they differ only in
**how your progress is stored/synced**.

---

## 🚀 Deployment Options

| Option | Sync | Cost | Guide |
|--------|------|------|-------|
| **Local** | Browser only | Free | Just open `index.html` |
| **GitHub Gist** | ✅ Cloud | Free | [Setup Guide](docs/setup-gist.md) |
| **Self-Hosted** | ✅ LAN/Server | Free | [Server Guide](server/) |
| **AWS** | ✅ Cloud + Multi-User | ~$0 (custom domain ~$0.50/mo) | [AWS Guide](aws/) |

The AWS deployment works **with or without a custom domain** — without one it
uses the default CloudFront URL, so no Route53 setup is required.

### Quick Comparison

| Feature | Local | Gist | Self-Hosted | AWS |
|---------|-------|------|-------------|-----|
| No setup needed | ✅ | | | |
| Sync across devices | | ✅ | ✅ | ✅ |
| Multiple users | | | | ✅ |
| Admin panel (users, password reset) | | | | ✅ |
| Custom domain | | | ✅ | optional |
| Password protection | | | ✅ | ✅ |
| Skill Books / Growing Calendar | ✅ | ✅ | ✅ | ✅ |
| VHS Tapes / Recipe Magazines | ✅ | ✅ | ✅ | ✅ |
| Emergency Frequency | ✅ | ✅ | ✅ | ✅ |

---

## 📦 Files

| File | Description |
|------|-------------|
| `index.html` | Local version (localStorage) |
| `index-gist.html` | GitHub Gist sync |
| `index-server.html` | Self-hosted server sync |
| `index-lambda.html` | Standalone cloud sync (Lambda backend) |
| `aws/website/` | AWS version (CloudFront + Lambda + DynamoDB, with login & admin panel) |

All variants share the same feature set (Skill Books, Growing Calendar, VHS
Tapes, Recipe Magazines, Emergency Frequency). They differ only in where your
progress is saved.

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
