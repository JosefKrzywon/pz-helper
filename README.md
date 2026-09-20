# 📚 Project Zomboid Skill Books Checklist

A checklist for all 120 skill books in Project Zomboid (Build 42) — plus a growing calendar for farming.

![Screenshot](docs/screenshot.png)

## ✨ Features

- **24 Skills × 5 Volumes** = 120 books to track
- **Progress indicator** with percentage
- **Search and sorting** (by category or A–Z)
- **Growing calendar** with month filter for Build 42
- **Mobile-optimized** responsive design
- **Export/Import** for local backups
- **Cloud sync** between devices (multiple options)
- **Multi-user support** with admin panel (AWS version)

---

## 🚀 Quick Start

### Option 1: Just Open It (Simplest)

```bash
# Download and open in browser
open index.html
```

Progress is stored in your browser's localStorage. Use Export/Import for backups.

### Option 2: GitHub Pages (Free, Public)

1. Fork this repository
2. Go to Settings → Pages → Enable GitHub Pages
3. Access at `https://YOUR-USERNAME.github.io/pz-skillbooks/`

### Option 3: AWS (Private, Multi-User, Recommended)

Deploy your own password-protected instance:

```
https://zomboid.your-domain.com
```

**Features:**
- Custom domain with HTTPS
- Cookie-based login (no popup)
- Progress synced to cloud
- Multiple users with separate progress
- Admin panel for user management

**Cost:** ~$0.50/month (Route53 only)

→ **[Full AWS Setup Guide](docs/setup-aws.md)**

---

## 📦 All Versions

| Version | File | Sync | Setup | Use Case |
|---------|------|------|-------|----------|
| **Local** | `index.html` | ❌ Browser only | None | Offline, single device |
| **Gist** | `index-gist.html` | ✅ GitHub Gist | 5 min | Free sync, multiple devices |
| **Self-Hosted** | `index-server.html` | ✅ Local JSON | 2 min | Own server, LAN |
| **AWS** | `aws/website/` | ✅ DynamoDB | 15 min | Production, multi-user |

---

## 🏗️ AWS Architecture

```
Internet → Route53 → CloudFront → S3 (Website)
                         ↓
                    Lambda URL → DynamoDB (Users + Progress)
```

| Component | Purpose |
|-----------|---------|
| **CloudFront** | CDN + SSL + Auth routing |
| **CloudFront Function** | Redirect to login if no session |
| **S3** | Static website files |
| **Lambda** | API (login, logout, sync, admin) |
| **DynamoDB** | User accounts + progress data |
| **Route53** | Custom domain DNS |
| **ACM** | Free SSL certificate |

**Monthly Cost:** ~$0.50 (Route53 zone fee only)

---

## 📁 Project Structure

```
pz-skillbooks/
├── index.html                  # Local version (localStorage)
├── index-gist.html             # GitHub Gist sync
├── index-server.html           # Self-hosted server sync
├── README.md
│
├── aws/
│   ├── stack.yaml              # CloudFormation template
│   ├── config.example.sh       # Config template
│   ├── deploy.sh               # Deployment script
│   ├── lambda/
│   │   └── index.mjs           # API Lambda code
│   └── website/
│       ├── index.html          # Main app (with API sync)
│       └── login.html          # Login page
│
├── server/
│   └── server.js               # Node.js server for self-hosting
│
├── docs/
│   ├── setup-aws.md            # AWS guide (detailed!)
│   ├── setup-gist.md           # Gist guide
│   ├── setup-server.md         # Self-hosted guide
│   └── requirements-aws.md     # AWS requirements spec
│
└── .github/
    └── workflows/              # GitHub Actions
```

---

## 🔐 Security

### AWS Version
- **Passwords:** SHA256 hashed with random salt
- **Sessions:** HMAC-signed cookies (1 year validity)
- **Transport:** HTTPS only (CloudFront enforces TLS 1.2+)
- **Data at rest:** DynamoDB encryption enabled (AES-256)
- **S3:** Private bucket, CloudFront OAC access only
- **No credentials stored:** Uses IAM roles, not access keys

### Gist Version
- Token has Gist-only permission, no repo access
- Gist is secret (unlisted, not searchable)
- Token stored in browser localStorage only

### Self-Hosted Version
- Password hashed with bcrypt (10 rounds)
- Data stored locally in JSON files
- Runs behind your firewall

---

## 💰 Cost Breakdown (AWS)

| Service | Free Tier | Expected Cost |
|---------|-----------|---------------|
| Lambda | 1M requests/month | $0.00 |
| DynamoDB | 25 GB storage | $0.00 |
| S3 | 5 GB storage | ~$0.01 |
| CloudFront | 1 TB transfer | ~$0.01 |
| **Route53 Zone** | - | **$0.50** |

**Total: ~$0.50/month** (only if using custom domain)

Without custom domain: practically free!

---

## 🛠️ Development

### Edit Skills

Skills are defined in the `DATA` constant:

```javascript
const DATA = {
  "Crafts (full rate)": [
    "Carpentry", "Cooking", "Electrical", ...
  ],
  "Survival (full rate)": [
    "First Aid", "Fishing", ...
  ],
  "Combat & Firearms (reduced rate)": [
    "Aiming", "Reloading", "Long Blade"
  ]
};
```

### Edit Growing Calendar

Crops are defined in the `CROPS` constant:

```javascript
const CROPS = [
  {n:"Barley", t:"Veg", w:30, d:108, p:"Aug–Oct", bad:"Jun–Jul", best:"Sep", hardy:true},
  // n: name, t: type, w: water%, d: days, p: plant window, bad: bad months, best: optimal, hardy: frost-resistant
  ...
];
```

### Deploy Changes

After editing HTML files:

```bash
# Upload to S3
aws s3 cp aws/website/index.html s3://YOUR-BUCKET/index.html --content-type "text/html; charset=utf-8"

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
```

---

## 🐛 Troubleshooting

### Lambda URL returns 403 Forbidden

Lambda Function URLs need **two** permissions:
1. `lambda:InvokeFunctionUrl` (created by CloudFormation)
2. `lambda:InvokeFunction` (must be added manually!)

```bash
aws lambda add-permission \
  --function-name YOUR_FUNCTION \
  --statement-id FunctionURLInvokeAccess \
  --action lambda:InvokeFunction \
  --principal "*"
```

> This is undocumented AWS behavior. The official docs only mention the first permission.

### Changes not showing

CloudFront caches content. Invalidate after changes:

```bash
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
```

### Login not working

1. Check password hash in DynamoDB
2. Check Lambda logs: `aws logs tail /aws/lambda/YOUR_FUNCTION --follow`
3. Test API directly with curl

→ See [Troubleshooting Guide](docs/setup-aws.md#troubleshooting)

---

## 📜 License

MIT — do whatever you want with it.

---

## 🧟 Good luck surviving!

*"You have a new skill to read."*

---

## 🙏 Credits

- Skill book data: [Project Zomboid Wiki](https://pzwiki.net/)
- Growing calendar: Build 42 in-game data
- Icons: Native emoji
