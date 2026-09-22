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
| **Local** | Browser only | Free | See below |
| **GitHub Gist** | ✅ Cloud | Free | [Setup Guide](docs/setup-gist.md) |
| **Self-Hosted** | ✅ LAN/Server | Free | [Server Guide](server/) |
| **AWS** | ✅ Cloud + Multi-User | See warning below | [AWS Guide](aws/) |

---

## 💾 Local Version (Easiest)

The local version stores your progress in your browser. No internet, no account, no setup — just a single HTML file.

### How to use

1. **Download** the file `zomboid-helper-local.html` to your computer (or phone)
2. **Open** it in any web browser (Chrome, Firefox, Edge, Safari...)
   - **Windows/Mac:** Double-click the file, or drag it into your browser
   - **Android:** Use a file manager app, tap the file, choose "Open with" → your browser
   - **iPhone/iPad:** Save to Files app, tap to open, or use a browser like Safari
3. **Done!** Your progress is saved automatically in your browser

### Good to know

- ✅ Works completely offline
- ✅ No account or password needed
- ⚠️ Progress is stored in your browser — if you clear browser data, it's gone
- ⚠️ Doesn't sync between devices (use Gist or AWS version for that)
- 💡 **Tip:** Bookmark the file for quick access

---

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
| `zomboid-helper-local.html` | Local version (localStorage) — **start here!** |
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

The **AWS version** is the most secure option with:
- HMAC-signed session cookies with timing-safe verification
- SHA256 + salt password hashing
- Security headers (CSP, HSTS, X-Frame-Options, etc.)
- Optional `robots.txt` to block search engines

---

## 💰 Costs

| Version | Monthly Cost |
|---------|--------------|
| Local | $0 |
| GitHub Gist | $0 |
| Self-Hosted | $0 |

### ⚠️ AWS Warning

> **The AWS option is for experienced users only.**
> 
> AWS can generate **significant unexpected costs** if misconfigured or abused (DDoS, traffic spikes, forgotten resources). While the deployment includes cost protection (budget alerts, auto-disable), **you are responsible for monitoring your AWS bill**.

**AWS Costs breakdown:**

| Scenario | Cost |
|----------|------|
| Without custom domain | ~$0/month (Free Tier covers it) |
| With existing Route53 zone | ~$0.50/month (zone hosting fee) |
| **Registering a new domain** | **$12–50/year** (depends on TLD) + $0.50/month zone fee |

If you don't already have an AWS account and domain, consider the **Gist** or **Self-Hosted** options instead — they're free and much simpler.

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
