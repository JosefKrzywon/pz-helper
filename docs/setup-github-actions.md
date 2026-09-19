# GitHub Actions Setup

This guide explains how to set up automatic deployments via GitHub Actions.

## Overview

There are two workflows:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| **deploy-website.yml** | Push to `main` (HTML files) or manual | Uploads HTML files to S3, invalidates CloudFront |
| **deploy-sync.yml** | Manual only | Updates Lambda code or CloudFormation stack |

## Prerequisites

1. AWS resources are already deployed (via `deploy.sh`)
2. You have admin access to the GitHub repository

## Step 1: Create AWS IAM Role for GitHub Actions

GitHub Actions uses OIDC (OpenID Connect) for secure authentication — no long-lived access keys needed.

### 1.1 Create Identity Provider

In the AWS Console under **IAM → Identity providers → Add provider**:

- **Provider type:** OpenID Connect
- **Provider URL:** `https://token.actions.githubusercontent.com`
- **Audience:** `sts.amazonaws.com`

### 1.2 Create IAM Role

Create a new role under **IAM → Roles → Create role**:

**Trust Policy:**
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
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/pz-skillbooks:*"
        }
      }
    }
  ]
}
```

Replace:
- `YOUR_ACCOUNT_ID` with your AWS Account ID
- `YOUR_GITHUB_USERNAME` with your GitHub username

**Permissions Policy:**
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
        "arn:aws:s3:::pz-skillbooks-website-YOUR_ACCOUNT_ID",
        "arn:aws:s3:::pz-skillbooks-website-YOUR_ACCOUNT_ID/*"
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
        "arn:aws:s3:::pz-skillbooks-artifacts-YOUR_ACCOUNT_ID",
        "arn:aws:s3:::pz-skillbooks-artifacts-YOUR_ACCOUNT_ID/*"
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
      "Resource": "arn:aws:lambda:eu-central-1:YOUR_ACCOUNT_ID:function:pz-skillbooks-sync"
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
      "Resource": "arn:aws:cloudformation:eu-central-1:YOUR_ACCOUNT_ID:stack/pz-skillbooks/*"
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

**Role Name:** `pz-skillbooks-github-actions`

Copy the **Role ARN** (e.g. `arn:aws:iam::123456789012:role/pz-skillbooks-github-actions`).

## Step 2: Configure GitHub Repository

### 2.1 Create Secret

Go to **Repository → Settings → Secrets and variables → Actions → Secrets**:

| Name | Value |
|------|-------|
| `AWS_ROLE_ARN` | `arn:aws:iam::YOUR_ACCOUNT_ID:role/pz-skillbooks-github-actions` |

### 2.2 Create Variables

Go to **Repository → Settings → Secrets and variables → Actions → Variables**:

| Name | Value | Description |
|------|-------|-------------|
| `WEBSITE_BUCKET_NAME` | `pz-skillbooks-website-123456789012` | S3 bucket for the website |
| `CLOUDFRONT_DISTRIBUTION_ID` | `E1234567890ABC` | CloudFront Distribution ID |
| `WEBSITE_DOMAIN` | `zomboid.example.com` | Domain for the website |
| `SYNC_USERNAME` | `admin` | Username for the sync API |

You can find the values in the CloudFormation stack outputs:
```bash
aws cloudformation describe-stacks --stack-name pz-skillbooks-website \
  --query 'Stacks[0].Outputs'
```

## Step 3: Use the Workflows

### Deploy Website

**Automatically:** On every push to `main` that changes `index*.html`.

**Manually:** 
1. Go to **Actions → Deploy Website → Run workflow**
2. Optional: Uncheck "Invalidate CloudFront cache" for faster deployment

### Deploy Sync Backend

**Manual only** (for password security):

1. Go to **Actions → Deploy Sync Backend → Run workflow**
2. Choose action:
   - `update`: Update Lambda code only (fast)
   - `full`: Update CloudFormation stack

**Important:** The initial deployment with password must be done locally via `deploy.sh`!

## Troubleshooting

### "Error: Could not assume role"

- Check if the Trust Policy contains the correct GitHub username
- Check if `AWS_ROLE_ARN` is set correctly

### "AccessDenied" on S3/CloudFront

- Check the Permissions Policy of the IAM role
- Make sure the bucket names are correct

### Website workflow doesn't run

- The workflow only runs if `WEBSITE_BUCKET_NAME` is set as a variable
- Check under Actions if the workflow is enabled

## Cost

GitHub Actions is **free** for public repositories (unlimited minutes).

For private repositories: 2,000 minutes/month free, then ~$0.008/minute.
