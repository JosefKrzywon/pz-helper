# AWS Deployment

Deploy your own password-protected PZ Skill Books website on AWS.

**What you get:**
- Custom domain with HTTPS (e.g. `zomboid.your-domain.com`)
- Cookie-based login (no browser popup)
- Progress synced to the cloud
- Multiple users with separate progress
- Admin panel for user management

**Cost:** ~$0.50/month (Route53 zone fee only — everything else is within Free Tier)

---

## Prerequisites

### 1. AWS Account

You need an AWS account. [Create one here](https://portal.aws.amazon.com/billing/signup) if you don't have one.

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
BUCKET_PREFIX="pz-skillbooks-1234"
DOMAIN_NAME="zomboid.your-domain.com"
HOSTED_ZONE_ID="ZXXXXXXXXXX"

# Cost Protection
BUDGET_LIMIT="5"
BUDGET_EMAIL=""
LAMBDA_CONCURRENCY="5"
```

Edit this file to change settings, then run `./deploy.sh` again.

---

## Costs

| Service | Free Tier | Your Cost |
|---------|-----------|-----------|
| Lambda | 1M requests/month | $0.00 |
| DynamoDB | 25 GB + 200M requests | $0.00 |
| S3 | 5 GB | ~$0.01 |
| CloudFront | 1 TB transfer | ~$0.01 |
| **Route53 Zone** | — | **$0.50** |

**Total: ~$0.50/month**

Without custom domain (using CloudFront URL): effectively **$0**

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
