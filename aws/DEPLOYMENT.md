# Deployment Reference

A detailed reference for deploying, operating, and tearing down the PZ Skill Books
AWS environment.

Last updated: 2026-09-22
Version: 1.4

---

## Overview

This project ships a small web application whose static frontend is served from
Amazon S3 through CloudFront, and whose API is served by a single AWS Lambda
function exposed via a Lambda Function URL. Persistent data lives in two
DynamoDB tables (Users and Progress). Authentication in the AWS version is
**cookie-based session auth**: the Lambda issues a signed session cookie on
login, and a CloudFront Function gates access to the site by verifying that
cookie's HMAC signature (not just its presence) before serving any page.

Almost everything is provisioned by a single CloudFormation stack
(`aws/stack.yaml`). A few things are handled outside the stack — the artifact
S3 bucket (which must exist before the stack can pull the Lambda code), the ACM
certificate (passed into the stack as a parameter), the website content upload,
and the initial admin user record.

- **Region for regional resources:** `eu-central-1` (adjust to your own region).
- **Region for the ACM certificate:** `us-east-1` (CloudFront requires the
  certificate to live in `us-east-1`, regardless of where the rest of the stack
  is deployed).

Throughout this document, replace the following generic placeholders with your
real values:

| Placeholder | Meaning |
|-------------|---------|
| `YOUR_ACCOUNT_ID` / `${ACCOUNT_ID}` | Your 12-digit AWS account ID |
| `pz-helper-XXXX` | Your chosen `BucketPrefix` for resource names |
| `zomboid.your-domain.com` | The custom domain you serve the site from |
| `ZXXXXXXXXXX` | Your Route53 Hosted Zone ID |
| `arn:aws:acm:us-east-1:XXXX:certificate/XXXX` | Your ACM certificate ARN (in `us-east-1`) |

---

## What Gets Deployed (Overview)

This is the most important section if you are trying to figure out **what
already exists** in your account after a previous (possibly automated)
deployment. Every resource below is either created by the CloudFormation stack
`pz-helper` or created as a manual prerequisite/follow-up step. For each one
you get a one-line purpose and a verification command you can run right now to
check whether it currently exists.

Set these first so the commands below work:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-central-1
```

### CloudFormation stack (`pz-helper`)
Purpose: the single source of truth that provisions and wires together the S3
website bucket, Lambda, DynamoDB tables, CloudFront distribution + function, and
Route53 records.

```bash
aws cloudformation describe-stacks --stack-name pz-helper --region $REGION \
  --query 'Stacks[0].StackStatus' --output text
```
If this returns `CREATE_COMPLETE` or `UPDATE_COMPLETE`, the stack exists and is
healthy. An error means the stack does not exist.

### S3 website bucket (`pz-helper-XXXX-website-${ACCOUNT_ID}`)
Purpose: stores the static frontend files (`index.html`, `login.html`) served
to users through CloudFront. Created by the stack. Public access is fully
blocked; CloudFront reaches it via Origin Access Control (OAC).

```bash
aws s3 ls s3://pz-helper-XXXX-website-${ACCOUNT_ID}
```

### S3 artifact bucket (`pz-helper-artifacts-${ACCOUNT_ID}`)
Purpose: holds the zipped Lambda deployment package (`lambda/api-function.zip`)
that CloudFormation and `update-function-code` pull from. Created **manually**
before the stack, because the stack references its contents.

```bash
aws s3 ls s3://pz-helper-artifacts-${ACCOUNT_ID}/lambda/
```

### Lambda function (`pz-helper-XXXX-api`)
Purpose: the API backend. Handles login, session validation, progress sync, and
admin operations, reading/writing the DynamoDB tables. Created by the stack
(Node.js 20.x runtime, code pulled from the artifact bucket).

```bash
aws lambda get-function --function-name pz-helper-XXXX-api --region $REGION \
  --query 'Configuration.[FunctionName,Runtime,LastModified]' --output table
