#!/bin/bash
#
# PZ Skillbücher - AWS Deployment
#
# Usage:
#   ./deploy.sh                      # Deploy sync backend (Lambda + S3)
#   ./deploy.sh --update             # Update Lambda code only (faster)
#   ./deploy.sh --delete             # Delete the sync stack
#
#   ./deploy.sh website              # Deploy website (CloudFront + S3)
#   ./deploy.sh website --upload     # Upload HTML files only
#   ./deploy.sh website --delete     # Delete website stack
#
set -e

# ============================================================
# CONFIGURATION - Edit these values for your setup
# ============================================================
STACK_NAME="pz-skillbuecher"
WEBSITE_STACK_NAME="pz-skillbuecher-website"
REGION="eu-central-1"
USERNAME="admin"
BUCKET_PREFIX="pz-skillbuecher"

# Website configuration (only needed for 'website' command)
DOMAIN_NAME=""           # e.g., zomboid.example.com
HOSTED_ZONE_ID=""        # e.g., Z1234567890ABC
CERTIFICATE_ARN=""       # e.g., arn:aws:acm:us-east-1:123456789012:certificate/xxx

# ============================================================
# Derived values (usually no need to change)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ARTIFACT_BUCKET="${BUCKET_PREFIX}-artifacts-${ACCOUNT_ID}"
LAMBDA_ZIP="sync-function.zip"

# ============================================================
# Helper functions
# ============================================================
generate_password_hash() {
    local password="$1"
    node -e "
        const crypto = require('crypto');
        const password = process.argv[1];
        const iterations = 100000;
        const salt = crypto.randomBytes(16);
        const hash = crypto.pbkdf2Sync(password, salt, iterations, 32, 'sha256');
        console.log(iterations + ':' + salt.toString('hex') + ':' + hash.toString('hex'));
    " "$password"
}

