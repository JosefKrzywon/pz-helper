# Setup: AWS Lambda Sync

This guide explains the AWS setup for the Lambda version. You'll get:
- **Sync Backend:** Lambda + S3 for progress synchronization
- **Optional:** Website hosting with CloudFront + custom domain

## Cost (without Free Tier)

| Component | Cost/Month |
|-----------|------------|
| Sync Backend (Lambda + S3) | < $0.05 |
| Website Hosting (CloudFront + S3) | < $0.10 |
| Route53 Hosted Zone | $0.50 |
| **Total** | **~$0.50** |

The Route53 Zone is the only significant cost factor. If you already have the zone (for other projects), the setup costs practically nothing.

## Prerequisites

- AWS Account
- AWS CLI installed and configured (`aws configure`)
- Node.js installed (for password hashing)
- Bash shell (Linux, macOS, Git Bash, WSL)
- Optional: Custom domain in Route53

---

## Part 1: Deploy Sync Backend

The sync backend enables progress synchronization between devices.

### 1.1 Adjust Configuration

Open `aws/deploy.sh` and adjust if needed:

```bash
STACK_NAME="pz-skillbooks"
REGION="eu-central-1"
USERNAME="admin"
BUCKET_PREFIX="pz-skillbooks"
```

### 1.2 Run Deployment

```bash
cd aws
chmod +x deploy.sh
./deploy.sh
```

The script:
1. Creates an artifact bucket
2. Prompts for your password (securely hashed)
3. Packages and uploads the Lambda code
4. Deploys the CloudFormation stack

**Output:**
```
========================================
Deployment complete!
========================================

Function URL:
  https://xxxxxxx.lambda-url.eu-central-1.on.aws/

Username: admin
```

### 1.3 Configure the App

1. Open `index-lambda.html` in your browser
2. Enter:
   - **API URL:** The Function URL from above
   - **Username:** `admin`
   - **Password:** The password from step 1.2
3. Click **"Login"**

---

## Part 2: Website Hosting (optional)

Host the page on your own domain with HTTPS.

### 2.1 Create ACM Certificate

The certificate must be in `us-east-1` (CloudFront requirement):

```bash
chmod +x create-certificate.sh
./create-certificate.sh zomboid.example.com Z1234567890ABC
```

Replace:
- `zomboid.example.com` with your domain
- `Z1234567890ABC` with your Route53 Hosted Zone ID

The script creates the certificate and waits for DNS validation (~2 minutes).

**Output:**
```
Certificate ARN (use this in website-stack.yaml):
  arn:aws:acm:us-east-1:123456789012:certificate/abc-123-def
```

### 2.2 Website Configuration

Enter the values in `aws/deploy.sh`:

```bash
DOMAIN_NAME="zomboid.example.com"
HOSTED_ZONE_ID="Z1234567890ABC"
CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/abc-123-def"
```

### 2.3 Deploy Website

```bash
./deploy.sh website
```

The script:
1. Creates S3 bucket + CloudFront distribution
2. Configures Route53 DNS
3. Uploads the HTML files
4. Invalidates the CloudFront cache

**Output:**
```
========================================
Website deployed!
========================================

URL: https://zomboid.example.com
```

### 2.4 Update Files Only

After changes to HTML files:

```bash
./deploy.sh website --upload
```

---

## Management

### Update Lambda Code

```bash
./deploy.sh --update
```

### Change Password

```bash
chmod +x set-password.sh
./set-password.sh
```

### Delete Stacks

```bash
./deploy.sh --delete           # Sync backend
./deploy.sh website --delete   # Website
```

**Note:** S3 buckets are not automatically deleted (data protection). Delete them manually in the AWS Console.

---

## CI/CD with GitHub Actions

For automatic deployments on Git push:

→ [GitHub Actions Setup](setup-github-actions.md)

---

## Troubleshooting

### "Login failed"

- Check API URL (must start with `https://`, end with `.on.aws/`)
- Check username/password (case-sensitive)
- Check CloudWatch Logs:
  ```bash
  aws logs tail /aws/lambda/pz-skillbooks-sync --follow
  ```

### "CORS error"

- Page must be loaded via HTTPS or `file://`
- HTTP (without S) doesn't work due to Mixed Content

### Deploy fails

```bash
# Show stack events
aws cloudformation describe-stack-events \
  --stack-name pz-skillbooks \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`]'
```

Common causes:
- Bucket name already exists → change `BUCKET_PREFIX`
- Missing IAM permissions

### Certificate validation stuck

- Check if the CNAME record was created in Route53
- DNS propagation can take up to 10 minutes
- Check with: `aws acm describe-certificate --certificate-arn <ARN> --region us-east-1`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser                               │
│                    (index-lambda.html)                       │
└─────────────────────┬───────────────────────────────────────┘
                      │ HTTPS + Basic Auth
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  Lambda Function URL                         │
│              (no hourly costs, pay-per-request)              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    Lambda Function                           │
│  - PBKDF2 password verification                              │
│  - Structured JSON logging                                   │
│  - Request validation                                        │
└─────────────────────┬───────────────────────────────────────┘
                      │ GetObject / PutObject
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      S3 Bucket                               │
│  - Encrypted (AES-256)                                       │
│  - Versioned (30 days history)                               │
│  - progress/<user-hash>.json                                 │
└─────────────────────────────────────────────────────────────┘

Optional: Website Hosting

┌─────────────────────────────────────────────────────────────┐
│                    CloudFront                                │
│  - HTTPS with custom certificate                             │
│  - HTTP/2 + HTTP/3                                           │
│  - Caching (CachingOptimized Policy)                         │
│  - Security Headers                                          │
└─────────────────────┬───────────────────────────────────────┘
                      │ Origin Access Control
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   S3 Bucket (Website)                        │
│  - Private (CloudFront access only)                          │
│  - index.html, index-gist.html, index-lambda.html            │
└─────────────────────────────────────────────────────────────┘
```

No hourly costs. Lambda and CloudFront sleep until a request arrives.
