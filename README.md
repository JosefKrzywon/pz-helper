# 📚 Project Zomboid Skill Books Checklist

A checklist for all 120 skill books in Project Zomboid (Build 42) — plus a growing calendar for farming.

**Features:**
- 24 Skills × 5 Volumes = 120 books to check off
- Progress indicator
- Search and sorting (by category or A–Z)
- Growing calendar with month filter
- Mobile-optimized
- Export/Import for backups
- Optional: Cloud sync between devices

---

## 📦 Three Versions

| Version | File | Sync | Setup | For whom |
|---------|------|------|-------|----------|
| **Local** | `index.html` | ❌ Export/Import | None | One device, offline |
| **Gist** | `index-gist.html` | ✅ GitHub Gist | 5 min | Multiple devices, free |
| **AWS** | `index-lambda.html` | ✅ S3 + Lambda | 15 min | Own infrastructure |

---

## 🚀 Quick Start

### Version 1: Local (Simplest)

```bash
# Just open in browser
open index.html
```

- Progress is stored in browser (localStorage)
- **Export/Import** buttons for backups and device transfers
- No internet connection required

### Version 2: GitHub Gist Sync

1. [Create Personal Access Token](https://github.com/settings/tokens?type=beta) (Gist permission only)
2. Open `index-gist.html`
3. Enter token → Gist is created automatically
4. On other devices: Enter token + Gist ID

**Cost:** $0

→ [Detailed Guide](docs/setup-gist.md)

### Version 3: AWS Lambda Sync

```bash
cd aws
./deploy.sh           # Deploy sync backend
./deploy.sh website   # Optional: Host website on your own domain
```

**Cost:** ~$0.50/month (Route53 only)

→ [Detailed Guide](docs/setup-aws.md)

---

## 💰 AWS Costs (without Free Tier)

Realistic costs at normal usage (one user, a few requests per day):

| Service | Price | Your Usage | Cost/Month |
|---------|-------|------------|------------|
| S3 Storage | $0.023/GB | ~10 KB | < $0.01 |
| S3 Requests | $0.0004/1000 | ~500 | < $0.01 |
| Lambda Requests | $0.20/1 million | ~500 | < $0.01 |
| Lambda Compute | $0.0000167/GB-s | ~50 GB-s | < $0.01 |
| CloudFront Requests | $0.01/10,000 | ~1,000 | < $0.01 |
| CloudFront Transfer | $0.085/GB | ~10 MB | < $0.01 |
| **Route53 Zone** | **$0.50/month** | 1 Zone | **$0.50** |
| Route53 Queries | $0.40/1 million | ~1,000 | < $0.01 |

**Total Cost: ~$0.50/month**

The Route53 Hosted Zone is the only significant cost factor. Everything else adds up to a few cents.

Even at 100x more usage you'll stay under $1/month.

---

## 🌐 Hosting Options

### Local / Offline
All versions work as local files (`file://`).

### GitHub Pages (recommended, free)
1. Fork the repository
2. Settings → Pages → Source: "Deploy from branch" → `main`
3. Optional: Configure custom domain

### AWS CloudFront (own domain, HTTPS)
```bash
cd aws
./create-certificate.sh zomboid.example.com Z1234567890ABC
# Enter Certificate ARN in deploy.sh
./deploy.sh website
```

→ [GitHub Actions Setup](docs/setup-github-actions.md) for automatic deployments

---

## 📁 Project Structure

```
pz-skillbooks/
├── index.html              # Version 1: localStorage + Export/Import
├── index-gist.html         # Version 2: GitHub Gist Sync
├── index-lambda.html       # Version 3: AWS Lambda Sync
├── README.md
│
├── docs/
│   ├── setup-gist.md           # Gist guide
│   ├── setup-aws.md            # AWS guide
│   └── setup-github-actions.md # CI/CD guide
│
├── aws/
│   ├── stack.yaml              # CloudFormation: Lambda + S3
│   ├── website-stack.yaml      # CloudFormation: CloudFront + S3
│   ├── deploy.sh               # Deployment script
│   ├── set-password.sh         # Change password
│   ├── create-certificate.sh   # Create ACM certificate
│   └── lambda/
│       └── index.mjs           # Lambda code
│
└── .github/
    └── workflows/
        ├── deploy-website.yml  # Auto-deploy on HTML changes
        └── deploy-sync.yml     # Manual Lambda deployment
```

---

## 🛠️ Customization

### Edit Skills
The skill data is in the `DATA` constant at the beginning of the `<script>` block:

```javascript
const DATA = {
  "Crafts (full rate)": [
    "Carpentry", "Cooking", ...
  ],
  ...
};
```

### Edit Crops
The growing calendar is in the `CROPS` constant:

```javascript
const CROPS = [
  {n:"Barley", t:"Veg", w:30, d:108, p:"Aug–Oct", ...},
  ...
];
```

---

## 🔒 Security

### Gist Version
- Token has Gist permission only, no repo access
- Gist is private (only you can see it)
- Token is stored locally in browser only

### AWS Version
- Password is stored as PBKDF2 hash (100,000 iterations)
- Transmission only via HTTPS (Lambda Function URL enforces TLS)
- S3 bucket is private and encrypted (AES-256)
- No long-lived credentials — GitHub Actions uses OIDC

---

## 📜 License

MIT — do whatever you want with it.

---

## 🧟 Good luck surviving!

*"You have a new skill to read."*