# ============================================================
# WEBSITE DEPLOYMENT
# ============================================================
deploy_website() {
    local ACTION="$1"

    if [ "$ACTION" == "--delete" ]; then
        echo "Deleting website stack ${WEBSITE_STACK_NAME}..."
        aws cloudformation delete-stack \
            --stack-name "${WEBSITE_STACK_NAME}" \
            --region "${REGION}"
        
        echo "Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "${WEBSITE_STACK_NAME}" \
            --region "${REGION}" || true
        
        echo "Website stack deleted."
        echo "Note: S3 bucket retained. Delete manually if needed."
        exit 0
    fi

    # Check configuration
    if [ -z "$DOMAIN_NAME" ] || [ -z "$HOSTED_ZONE_ID" ] || [ -z "$CERTIFICATE_ARN" ]; then
        echo "Error: Website configuration incomplete."
        echo ""
        echo "Edit deploy.sh and set:"
        echo "  DOMAIN_NAME=\"zomboid.example.com\""
        echo "  HOSTED_ZONE_ID=\"Z1234567890ABC\""
        echo "  CERTIFICATE_ARN=\"arn:aws:acm:us-east-1:...\""
        echo ""
        echo "To create a certificate, run:"
        echo "  ./create-certificate.sh <domain> <hosted-zone-id>"
        exit 1
    fi

    echo "========================================"
    echo "PZ Skillbücher - Website Deployment"
    echo "========================================"
    echo "Stack:   ${WEBSITE_STACK_NAME}"
    echo "Domain:  ${DOMAIN_NAME}"
    echo "Region:  ${REGION}"
    echo "========================================"
    echo ""

    if [ "$ACTION" == "--upload" ]; then
        # Get bucket name from stack outputs
        BUCKET_NAME=$(aws cloudformation describe-stacks \
            --stack-name "${WEBSITE_STACK_NAME}" \
            --region "${REGION}" \
            --query "Stacks[0].Outputs[?OutputKey=='WebsiteBucketName'].OutputValue" \
            --output text 2>/dev/null)
        
        if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" == "None" ]; then
            echo "Error: Website stack not deployed yet. Run './deploy.sh website' first."
            exit 1
        fi
        
        DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
            --stack-name "${WEBSITE_STACK_NAME}" \
            --region "${REGION}" \
            --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
            --output text)
    else
        # Full website deployment
        echo "Deploying CloudFormation stack..."
        aws cloudformation deploy \
            --template-file "${SCRIPT_DIR}/website-stack.yaml" \
            --stack-name "${WEBSITE_STACK_NAME}" \
            --region "${REGION}" \
            --parameter-overrides \
                "DomainName=${DOMAIN_NAME}" \
                "HostedZoneId=${HOSTED_ZONE_ID}" \
                "CertificateArn=${CERTIFICATE_ARN}" \
                "BucketPrefix=${BUCKET_PREFIX}" \
            --no-fail-on-empty-changeset
        
        BUCKET_NAME=$(aws cloudformation describe-stacks \
            --stack-name "${WEBSITE_STACK_NAME}" \
            --region "${REGION}" \
            --query "Stacks[0].Outputs[?OutputKey=='WebsiteBucketName'].OutputValue" \
            --output text)
        
        DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
            --stack-name "${WEBSITE_STACK_NAME}" \
            --region "${REGION}" \
            --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
            --output text)
    fi

    # Upload HTML files
    echo ""
    echo "Uploading website files..."
    
    aws s3 cp "${SCRIPT_DIR}/../index.html" "s3://${BUCKET_NAME}/index.html" \
        --content-type "text/html; charset=utf-8"
    aws s3 cp "${SCRIPT_DIR}/../index-gist.html" "s3://${BUCKET_NAME}/index-gist.html" \
        --content-type "text/html; charset=utf-8"
    aws s3 cp "${SCRIPT_DIR}/../index-lambda.html" "s3://${BUCKET_NAME}/index-lambda.html" \
        --content-type "text/html; charset=utf-8"
    
    # Invalidate CloudFront cache
    echo "Invalidating CloudFront cache..."
    aws cloudfront create-invalidation \
        --distribution-id "${DISTRIBUTION_ID}" \
        --paths "/*" \
        --output text --query 'Invalidation.Id'
    
    echo ""
    echo "========================================"
    echo "Website deployed!"
    echo "========================================"
    echo ""
    echo "URL: https://${DOMAIN_NAME}"
    echo ""
    echo "Note: DNS propagation may take a few minutes."
    echo "      CloudFront cache invalidation takes 1-2 minutes."
    echo ""
    echo "To upload files only: ./deploy.sh website --upload"
    exit 0
}

