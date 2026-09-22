# AWS Deployment

Deploy your own password-protected Zomboid Helper website on AWS.

> ⚠️ **For experienced users only**
> 
> This deployment requires familiarity with AWS, CloudFormation, and cloud infrastructure. **AWS can generate significant unexpected costs** if misconfigured, abused, or if resources are forgotten. While this deployment includes cost protection (budget alerts, auto-disable at threshold), **you are responsible for monitoring your AWS bill**.
> 
> If you're new to AWS, consider the simpler **Local**, **Gist**, or **Self-Hosted** options instead.

---

**What you get:**
- Custom domain with HTTPS (optional — works without too)
- Cookie-based login (no browser popup)
- Progress synced to the cloud
- Multiple users with separate progress
- Admin panel for user management

**Costs:**

| Scenario | Cost |
|----------|------|
| Without custom domain | ~$0/month (Free Tier) |
| With existing Route53 zone | ~$0.50/month (zone hosting fee) |
| **Registering a new domain at AWS** | **$12–50/year** (depends on TLD) + $0.50/month |

If you already have a domain elsewhere (Namecheap, GoDaddy, etc.), you can either:
- Transfer it to Route53 (one-time fee, varies by TLD)
- Point your external nameservers to a Route53 hosted zone ($0.50/month)
- Skip the custom domain and use the free CloudFront URL

---

## Prerequisites

### 1. AWS Account

