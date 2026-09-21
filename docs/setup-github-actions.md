# GitHub Actions Setup

Last updated: 2025-06-12 (uses the current date)

This guide explains how to set up automatic deployments with GitHub Actions.
GitHub Actions is a built-in automation system that runs jobs (called
*workflows*) in response to events in your repository, such as a push to a
branch or a manual button click.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Create the AWS IAM Role for GitHub Actions](#step-1-create-the-aws-iam-role-for-github-actions)
4. [Step 2: Configure the GitHub Repository](#step-2-configure-the-github-repository)
5. [Step 3: Use the Workflows](#step-3-use-the-workflows)
6. [Troubleshooting](#troubleshooting)
7. [Cost](#cost)

---

## Overview

This repository contains two workflows, stored in `.github/workflows/`:

| Workflow | File | Trigger | What it does |
|----------|------|---------|--------------|
| **Deploy Website** | `deploy-website.yml` | Push to `main` that changes an `index*.html` file, or manual run | Uploads the site's HTML files to the website S3 bucket and (optionally) invalidates the CloudFront cache |
| **Deploy Sync Backend** | `deploy-sync.yml` | Manual run only | Updates the Lambda function code, or performs a full CloudFormation deployment |

Both workflows authenticate to AWS using OIDC (see [Step 1](#step-1-create-the-aws-iam-role-for-github-actions))
and use the region `eu-central-1`.

> **Naming note:** This guide uses the generic resource prefix `pz-helper` for
> the stack name, buckets, function, and IAM role (defined as `STACK_NAME` and
> `BUCKET_PREFIX` in `deploy-sync.yml`). If your deployed resources use a
> different prefix, substitute your actual names wherever `pz-helper` appears.

---

## Prerequisites

1. The AWS resources are already deployed (via `deploy.sh` — see `DEPLOYMENT.md`).
   The `full` sync deployment can update an existing stack, but the **first**
   deployment must be done locally so the admin password can be set. Secrets
   cannot be passed through GitHub Actions.
2. You have admin access to the GitHub repository (needed to add secrets and
   variables).
3. The AWS CLI is installed locally if you want to look up the stack outputs in
   [Step 2](#step-2-configure-the-github-repository).

---

## Step 1: Create the AWS IAM Role for GitHub Actions

GitHub Actions authenticates to AWS using **OIDC (OpenID Connect)**. OIDC lets
GitHub prove its identity to AWS and assume a role on the fly, so you never have
to store long-lived AWS access keys as repository secrets. This is more secure
because there is no static credential that could leak.

### 1.1 Create the Identity Provider

The identity provider tells AWS to trust tokens issued by GitHub. You only need
to create it once per AWS account.

In the AWS Console, go to **IAM → Identity providers → Add provider** and enter:

- **Provider type:** OpenID Connect
- **Provider URL:** `https://token.actions.githubusercontent.com`
- **Audience:** `sts.amazonaws.com`

**Verify:** After saving, the new provider appears in the
**IAM → Identity providers** list with the URL above.

### 1.2 Create the IAM Role

Create a new role under **IAM → Roles → Create role** using the trust policy and
permissions policy below.

The **trust policy** controls *who* may assume the role. The `sub` condition
restricts it to your specific repository, so no other repository can assume it.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:*"
        }
      }
    }
  ]
}
```

Replace:

- `YOUR_ACCOUNT_ID` — your 12-digit AWS account ID.
- `YOUR_GITHUB_USERNAME` — your GitHub username or organization name.
- `YOUR_REPO_NAME` — the name of this repository on GitHub.

The **permissions policy** controls *what* the role may do. The statements below
map directly to the actions the two workflows perform. Replace `YOUR_ACCOUNT_ID`
in every ARN with your real account ID.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Website",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::pz-helper-website-YOUR_ACCOUNT_ID",
        "arn:aws:s3:::pz-helper-website-YOUR_ACCOUNT_ID/*"
      ]
    },
    {
      "Sid": "S3Artifacts",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:CreateBucket",
        "s3:PutBucketPublicAccessBlock"
      ],
      "Resource": [
        "arn:aws:s3:::pz-helper-artifacts-YOUR_ACCOUNT_ID",
        "arn:aws:s3:::pz-helper-artifacts-YOUR_ACCOUNT_ID/*"
      ]
    },
    {
      "Sid": "CloudFront",
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::YOUR_ACCOUNT_ID:distribution/*"
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": "lambda:UpdateFunctionCode",
      "Resource": "arn:aws:lambda:eu-central-1:YOUR_ACCOUNT_ID:function:pz-helper-sync"
    },
    {
      "Sid": "CloudFormation",
      "Effect": "Allow",
      "Action": [
        "cloudformation:DescribeStacks",
        "cloudformation:CreateChangeSet",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:DescribeChangeSet"
      ],
      "Resource": "arn:aws:cloudformation:eu-central-1:YOUR_ACCOUNT_ID:stack/pz-helper/*"
    },
    {
      "Sid": "STS",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

How each statement maps to the workflows:

- **S3Website** — `deploy-website.yml` uploads `index.html`, `index-gist.html`,
  and `index-lambda.html` to the website bucket (`s3:PutObject`).
- **S3Artifacts** — `deploy-sync.yml` creates the artifact bucket if it is
  missing (`s3:CreateBucket`, `s3:PutBucketPublicAccessBlock`) and uploads the
  packaged Lambda zip (`s3:PutObject`).
- **CloudFront** — `deploy-website.yml` invalidates the cache
  (`cloudfront:CreateInvalidation`).
- **Lambda** — the `update` action in `deploy-sync.yml` calls
  `lambda:UpdateFunctionCode` on the function `pz-helper-sync`.
- **CloudFormation** — the `full` action in `deploy-sync.yml` runs
  `aws cloudformation deploy`, which uses change sets and `DescribeStacks`.
- **STS** — both workflows call `sts:GetCallerIdentity` to look up the AWS
  account ID at runtime.

> **Note on `full` deployments:** `aws cloudformation deploy` runs with
> `CAPABILITY_NAMED_IAM` and can create or modify every resource in the stack
> (S3, Lambda, DynamoDB, CloudFront, IAM role, Route53 records). The change-set
> permissions above let the deployment *start*, but CloudFormation also needs
> permission to act on each underlying resource. If you plan to run `full`
> deployments from CI, grant the role the additional resource permissions the
> stack requires, or attach a broader managed policy. If you only run `update`
> deployments, the statements above are sufficient.

**Role name:** `pz-helper-github-actions`

After creating the role, copy its **Role ARN**. It looks like
`arn:aws:iam::YOUR_ACCOUNT_ID:role/pz-helper-github-actions`.

**Verify:** In **IAM → Roles**, open the new role and confirm the
**Trust relationships** tab shows the GitHub OIDC provider, and the
**Permissions** tab lists the policy above.

---

## Step 2: Configure the GitHub Repository

The workflows read one secret and several variables. Secrets are encrypted and
hidden in logs; variables are plain configuration values.

### 2.1 Create the Secret

Go to **Repository → Settings → Secrets and variables → Actions → Secrets** and
add:

| Name | Value |
|------|-------|
| `AWS_ROLE_ARN` | `arn:aws:iam::YOUR_ACCOUNT_ID:role/pz-helper-github-actions` |

This is the ARN of the role you created in Step 1.

### 2.2 Create the Variables

Go to **Repository → Settings → Secrets and variables → Actions → Variables** and
add the following. The example values use generic placeholders — substitute your
own.

| Name | Example value | Description | Used by |
|------|---------------|-------------|---------|
| `WEBSITE_BUCKET_NAME` | `pz-helper-website-YOUR_ACCOUNT_ID` | S3 bucket that serves the website | `deploy-website.yml` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `EXXXXXXXXXXXXX` | CloudFront distribution ID for cache invalidation | `deploy-website.yml` |
| `WEBSITE_DOMAIN` | `zomboid.your-domain.com` | Public domain shown in the deployment summary | `deploy-website.yml` |
| `SYNC_USERNAME` | `admin` | Admin username passed to the `full` CloudFormation deployment | `deploy-sync.yml` |

> **Important:** The `deploy-website.yml` workflow only runs if
> `WEBSITE_BUCKET_NAME` is set. If that variable is empty, GitHub Actions skips
> the job.

You can look up the real values from the CloudFormation stack outputs. Note the
stack name is `pz-helper` (not `pz-helper-website`):

```bash
aws cloudformation describe-stacks \
  --stack-name pz-helper \
  --region eu-central-1 \
  --query 'Stacks[0].Outputs'
```

**Verify:** The **Actions → Variables** page lists all four names above, and the
secret `AWS_ROLE_ARN` appears (value hidden) under **Actions → Secrets**.

---

## Step 3: Use the Workflows

### Deploy Website

- **Automatically:** on every push to `main` that changes an `index*.html` file
  (for example `index.html`, `index-gist.html`, or `index-lambda.html`).
- **Manually:**
  1. Go to **Actions → Deploy Website → Run workflow**.
  2. Leave **Invalidate CloudFront cache** checked to serve the new files
     immediately, or uncheck it for a slightly faster deploy that relies on the
     existing cache expiring.

**Verify:** Open the workflow run and check the **Deployment Complete** summary.
It lists the uploaded files and the website URL.

### Deploy Sync Backend

This workflow is **manual only**, because the admin password cannot be passed
through CI.

1. Go to **Actions → Deploy Sync Backend → Run workflow**.
2. Choose an action:
   - `update` — packages `aws/lambda/index.mjs`, uploads it to the artifact
     bucket, and updates the Lambda function code. This is the fast, common path.
   - `full` — runs `aws cloudformation deploy` to update the existing
     `pz-helper` stack. This only works if the stack already exists; if it
     does not, the workflow fails with an error telling you to run `deploy.sh`
     locally first.

**Verify:** Open the workflow run and check the **Sync Backend Deployment
Complete** summary. It shows the chosen action and the Lambda Function URL.

> **Important:** The very first deployment (which sets the admin password) must
> be done locally with `deploy.sh`. See `DEPLOYMENT.md` for the initial setup.

---

## Troubleshooting

### "Error: Could not assume role"

- Confirm the trust policy's `sub` condition matches your repository exactly:
  `repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:*`.
- Confirm the `AWS_ROLE_ARN` secret contains the correct role ARN.
- Confirm the OIDC identity provider from Step 1.1 exists in your account.

### "AccessDenied" on S3, CloudFront, Lambda, or CloudFormation

- Review the role's permissions policy against the statements in Step 1.2.
- Confirm the resource names in the ARNs match your real bucket and function
  names (they use the `pz-helper` prefix and your account ID).
- For `full` CloudFormation deployments, confirm the role also has permission to
  modify the underlying stack resources (see the note in Step 1.2).

### The website workflow does not run

- It only runs when the `WEBSITE_BUCKET_NAME` variable is set. Add it under
  **Actions → Variables**.
- Check under **Actions** that workflows are enabled for the repository.

---

## Cost

GitHub Actions is **free** for public repositories with unlimited minutes.

For private repositories, GitHub includes a free monthly allowance (2,000
minutes/month on the Free plan) and bills per minute beyond that. Pricing and
allowances change over time, so check GitHub's current
[Actions billing documentation](https://docs.github.com/billing/managing-billing-for-github-actions)
for exact figures.
ct figures.