# ============================================================
# SYNC BACKEND DEPLOYMENT
# ============================================================
deploy_sync() {
    local ACTION="$1"

    echo "========================================"
    echo "PZ Skillbücher - Sync Backend Deployment"
    echo "========================================"
    echo "Stack:    ${STACK_NAME}"
    echo "Region:   ${REGION}"
    echo "Account:  ${ACCOUNT_ID}"
    echo "Username: ${USERNAME}"
    echo "========================================"
    echo ""

    # Handle --delete
    if [ "$ACTION" == "--delete" ]; then
        echo "Deleting stack ${STACK_NAME}..."
        aws cloudformation delete-stack \
            --stack-name "${STACK_NAME}" \
            --region "${REGION}"
        
        echo "Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "${STACK_NAME}" \
            --region "${REGION}" || true
        
        echo ""
        echo "Stack deleted."
        echo "Note: S3 buckets are retained. Delete manually if needed:"
        echo "  - ${ARTIFACT_BUCKET}"
        echo "  - ${BUCKET_PREFIX}-progress-${ACCOUNT_ID}"
        exit 0
    fi

    # Ensure artifact bucket exists
    echo "Checking artifact bucket..."
    if ! aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" 2>/dev/null; then
        echo "Creating artifact bucket: ${ARTIFACT_BUCKET}"
        aws s3api create-bucket \
            --bucket "${ARTIFACT_BUCKET}" \
            --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
        
        aws s3api put-public-access-block \
            --bucket "${ARTIFACT_BUCKET}" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    else
        echo "Artifact bucket exists."
    fi

    # Package Lambda
    echo ""
    echo "Packaging Lambda function..."
    cd "${SCRIPT_DIR}/lambda"
    rm -f "${LAMBDA_ZIP}"
    zip -j "${LAMBDA_ZIP}" index.mjs
    
    echo "Uploading to S3..."
    aws s3 cp "${LAMBDA_ZIP}" "s3://${ARTIFACT_BUCKET}/lambda/${LAMBDA_ZIP}"
    cd "${SCRIPT_DIR}"

    # Handle --update (Lambda code only)
    if [ "$ACTION" == "--update" ]; then
        echo ""
        echo "Updating Lambda function code..."
        aws lambda update-function-code \
            --function-name "${BUCKET_PREFIX}-sync" \
            --s3-bucket "${ARTIFACT_BUCKET}" \
            --s3-key "lambda/${LAMBDA_ZIP}" \
            --region "${REGION}" \
            --output text --query 'FunctionArn'
        
        echo ""
        echo "Lambda code updated!"
        exit 0
    fi

    # Get or generate password hash
    echo ""
    PASSWORD_HASH=""
    
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
        echo "Stack exists. Reusing existing password hash."
        echo "(Use --delete first if you want to change the password)"
        
        read -p "Press Enter to keep existing password, or type 'new' for new password: " CHANGE_PW
        
        if [ "$CHANGE_PW" != "new" ]; then
            PASSWORD_HASH="USE_PREVIOUS"
        fi
    fi

    if [ "$PASSWORD_HASH" != "USE_PREVIOUS" ]; then
        echo "Enter password for user '${USERNAME}':"
        read -s PASSWORD
        echo ""
        
        if [ -z "$PASSWORD" ]; then
            echo "Error: Password cannot be empty."
            exit 1
        fi
        
        echo "Confirm password:"
        read -s PASSWORD_CONFIRM
        echo ""
        
        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            echo "Error: Passwords do not match."
            exit 1
        fi
        
        echo "Generating password hash..."
        PASSWORD_HASH=$(generate_password_hash "$PASSWORD")
    fi

    # Deploy CloudFormation stack
    echo ""
    echo "Deploying CloudFormation stack..."

    if [ "$PASSWORD_HASH" == "USE_PREVIOUS" ]; then
        aws cloudformation deploy \
            --template-file "${SCRIPT_DIR}/stack.yaml" \
            --stack-name "${STACK_NAME}" \
            --region "${REGION}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --parameter-overrides \
                "Username=${USERNAME}" \
                "BucketPrefix=${BUCKET_PREFIX}" \
            --no-fail-on-empty-changeset
    else
        aws cloudformation deploy \
            --template-file "${SCRIPT_DIR}/stack.yaml" \
            --stack-name "${STACK_NAME}" \
            --region "${REGION}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --parameter-overrides \
                "Username=${USERNAME}" \
                "PasswordHash=${PASSWORD_HASH}" \
                "BucketPrefix=${BUCKET_PREFIX}" \
            --no-fail-on-empty-changeset
    fi

    # Get outputs
    echo ""
    echo "========================================"
    echo "Deployment complete!"
    echo "========================================"
    echo ""

    FUNCTION_URL=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='FunctionUrl'].OutputValue" \
        --output text)

    echo "Function URL:"
    echo "  ${FUNCTION_URL}"
    echo ""
    echo "Username: ${USERNAME}"
    echo ""
    echo "Use these values in the app (index-lambda.html):"
    echo "  - API URL: ${FUNCTION_URL}"
    echo "  - Username: ${USERNAME}"
    echo "  - Password: (the password you entered)"
    echo ""
    echo "To update Lambda code later: ./deploy.sh --update"
    echo "To delete everything: ./deploy.sh --delete"
}

# ============================================================
# MAIN
# ============================================================
case "$1" in
    website)
        deploy_website "$2"
        ;;
    --delete|--update|"")
        deploy_sync "$1"
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        echo "Usage:"
        echo "  ./deploy.sh                      # Deploy sync backend"
        echo "  ./deploy.sh --update             # Update Lambda code only"
        echo "  ./deploy.sh --delete             # Delete sync stack"
        echo ""
        echo "  ./deploy.sh website              # Deploy website"
        echo "  ./deploy.sh website --upload     # Upload files only"
        echo "  ./deploy.sh website --delete     # Delete website stack"
        exit 1
        ;;
esac