```

### Lambda Function URL
Purpose: gives the Lambda a stable HTTPS endpoint that CloudFront uses as the
origin for `/api/*` requests. Created by the stack with `AuthType: NONE` (auth
is enforced inside the Lambda via the session cookie, not by IAM).

```bash
aws lambda get-function-url-config --function-name pz-helper-XXXX-api \
  --region $REGION --query 'FunctionUrl' --output text
```

### DynamoDB Users table (`pz-helper-XXXX-users`)
Purpose: stores user accounts — username (partition key), salted+hashed
password, admin flag, creation timestamp. This is the authentication data store.
Created by the stack (on-demand billing, encryption at rest enabled).

```bash
aws dynamodb describe-table --table-name pz-helper-XXXX-users --region $REGION \
  --query 'Table.[TableName,TableStatus,ItemCount]' --output table
```

### DynamoDB Progress table (`pz-helper-XXXX-progress`)
Purpose: stores each user's saved progress, keyed by `visibleId`
(`SHA256(username).slice(0,16)`). **This is the progress store — not S3.**
Created by the stack (on-demand billing, encryption at rest enabled).

```bash
aws dynamodb describe-table --table-name pz-helper-XXXX-progress --region $REGION \
  --query 'Table.[TableName,TableStatus,ItemCount]' --output table
```

### CloudFront distribution
Purpose: the public HTTPS entry point. Serves static files from the S3 origin
and forwards `/api/*` to the Lambda origin, terminates TLS with your ACM
certificate, and maps your custom domain. Created by the stack.

```bash
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='PZ Skill Books'].[Id,DomainName,Status]" \
  --output table
```

### CloudFront Function (`pz-helper-XXXX-auth`)
Purpose: runs at viewer-request time on every non-API request and redirects
visitors without a valid `pz_session` cookie to `/login.html`. This is the
edge-level gate for cookie-based session auth. Created by the stack.

```bash
aws cloudfront list-functions \
  --query "FunctionList.Items[?Name=='pz-helper-XXXX-auth'].[Name,Status]" \
  --output table
```

### Route53 record (A + AAAA for `zomboid.your-domain.com`)
Purpose: DNS alias records pointing your custom domain (IPv4 and IPv6) at the
CloudFront distribution. Created by the stack in your Hosted Zone.

```bash
aws route53 list-resource-record-sets --hosted-zone-id ZXXXXXXXXXX \
  --query "ResourceRecordSets[?Name=='zomboid.your-domain.com.']" --output table
```

### ACM certificate (`arn:aws:acm:us-east-1:XXXX:certificate/XXXX`)
Purpose: the TLS certificate that CloudFront presents for your custom domain.
**Not created by this stack** — it is passed in as the `CertificateArn`
parameter and must already exist in `us-east-1` and be validated.

```bash
aws acm describe-certificate --region us-east-1 \
  --certificate-arn arn:aws:acm:us-east-1:XXXX:certificate/XXXX \
  --query 'Certificate.[DomainName,Status]' --output table
```

### Supporting resources created by the stack (for completeness)
These are provisioned automatically as part of the stack and generally do not
require separate management:

- **IAM execution role (`pz-helper-XXXX-lambda-role`)** — grants the Lambda
  DynamoDB access and CloudWatch Logs permissions.
- **Two Lambda permissions** — a Function URL invoke permission and a plain
  `lambda:InvokeFunction` permission. Both are required for the Function URL to
  respond without `403 Forbidden` (see the note in the initial deployment).
- **CloudFront Origin Access Control (`pz-helper-XXXX-oac`)** — lets
  CloudFront read the private S3 website bucket.
- **S3 bucket policy** — allows the CloudFront distribution (via OAC) to
  `s3:GetObject` from the website bucket.
- **CloudWatch Logs group (`/aws/lambda/pz-helper-XXXX-api`)** — created
  automatically on the Lambda's first invocation.

---

## Prerequisites

```bash
# Check the AWS CLI version
aws --version

# Confirm you are authenticated against the right account
aws sts get-caller-identity
```

You also need, before deploying:

- A Route53 Hosted Zone for your domain (its ID is `ZXXXXXXXXXX`).
- A validated ACM certificate in `us-east-1` covering `zomboid.your-domain.com`.

---

## Initial Deployment

The steps below go in order. Steps 1–2 prepare the artifact the stack needs,
step 3 generates secrets, step 4 creates the stack (the bulk of the resources),
and steps 5–8 finish wiring things up and load initial content/data.

Set common variables once:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-central-1
```

### 1. Create the artifact bucket (one-time)

Creates the S3 bucket that stores the Lambda deployment package. The stack
cannot be created until this bucket exists and contains the zip, because the
stack's Lambda resource references `lambda/api-function.zip` inside it.

```bash
aws s3 mb s3://pz-helper-artifacts-${ACCOUNT_ID} --region $REGION
```

Verify:

```bash
aws s3 ls | grep pz-helper-artifacts-${ACCOUNT_ID}
```

### 2. Upload the Lambda code

Packages the API handler into a zip and uploads it to the artifact bucket. The
resulting artifact is `s3://pz-helper-artifacts-${ACCOUNT_ID}/lambda/api-function.zip`.

```bash
cd aws/lambda

# Linux/macOS
zip -j api-function.zip index.mjs

# Windows (7-Zip)
7z a -tzip api-function.zip index.mjs

# Upload
aws s3 cp api-function.zip s3://pz-helper-artifacts-${ACCOUNT_ID}/lambda/api-function.zip
```

Verify:

```bash
aws s3 ls s3://pz-helper-artifacts-${ACCOUNT_ID}/lambda/
```

### 3. Generate secrets

Produces the two secret parameters the stack needs: a session-signing secret
(used by the Lambda to sign/verify session cookies) and an admin password hash.
Nothing is deployed here — you are only generating values to pass in step 4.

```bash
# Session secret (64 hex characters)
SESSION_SECRET=$(openssl rand -hex 32)
echo "Session Secret: $SESSION_SECRET"

# Hash the admin password
SALT=$(openssl rand -hex 16)
PASSWORD="your-password-here"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')
ADMIN_HASH="sha256:${SALT}:${HASH}"
echo "Admin Hash: $ADMIN_HASH"
```

The hash format is `sha256:<salt>:<hash>`, matching what the Lambda expects when
verifying passwords.

### 4. Deploy the CloudFormation stack

This is the big step. It creates the majority of the resources listed in
**What Gets Deployed**: both DynamoDB tables, the S3 website bucket + bucket
policy, the IAM role, the Lambda function + Function URL + permissions, the
CloudFront distribution + auth function + OAC, and the Route53 A/AAAA records.

```bash
aws cloudformation create-stack \
  --stack-name pz-helper \
  --template-body file://aws/stack.yaml \
  --parameters \
    ParameterKey=BucketPrefix,ParameterValue=pz-helper-XXXX \
    ParameterKey=DomainName,ParameterValue=zomboid.your-domain.com \
    ParameterKey=HostedZoneId,ParameterValue=ZXXXXXXXXXX \
    ParameterKey=CertificateArn,ParameterValue=arn:aws:acm:us-east-1:XXXX:certificate/XXXX \
    ParameterKey=AdminUsername,ParameterValue=zombie \
    ParameterKey=AdminPasswordHash,ParameterValue="$ADMIN_HASH" \
    ParameterKey=SessionSecret,ParameterValue="$SESSION_SECRET" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION

# Wait for completion (CloudFront distribution creation can take 10-20 minutes)
aws cloudformation wait stack-create-complete --stack-name pz-helper --region $REGION
```

`CAPABILITY_NAMED_IAM` is required because the stack creates a named IAM role.

Verify:

```bash
aws cloudformation describe-stacks --stack-name pz-helper --region $REGION \
  --query 'Stacks[0].StackStatus' --output text
```

Expect `CREATE_COMPLETE`.

### 5. IMPORTANT: Add the Lambda invoke permission

The stack already creates a Function URL invoke permission, but Lambda Function
URLs in practice need **both** the URL-scoped permission and a plain
`lambda:InvokeFunction` permission. Without this, the Function URL (and
therefore every `/api/*` call through CloudFront) returns `403 Forbidden`. Run
this if you hit 403s on the API:

```bash
aws lambda add-permission \
  --function-name pz-helper-XXXX-api \
  --statement-id FunctionURLInvokeAccess \
  --action lambda:InvokeFunction \
  --principal "*" \
  --region $REGION
```

Verify the resource policy contains the statement:

```bash
aws lambda get-policy --function-name pz-helper-XXXX-api --region $REGION \
  --query 'Policy' --output text
```

### 6. Upload the website files

The stack creates the website bucket but leaves it empty. This step uploads the
actual HTML the users see. Content type is set explicitly so browsers render
UTF-8 correctly.

```bash
BUCKET=$(aws cloudformation describe-stacks --stack-name pz-helper --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`WebsiteBucketName`].OutputValue' --output text)

aws s3 cp aws/website/index.html s3://${BUCKET}/index.html --content-type "text/html; charset=utf-8"
aws s3 cp aws/website/login.html s3://${BUCKET}/login.html --content-type "text/html; charset=utf-8"
```

Verify:

```bash
aws s3 ls s3://${BUCKET}/
```

### 7. Create the admin user

The Users table is created empty by the stack, so you must insert the initial
admin record. Use the same hash you generated in step 3.

```bash
aws dynamodb put-item \
  --table-name pz-helper-XXXX-users \
  --item '{
    "username": {"S": "zombie"},
    "passwordHash": {"S": "'"$ADMIN_HASH"'"},
    "isAdmin": {"BOOL": true},
    "createdAt": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
  }' \
  --region $REGION
```

Verify:

```bash
aws dynamodb get-item --table-name pz-helper-XXXX-users \
  --key '{"username": {"S": "zombie"}}' --region $REGION
```

### 8. Invalidate the CloudFront cache

Ensures CloudFront serves the files you just uploaded rather than a cached
(possibly empty/404) version.

```bash
DIST_ID=$(aws cloudformation describe-stacks --stack-name pz-helper --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output text)

aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
```

After this, browse to `https://zomboid.your-domain.com` — you should be
redirected to `/login.html` by the CloudFront auth function until you log in.

---

## Common Tasks

### Deploy website changes

Re-upload the changed static files and invalidate only the affected paths (cheaper
and faster than invalidating everything).

```bash
# Upload files
aws s3 cp aws/website/index.html s3://${BUCKET}/index.html --content-type "text/html; charset=utf-8"

# Invalidate the cache
aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/index.html"
```

### Update the Lambda code

Repackage the handler, push it to the artifact bucket, then tell Lambda to pull
the new artifact. This does not touch the stack.

```bash
# Repackage
cd aws/lambda
zip -j api-function.zip index.mjs

# Upload
aws s3 cp api-function.zip s3://pz-helper-artifacts-${ACCOUNT_ID}/lambda/api-function.zip

# Update the function
aws lambda update-function-code \
  --function-name pz-helper-XXXX-api \
  --s3-bucket pz-helper-artifacts-${ACCOUNT_ID} \
  --s3-key lambda/api-function.zip \
  --region $REGION
```

### Create a new user

Adds a non-admin account to the Users table.

```bash
# Hash the password
SALT=$(openssl rand -hex 16)
PASSWORD="new-password"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')

# Create the user
aws dynamodb put-item \
  --table-name pz-helper-XXXX-users \
  --item '{
    "username": {"S": "new-user"},
    "passwordHash": {"S": "sha256:'$SALT':'$HASH'"},
    "isAdmin": {"BOOL": false},
    "createdAt": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
  }' \
  --region $REGION
```

### Reset a password

Generates a new salt+hash and updates the existing user record in place.

```bash
SALT=$(openssl rand -hex 16)
PASSWORD="new-password"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')

aws dynamodb update-item \
  --table-name pz-helper-XXXX-users \
  --key '{"username": {"S": "zombie"}}' \
  --update-expression "SET passwordHash = :ph" \
  --expression-attribute-values '{":ph": {"S": "sha256:'$SALT':'$HASH'"}}' \
  --region $REGION
```

### Delete a user

Removes the account from the Users table. The user's saved progress lives in the
Progress table under a derived key and can be removed separately.

```bash
# Delete the user
aws dynamodb delete-item \
  --table-name pz-helper-XXXX-users \
  --key '{"username": {"S": "user-to-delete"}}' \
  --region $REGION

# Optional: also delete their progress
# visibleId = SHA256(username).slice(0,16)
```

### List all users

```bash
aws dynamodb scan \
  --table-name pz-helper-XXXX-users \
  --projection-expression "username, isAdmin, createdAt" \
  --region $REGION
```

---

## Debugging

### Tail the Lambda logs

Follows the Lambda's CloudWatch log group in real time — the first place to look
when the API misbehaves.

```bash
aws logs tail /aws/lambda/pz-helper-XXXX-api --follow --region $REGION
```

### Test the API directly

Exercises the endpoints end to end through CloudFront, storing the session
cookie in `cookies.txt` and reusing it for authenticated calls.

```bash
# Login (stores the session cookie)
curl -X POST "https://zomboid.your-domain.com/api/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"zombie","password":"your-password"}' \
  -c cookies.txt

# Check the session
curl "https://zomboid.your-domain.com/api/session" -b cookies.txt

# Test sync
curl "https://zomboid.your-domain.com/api/sync" -b cookies.txt
```

### Check the stack status

```bash
aws cloudformation describe-stacks --stack-name pz-helper --region $REGION \
  --query 'Stacks[0].StackStatus'
```

### Inspect stack events on failure

Lists the resources that failed and why — the fastest way to diagnose a failed
create/update.

```bash
aws cloudformation describe-stack-events --stack-name pz-helper --region $REGION \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]'
```

---

## Cleanup

### Delete everything

Deletes the stack (which removes all stack-managed resources: DynamoDB tables,
Lambda, CloudFront distribution + function, Route53 records, IAM role, website
bucket policy). The S3 buckets must be emptied and removed manually because
CloudFormation will not delete non-empty buckets. The ACM certificate is not
managed by the stack and is left untouched.

> Warning: this is destructive and irreversible. It deletes the DynamoDB tables
> (all users and progress) and the website content. Make sure you have backups
> if you need them before running this.

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name pz-helper --region $REGION
aws cloudformation wait stack-delete-complete --stack-name pz-helper --region $REGION

# Delete the S3 buckets manually (they contain objects)
aws s3 rm s3://pz-helper-XXXX-website-${ACCOUNT_ID} --recursive
aws s3 rb s3://pz-helper-XXXX-website-${ACCOUNT_ID}

aws s3 rm s3://pz-helper-artifacts-${ACCOUNT_ID} --recursive
aws s3 rb s3://pz-helper-artifacts-${ACCOUNT_ID}
```

---

## Important ARNs & IDs

After deployment you can retrieve these from the stack outputs:

```bash
aws cloudformation describe-stacks --stack-name pz-helper --region $REGION \
  --query 'Stacks[0].Outputs'
```

| Output | Description |
|--------|-------------|
| `WebsiteURL` | The public URL of your site |
| `WebsiteBucketName` | S3 bucket holding the HTML files |
| `UsersTableName` | DynamoDB table for user accounts (auth data) |
| `ProgressTableName` | DynamoDB table for saved progress |
| `CloudFrontDistributionId` | Used for cache invalidations |

---

## Changelog

### 1.4 (2026-09-22)

- **Tab navigation:** the app now separates *Skill Books* and *Growing Calendar*
  into two tabs instead of one long scrolling page.
- **Volume markers:** each skill shows five I–V badges in its header (filled =
  owned, empty = missing), so you can see which books you have without
  expanding the card.
- **Wiki links:** skill names and crop names link to their PZ Wiki page
  (`pzwiki.net`), opening in a new tab.

### 1.3 (2026-09-22)

- **Admin panel:** the web UI now includes a 👑 Admin panel (visible to admin
  users only) to create users, delete users, and reset user passwords.
- **New API endpoint:** `POST /api/admin/users/:username/password` lets an
  admin set another user's password (admin-only, session required).
- **Roles:** administrators (create/delete/reset users) and regular users
  (track their own skill books) — controlled by the `isAdmin` flag.
- **Deploy fix:** the AWS build of `index.html` (from `aws/website/`, with the
  API + admin panel) is now the one served, instead of the local
  localStorage-only build.

### 1.2 (2026-09-22)

- **Security fix:** the CloudFront Function now verifies the session cookie's
  HMAC signature and expiry instead of only checking that a cookie exists.
  Forged or empty cookies no longer grant access to protected pages.
- **Security fix:** `CustomErrorResponses` now serve the public `login.html`
  on S3 403/404 instead of the protected `index.html`, so missing objects
  can't leak the app.
- **Admin bootstrap:** the API Lambda now creates the initial admin user
  automatically on first login (from `ADMIN_USERNAME` / `ADMIN_PASSWORD_HASH`),
  so a fresh deploy no longer leaves an empty users table.
- **New:** `reset-password.sh` to reset or create a user's password directly
  in DynamoDB (account owner only).
- **Deploy fixes:** `deploy.sh` now generates and persists a `SessionSecret`,
  falls back to `python3` for packaging when `zip` is absent, and also uploads
  `login.html` from `aws/website/`.

### 1.1 (2026-09-21)

- Documentation restructure, cost protection (budget alerts + auto-disable),
  Lambda concurrency limit.