You need an AWS account. [Create one here](https://portal.aws.amazon.com/billing/signup) if you don't have one.

**Important:** New AWS accounts have a 12-month Free Tier. After that, or if you exceed Free Tier limits, charges apply. Always monitor your [AWS Billing Dashboard](https://console.aws.amazon.com/billing/).

### 2. AWS CLI

The deployment script uses the AWS CLI. Check if it's installed:

```bash
aws --version
# Should show: aws-cli/2.x.x ...
```

**Not installed?** Follow the official guide:
- **Windows:** [AWS CLI MSI Installer](https://awscli.amazonaws.com/AWSCLIV2.msi)
- **macOS:** `brew install awscli`
- **Linux:** [Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

### 3. AWS Credentials

Configure your credentials:

```bash
aws configure
```

You'll need:
- **Access Key ID** and **Secret Access Key** — get these from [IAM Console](https://console.aws.amazon.com/iam/) → Users → Your User → Security credentials
- **Default region** — e.g. `eu-central-1`

Verify it works:
```bash
aws sts get-caller-identity
# Should show your account ID
```

**Required permissions:** the deploy script provisions resources across several
services, so the credentials you use need permissions for **S3,
CloudFormation, Lambda, DynamoDB, Route53, ACM, IAM, CloudFront, SNS and
Budgets**. The simplest option is an account/user with `AdministratorAccess`.
If you prefer least privilege, grant the full-access managed policies for those
services (e.g. `AmazonS3FullAccess`, `AWSCloudFormationFullAccess`,
`AWSLambda_FullAccess`, `AmazonDynamoDBFullAccess`, `AmazonRoute53FullAccess`,
`AWSCertificateManagerFullAccess`, `CloudFrontFullAccess`, `IAMFullAccess`, and
budget/SNS access). The script checks most of these up front and warns if any
are missing.

### 4. Required Tools

| Tool | Check | Install |
|------|-------|---------|
| **Bash** | `bash --version` | Git Bash (Windows), Terminal (macOS/Linux) |
| **zip** | `zip --version` | `apt install zip` / `brew install zip` / 7-Zip on Windows (or have `python3` available — the script falls back to it) |
| **openssl** | `openssl version` | Usually pre-installed; comes with Git Bash |

### 5. Route53 Hosted Zone (Optional)

For a custom domain, you need a Route53 hosted zone. Skip this if you're okay with the CloudFront URL.

Check existing zones:
```bash
aws route53 list-hosted-zones --query 'HostedZones[*].[Name,Id]' --output table
```

---

## Quick Start

```bash
cd aws
./deploy.sh
```

That's it! The script is interactive and will:

1. ✓ Check all prerequisites
2. ✓ Test AWS permissions
3. ✓ List your Route53 domains to choose from
4. ✓ Ask for your preferred settings
5. ✓ Configure cost protection (budget alerts, auto-disable)
6. ✓ Create the SSL certificate (if using custom domain)
7. ✓ Deploy all AWS resources via CloudFormation
8. ✓ Upload the website files
9. ✓ Print your website URL and login credentials

**First run takes 10-15 minutes** (mostly waiting for CloudFront distribution).

---

## What Gets Deployed

| Resource | Purpose |
|----------|---------|
| **S3 Bucket** | Hosts the static website files |
| **CloudFront** | CDN with HTTPS and caching |
| **CloudFront Function** | Redirects unauthenticated users to login |
| **Lambda** | API backend (login, sync, admin) |
| **DynamoDB** | Stores users and progress |
| **Route53 Record** | Points your domain to CloudFront |
| **ACM Certificate** | Free SSL certificate |
| **AWS Budget** | Cost monitoring with alerts |
| **Budget Alert Lambda** | Auto-disables site if budget exceeded |
| **SNS Topic** | Delivers budget alerts |

All resources are created by a single CloudFormation stack and can be deleted cleanly.

---

## Cost Protection (DDoS/Abuse Prevention)

The setup wizard asks about cost protection:

- **Budget Limit:** Set a monthly spending cap (default: $5)
- **Alert Thresholds:** Email notifications at 50%, 80%, 100%
- **Auto-Disable:** CloudFront is automatically disabled when 100% budget is reached
- **Lambda Concurrency Limit:** Restricts max concurrent API calls (default: 5)

**Why this matters:** Without limits, a DDoS attack or abuse could generate unexpected AWS bills. S3/CloudFront transfer costs ~$0.09/GB — a malicious actor downloading your site repeatedly could rack up charges.

**If your site goes offline due to budget:**
1. Check AWS Console → CloudFront → Distributions
2. Select your distribution
3. Click "Enable"
4. Investigate what caused the traffic spike

---

## Commands

```bash
./deploy.sh              # Deploy (interactive setup on first run)
./deploy.sh --upload     # Upload HTML files only (after edits)
./deploy.sh --delete     # Delete all AWS resources
./deploy.sh --help       # Show help
./reset-password.sh      # Reset a user's login password (admin only)
```

---

## Resetting a Password

If you forget your login password (or want to change it without the website),
use the admin reset script:

```bash
cd aws
./reset-password.sh              # resets the admin user from config.sh
./reset-password.sh someuser     # resets a specific user
```

The script asks for the new password (hidden input), hashes it locally, and
writes it directly into the DynamoDB users table. If the user doesn't exist
yet, it is created as an admin.

**Who can run this:** The script talks to DynamoDB through the AWS CLI, so it
only works for someone with valid AWS credentials for this account that have
write access to the users table — i.e. the **account owner / administrator**.
There is no way to trigger it anonymously or from the website. Your plaintext
password never leaves your machine; only the salted SHA-256 hash is stored.

---

## Admin Panel

Users flagged as **admin** see a 👑 **Admin** button in the top bar after
logging in. It opens a simple user-management panel:

- **Add User** — create a new account; tick *Make admin* to grant admin rights.
- **Reset PW** — set a new password for any user (useful when someone forgets
  theirs). The admin types the new password; it is hashed server-side.
- **Delete** — remove a user (and their saved progress). You cannot delete
  your own account.

**Roles:**

| Role | Can do |
|------|--------|
| **Administrator** | Everything a user can, plus create / delete users and reset passwords |
| **User** | Log in and track their own skill books; progress synced to the cloud |

The first admin user is created automatically on first login from the username
and password you set during `./deploy.sh`. Additional users are created from
within the admin panel. For an out-of-band password reset (e.g. the admin
locked themselves out), use `./reset-password.sh` (see above).

---

## Configuration

After first run, settings are saved in `config.sh`:

```bash
REGION="eu-central-1"
USERNAME="zombie"
BUCKET_PREFIX="pz-helper"
DOMAIN_NAME="zomboid.your-domain.com"
HOSTED_ZONE_ID="ZXXXXXXXXXX"

# Cost Protection
BUDGET_LIMIT="5"
BUDGET_EMAIL=""
LAMBDA_CONCURRENCY="5"

# Search Engine Visibility
BLOCK_ROBOTS="no"
```

Edit this file to change settings, then run `./deploy.sh` again.

---

## Security

The AWS deployment includes several security features:

### Authentication & Sessions
- **HMAC-signed session cookies** — tokens are cryptographically signed and verified
- **Timing-safe comparisons** — prevents timing attacks on token verification
- **Password hashing** — SHA-256 with random salt, stored in DynamoDB
- **HttpOnly/Secure/SameSite cookies** — protects against XSS and CSRF

### HTTP Security Headers
CloudFront adds these headers to all responses:
- `Content-Security-Policy` — restricts resource loading
- `X-Frame-Options: DENY` — prevents clickjacking
- `X-Content-Type-Options: nosniff` — prevents MIME sniffing
- `Strict-Transport-Security` — enforces HTTPS
- `Referrer-Policy` — controls referrer information
- `X-XSS-Protection` — legacy XSS filter

### Search Engine Visibility
The deploy script asks whether to block search engines (default: no). If enabled, a `robots.txt` is uploaded:
```
User-agent: *
Disallow: /
```
This tells well-behaved crawlers not to index the site. To change this later, edit `BLOCK_ROBOTS` in `config.sh` and run `./deploy.sh --upload`.

---

## Costs (Detailed)

This assumes you're within AWS Free Tier (first 12 months, or always-free tiers):

| Service | Free Tier Limit | Typical Usage | Your Cost |
|---------|-----------------|---------------|-----------|
| Lambda | 1M requests/month | <1000 | $0.00 |
| DynamoDB | 25 GB + 200M requests | <1 MB | $0.00 |
| S3 | 5 GB storage | <1 MB | $0.00 |
| CloudFront | 1 TB transfer/month | <1 GB | $0.00 |
| Route53 Zone | — | 1 zone | $0.50/month |
| Route53 Domain | — | if registering new | $12–50/year |

**Scenarios:**

| Setup | Monthly Cost |
|-------|--------------|
| No custom domain (CloudFront URL only) | ~$0 |
| Custom domain with existing Route53 zone | ~$0.50 |
| Custom domain + new zone (domain registered elsewhere) | ~$0.50 |
| **New domain registered at AWS** | **$0.50 + $1–4/month amortized** |

⚠️ **Cost risks:**
- **Traffic spikes / DDoS:** CloudFront charges ~$0.085/GB for data transfer. A sustained attack could generate costs.
- **Forgotten resources:** If you stop using the site, delete the stack (`./deploy.sh --delete`) to avoid ongoing charges.
- **Free Tier expiration:** After 12 months, some services start charging. Lambda and DynamoDB have always-free tiers, but watch your bill.

The deployment includes automatic cost protection (see "Cost Protection" section above), but **always monitor your AWS bill**.

---

## Troubleshooting

### "AWS CLI not found"

Install the AWS CLI — see Prerequisites above.

### "AWS credentials not configured"

Run `aws configure` and enter your Access Key ID and Secret Access Key.

### Lambda URL returns 403 Forbidden

This is a known AWS quirk. The deploy script handles it automatically, but if you hit this:

```bash
aws lambda add-permission \
  --function-name YOUR_FUNCTION_NAME \
  --statement-id FunctionURLInvokeAccess \
  --action lambda:InvokeFunction \
  --principal "*"
```

### Certificate stuck on "Pending validation"

DNS propagation can take up to 30 minutes. The script waits automatically.

### Changes not showing up

CloudFront caches content. Invalidate after changes:

```bash
./deploy.sh --upload
# or manually:
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
```

---

## More Information

- **[Detailed Technical Reference](DEPLOYMENT.md)** — Manual deployment steps, CloudFormation parameters, admin CLI commands
- **[Development Guide](../docs/DEVELOPMENT.md)** — How to customize skills, crops, and contribute

---

## Deleting Everything

```bash
./deploy.sh --delete
```

This removes all AWS resources. S3 buckets with content are emptied and deleted. Your `config.sh` is kept locally.
