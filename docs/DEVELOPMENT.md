# Development Guide

How to customize the skill list, growing calendar, and contribute to the project.

---

## Project Structure

```
pz-helper/
├── index.html              # Local version (localStorage only)
├── index-gist.html         # GitHub Gist sync version
├── index-server.html       # Self-hosted server version
│
├── aws/
│   ├── website/
│   │   ├── index.html      # AWS version (main app)
│   │   └── login.html      # AWS login page
│   ├── lambda/
│   │   └── index.mjs       # API backend
│   └── stack.yaml          # CloudFormation template
│
└── server/
    └── server.js           # Self-hosted Node.js server
```

**Important:** There are multiple `index.html` files! Make sure you edit the right one:

| File | Use Case |
|------|----------|
| `/index.html` | Local/offline use |
| `/index-gist.html` | GitHub Gist sync |
| `/index-server.html` | Self-hosted server |
| `/aws/website/index.html` | AWS deployment |

---

## Customizing Skills

Skills are defined in the `DATA` constant near the top of the `<script>` section:

```javascript
const DATA = {
  "Crafts (full rate)": [
    "Carpentry", "Cooking", "Electrical", "Welding", "Mechanics",
    "Tailoring", "Blacksmithing", "Carving", "Knapping", "Glassmaking",
    "Masonry", "Pottery"
  ],
  "Survival (full rate)": [
    "First Aid", "Fishing", "Trapping", "Foraging", "Tracking",
    "Agriculture", "Animal Care", "Butchering", "Maintenance"
  ],
  "Combat & Firearms (reduced rate)": [
    "Aiming", "Reloading", "Long Blade"
  ]
};
```

### Adding a Skill

Add the skill name to the appropriate category array:

```javascript
"Crafts (full rate)": [
  "Carpentry", "Cooking", /* ... */, "NewSkill"
],
```

### Adding a Category

Add a new key-value pair:

```javascript
const DATA = {
  // ... existing categories ...
  "New Category (your rate)": [
    "Skill1", "Skill2", "Skill3"
  ]
};
```

### Skill Book Volumes

Each skill has 5 volumes (I–V) automatically. This is hardcoded in the render logic:

```javascript
for (let v = 1; v <= 5; v++) {
  // Creates Volume I, II, III, IV, V
}
```

To change the number of volumes, modify the loop in the `buildSkillCard()` function.

---

## Customizing the Growing Calendar

Crops are defined in the `CROPS` constant:

```javascript
const CROPS = [
  {n:"Barley", t:"Veg", w:30, d:108, p:"Aug–Oct", bad:"Jun–Jul", best:"Sep", hardy:true},
  {n:"Basil", t:"Herb", w:80, d:60, p:"Mar–May", bad:"Aug–Jan", best:"Mar", hardy:false},
  // ...
];
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `n` | string | Crop name |
| `t` | string | Type: `"Veg"` or `"Herb"` |
| `w` | number | Minimum water level (%) |
| `d` | number | Days to harvest |
| `p` | string | Planting window (months) |
| `bad` | string | Bad months (low yield) |
| `best` | string | Best planting time |
| `hardy` | boolean | Survives frost |

### Adding a Crop

```javascript
{n:"NewCrop", t:"Veg", w:50, d:90, p:"Apr–Jun", bad:"Oct–Feb", best:"May", hardy:false},
```

### Month Format

Use 3-letter English abbreviations: `Jan`, `Feb`, `Mar`, `Apr`, `May`, `Jun`, `Jul`, `Aug`, `Sep`, `Oct`, `Nov`, `Dec`

Ranges use an en-dash: `Mar–May` (not hyphen)

---

## Local Development

### Testing Changes Locally

1. Edit the HTML file
2. Open it directly in your browser (`file://` URL works)
3. Changes take effect immediately on refresh

### Testing with the Self-Hosted Server

```bash
cd server
PASSWORD=test node server.js
```

Open http://localhost:3000 — edits to `index-server.html` show on refresh.

### Testing the AWS Version Locally

The AWS version needs the API backend. For local testing:

1. Start a local server (e.g., VS Code Live Server, Python's `http.server`)
2. The API calls will fail, but you can test the UI

For full local testing, you'd need to mock the API or use a local Lambda emulator.

---

## Deploying Changes

### Local Version

Just edit and use — no deployment needed.

### GitHub Pages

```bash
git add .
git commit -m "Update skills"
git push
```

Changes go live in 1-2 minutes.

### Self-Hosted Server

Edit the file on your server and refresh. No restart needed.

### AWS

```bash
cd aws

# Upload changed files
aws s3 cp website/index.html s3://YOUR-BUCKET/index.html \
  --content-type "text/html; charset=utf-8"

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id YOUR-DIST-ID \
  --paths "/index.html"
```

Or use the deploy script:

```bash
./deploy.sh --upload
```

---

## Code Style

- **HTML:** All-in-one files (CSS and JS inline) for simplicity
- **JavaScript:** ES6+, no build step, no external dependencies
- **CSS:** CSS custom properties (variables) for theming

### Theme Colors

```css
:root {
  --bg: #14171a;           /* Background */
  --card: #1f2428;         /* Card background */
  --accent: #7fbf3f;       /* Primary accent (green) */
  --accent-dim: #3d5a20;   /* Dimmed accent */
  --text: #e8e8e8;         /* Primary text */
  --text-dim: #9a9a9a;     /* Secondary text */
  --border: #2c3237;       /* Borders */
}
```

---

## Contributing

### Pull Request Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test locally
5. Commit: `git commit -m "Add feature X"`
6. Push: `git push origin feature/my-feature`
7. Open a Pull Request

### Guidelines

- Keep HTML files self-contained (no external dependencies)
- Test in multiple browsers (Chrome, Firefox, Safari)
- Test on mobile
- Update all relevant HTML files if changing shared features
- Write clear commit messages

### Reporting Issues

Open an issue on GitHub with:
- What you expected
- What actually happened
- Browser and OS version
- Steps to reproduce

---

## Data Sources

- **Skill books:** [Project Zomboid Wiki](https://pzwiki.net/wiki/Skill_book)
- **Growing calendar:** In-game data from Build 42
- **Skill categories:** Based on XP multiplier rates from the wiki

---

## License

MIT — do whatever you want with it.
