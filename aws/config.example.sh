#!/bin/bash
#
# PZ Skill Books - AWS Configuration
#
# Copy this file to config.sh and edit the values:
#   cp config.example.sh config.sh
#

# ============================================================
# REQUIRED
# ============================================================

# AWS region (e.g., eu-central-1, us-east-1)
REGION="eu-central-1"

# Login username
USERNAME="zombie"

# Unique prefix for AWS resources (lowercase, no spaces)
# This must be globally unique across all AWS accounts!
BUCKET_PREFIX="pz-skillbooks-CHANGEME"

# ============================================================
# OPTIONAL - Custom Domain
# ============================================================
# Leave empty for basic S3 website hosting (http://bucket.s3-website.region.amazonaws.com)
# Fill in for custom domain with HTTPS (https://zomboid.yourdomain.com)

# Your domain (e.g., zomboid.nubilum.net)
DOMAIN_NAME=""

# Route53 Hosted Zone ID - find in AWS Console → Route53 → Hosted Zones
HOSTED_ZONE_ID=""
