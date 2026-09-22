#!/bin/bash
#
# PZ Skill Books - AWS Deployment
#
# Deploys everything in one command:
# - Lambda + DynamoDB for sync
# - S3 + CloudFront for website hosting
# - Custom domain with SSL certificate (optional)
#
# Usage:
#   ./deploy.sh              # Deploy (interactive setup on first run)
#   ./deploy.sh --upload     # Upload HTML files only
#   ./deploy.sh --delete     # Delete all stacks
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# ============================================================
# COLORS
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
info() { echo -e "${BLUE}→${NC} $1"; }
header() { echo -e "\n${GREEN}==== $1 ====${NC}\n"; }

# ============================================================
# FIRST-TIME SETUP
# ============================================================
first_time_setup() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║          PZ Skill Books - AWS Setup Wizard                 ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Step 1: Check prerequisites (AWS CLI, zip, openssl)
    header "Step 1/5: Checking Prerequisites"
    
    local errors=0
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        fail "AWS CLI not installed"
        echo ""
        echo "Install the AWS CLI:"
        echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        echo ""
        errors=$((errors + 1))
    else
        ok "AWS CLI installed"
    fi
    
    # Check zip or PowerShell (for creating Lambda package)
    if command -v zip &> /dev/null; then
        ok "zip installed"
    elif command -v powershell.exe &> /dev/null; then
        ok "PowerShell available (will use Compress-Archive for zip)"
    else
        fail "Neither zip nor PowerShell found"
        echo ""
        echo "Install zip or ensure PowerShell is available"
        echo ""
        errors=$((errors + 1))
    fi
    
    # Check openssl
    if ! command -v openssl &> /dev/null; then
        fail "openssl not installed"
        echo ""
        echo "Install openssl:"
        echo "  Windows: Usually included with Git Bash"
        echo "  macOS:   brew install openssl"
        echo "  Linux:   sudo apt install openssl"
        echo ""
        errors=$((errors + 1))
    else
        ok "openssl installed"
    fi
    
    if [ $errors -gt 0 ]; then
        echo ""
        fail "Please install missing tools and run again."
        exit 1
    fi
    
    # Step 2: Check AWS credentials
    header "Step 2/5: Checking AWS Connection"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        fail "AWS credentials not configured or invalid"
        echo ""
        echo "Configure your AWS credentials:"
        echo "  aws configure"
        echo ""
        echo "You'll need:"
        echo "  - AWS Access Key ID"
        echo "  - AWS Secret Access Key"
        echo "  - Default region (e.g., eu-central-1)"
        echo ""
        echo "Get credentials from AWS Console → IAM → Users → Security credentials"
        echo "  https://console.aws.amazon.com/iam/"
        echo ""
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    ok "Connected to AWS"
    echo "   Account: $ACCOUNT_ID"
    echo "   Identity: $identity"
    
    # Step 3: Check AWS permissions
    header "Step 3/5: Checking AWS Permissions"
    
    local perm_errors=0
    
    # Check S3 permissions
    if aws s3 ls &> /dev/null; then
        ok "S3 access"
    else
        fail "No S3 access"
        perm_errors=$((perm_errors + 1))
    fi
    
    # Check CloudFormation permissions
    if aws cloudformation list-stacks --max-items 1 &> /dev/null; then
        ok "CloudFormation access"
    else
        fail "No CloudFormation access"
        perm_errors=$((perm_errors + 1))
    fi
    
    # Check Lambda permissions
    if aws lambda list-functions --max-items 1 &> /dev/null; then
        ok "Lambda access"
    else
        fail "No Lambda access"
        perm_errors=$((perm_errors + 1))
    fi
    
    # Check DynamoDB permissions
    if aws dynamodb list-tables --max-items 1 &> /dev/null; then
        ok "DynamoDB access"
    else
        fail "No DynamoDB access"
        perm_errors=$((perm_errors + 1))
    fi
    
    # Check Route53 permissions
    if aws route53 list-hosted-zones --max-items 1 &> /dev/null; then
        ok "Route53 access"
    else
        fail "No Route53 access"
        perm_errors=$((perm_errors + 1))
    fi
    
    # Check ACM permissions
    if aws acm list-certificates --region us-east-1 --max-items 1 &> /dev/null; then
        ok "ACM (Certificate Manager) access"
    else
        fail "No ACM access"
        perm_errors=$((perm_errors + 1))
    fi
    
    # Check IAM permissions (needed for Lambda role)
    if aws iam list-roles --max-items 1 &> /dev/null; then
        ok "IAM access"
    else
        fail "No IAM access"
        perm_errors=$((perm_errors + 1))
    fi
    
    if [ $perm_errors -gt 0 ]; then
        echo ""
        warn "Missing some AWS permissions"
        echo ""
        echo "Your IAM user/role needs these permissions:"
        echo "  - AmazonS3FullAccess"
        echo "  - AWSCloudFormationFullAccess"
        echo "  - AWSLambda_FullAccess"
        echo "  - AmazonDynamoDBFullAccess"
        echo "  - AmazonRoute53FullAccess"
        echo "  - AWSCertificateManagerFullAccess"
        echo "  - IAMFullAccess (or at least iam:CreateRole, iam:AttachRolePolicy)"
        echo ""
        echo "Or use AdministratorAccess for simplicity."
        echo ""
        read -p "Continue anyway? (deployment may fail) [y/N] " cont
        if [ "$cont" != "y" ] && [ "$cont" != "Y" ]; then
            exit 1
        fi
    fi
    
    # Step 4: Check Route53 hosted zones
    header "Step 4/5: Domain Configuration"
    
    echo "Checking Route53 for available domains..."
    echo ""
    
    local zones=$(aws route53 list-hosted-zones --query 'HostedZones[?Config.PrivateZone==`false`].[Id,Name]' --output text 2>/dev/null || echo "")
    
    if [ -z "$zones" ]; then
        warn "No public hosted zones found in Route53"
        echo ""
        echo "You have two options:"
        echo ""
        echo "  1) Deploy WITHOUT custom domain"
        echo "     → You'll get an S3 website URL (works fine, just longer)"
        echo ""
        echo "  2) Set up a domain in Route53 first"
        echo "     → https://console.aws.amazon.com/route53/"
        echo ""
        read -p "Continue without custom domain? [Y/n] " no_domain
        
        if [ "$no_domain" == "n" ] || [ "$no_domain" == "N" ]; then
            echo ""
            echo "Set up your domain in Route53, then run this script again."
            exit 0
        fi
        
        DOMAIN_NAME=""
        HOSTED_ZONE_ID=""
    else
        echo "Found hosted zones:"
        echo ""
        
        local i=1
        local zone_ids=()
        local zone_names=()
        
        while IFS=$'\t' read -r zone_id zone_name; do
            # Clean up zone ID (remove /hostedzone/ prefix)
            zone_id=$(echo "$zone_id" | sed 's|/hostedzone/||')
            zone_name=$(echo "$zone_name" | sed 's/\.$//')  # Remove trailing dot
            
            zone_ids+=("$zone_id")
            zone_names+=("$zone_name")
            
            echo "  $i) $zone_name"
            i=$((i + 1))
        done <<< "$zones"
        
        echo "  0) No custom domain (use S3 URL)"
        echo ""
        
        while true; do
            read -p "Select domain [0-$((i-1))]: " selection
            
            if [ "$selection" == "0" ]; then
                DOMAIN_NAME=""
                HOSTED_ZONE_ID=""
                break
            elif [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ] 2>/dev/null; then
                local idx=$((selection - 1))
                local base_domain="${zone_names[$idx]}"
                HOSTED_ZONE_ID="${zone_ids[$idx]}"
                
                echo ""
                echo "Selected: $base_domain (Zone ID: $HOSTED_ZONE_ID)"
                echo ""
                read -p "Subdomain (e.g., 'zomboid' for zomboid.$base_domain): " subdomain
                
                if [ -z "$subdomain" ]; then
                    DOMAIN_NAME="$base_domain"
                else
                    DOMAIN_NAME="${subdomain}.${base_domain}"
                fi
                
                echo ""
                ok "Domain: $DOMAIN_NAME"
                break
            else
                echo "Invalid selection. Enter 0-$((i-1))"
            fi
        done
    fi
    
    # Step 5: Get remaining settings
    header "Step 5/6: Final Settings"
    
    # Region
    local default_region=$(aws configure get region 2>/dev/null || echo "eu-central-1")
    read -p "AWS Region [$default_region]: " input_region
    REGION="${input_region:-$default_region}"
    
    # Username
    read -p "Login username [zombie]: " input_username
    USERNAME="${input_username:-zombie}"
    
    # Bucket prefix
    local default_prefix="pz-skillbooks-$(echo $ACCOUNT_ID | tail -c 5)"
    read -p "Resource prefix [$default_prefix]: " input_prefix
    BUCKET_PREFIX="${input_prefix:-$default_prefix}"
    
    # Step 6: Cost Protection
    header "Step 6/6: Cost Protection (DDoS/Budget)"
    
    echo "AWS costs can spike from unexpected traffic or DDoS attacks."
    echo "This setup can automatically disable your site if costs exceed a limit."
    echo ""
    echo "How it works:"
    echo "  - AWS Budget monitors your costs"
    echo "  - At 50% and 80%: You get email alerts"
    echo "  - At 100%: CloudFront gets automatically disabled"
    echo "  - Lambda API calls are rate-limited (max concurrent executions)"
    echo ""
    
    read -p "Enable cost protection? [Y/n]: " enable_budget
    if [ "$enable_budget" == "n" ] || [ "$enable_budget" == "N" ]; then
        BUDGET_LIMIT=0
        BUDGET_EMAIL=""
        LAMBDA_CONCURRENCY=10
        warn "Cost protection disabled - no spending limit!"
    else
        # Budget limit
        echo ""
        echo "Monthly budget limit (USD):"
        echo "  Recommended: \$5 for personal use"
        echo "  Expected normal usage: <\$1/month"
        echo ""
        read -p "Budget limit in USD [5]: " input_budget
        BUDGET_LIMIT="${input_budget:-5}"
        
        # Validate number
        if ! [[ "$BUDGET_LIMIT" =~ ^[0-9]+$ ]]; then
            warn "Invalid number, using default: 5"
            BUDGET_LIMIT=5
        fi
        
        # Email for alerts
        echo ""
        read -p "Email for budget alerts (optional, press Enter to skip): " input_email
        BUDGET_EMAIL="${input_email:-}"
        
        # Lambda concurrency
        echo ""
        echo "Lambda rate limit (max concurrent API executions):"
        echo "  5 = Very restrictive (recommended for low traffic)"
        echo "  10 = Normal"
        echo "  25 = Higher traffic"
        echo ""
        read -p "Lambda concurrency limit [5]: " input_concurrency
        LAMBDA_CONCURRENCY="${input_concurrency:-5}"
        
        if ! [[ "$LAMBDA_CONCURRENCY" =~ ^[0-9]+$ ]] || [ "$LAMBDA_CONCURRENCY" -lt 1 ]; then
            warn "Invalid number, using default: 5"
            LAMBDA_CONCURRENCY=5
        fi
        
        ok "Cost protection enabled"
        echo "   Budget: \$${BUDGET_LIMIT}/month"
        if [ -n "$BUDGET_EMAIL" ]; then
            echo "   Alerts: $BUDGET_EMAIL"
        fi
        echo "   Lambda limit: $LAMBDA_CONCURRENCY concurrent"
    fi
    
    # Save config
    header "Saving Configuration"
    
    cat > "$CONFIG_FILE" << EOF
#!/bin/bash
# PZ Skill Books - AWS Configuration
# Generated: $(date)

REGION="$REGION"
USERNAME="$USERNAME"
BUCKET_PREFIX="$BUCKET_PREFIX"
DOMAIN_NAME="$DOMAIN_NAME"
HOSTED_ZONE_ID="$HOSTED_ZONE_ID"

# Cost Protection
BUDGET_LIMIT="$BUDGET_LIMIT"
BUDGET_EMAIL="$BUDGET_EMAIL"
LAMBDA_CONCURRENCY="$LAMBDA_CONCURRENCY"
EOF
    
    ok "Config saved to config.sh"
    echo ""
    echo "Settings:"
    echo "  Region:          $REGION"
    echo "  Username:        $USERNAME"
    echo "  Prefix:          $BUCKET_PREFIX"
    if [ -n "$DOMAIN_NAME" ]; then
        echo "  Domain:          $DOMAIN_NAME"
        echo "  Zone ID:         $HOSTED_ZONE_ID"
    else
        echo "  Domain:          (none - using S3 URL)"
    fi
    echo "  Budget Limit:    \$${BUDGET_LIMIT}/month"
    echo "  Lambda Limit:    $LAMBDA_CONCURRENCY concurrent"
    echo ""
    
    read -p "Continue with deployment? [Y/n] " confirm
    if [ "$confirm" == "n" ] || [ "$confirm" == "N" ]; then
        echo ""
        echo "Config saved. Run ./deploy.sh again when ready."
        exit 0
    fi
}

# ============================================================
# CHECK FOR EXISTING RESOURCES (from failed runs)
# ============================================================
check_existing_resources() {
    local found=0
    local resources=""
    
    # Check for existing stack
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
        local stack_status=$(aws cloudformation describe-stacks \
            --stack-name "${STACK_NAME}" \
            --region "${REGION}" \
            --query 'Stacks[0].StackStatus' \
            --output text)
        resources="${resources}\n  - CloudFormation stack '${STACK_NAME}' (${stack_status})"
        found=$((found + 1))
    fi
    
    # Check for artifact bucket
    if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" 2>/dev/null; then
        resources="${resources}\n  - S3 bucket '${ARTIFACT_BUCKET}'"
        found=$((found + 1))
    fi
    
    # Check for website bucket
    if aws s3api head-bucket --bucket "${WEBSITE_BUCKET}" 2>/dev/null; then
        resources="${resources}\n  - S3 bucket '${WEBSITE_BUCKET}'"
        found=$((found + 1))
    fi
    
    # Check for certificate (if using custom domain)
    if [ -n "$DOMAIN_NAME" ]; then
        local cert=$(aws acm list-certificates \
            --region us-east-1 \
            --query "CertificateSummaryList[?DomainName=='${DOMAIN_NAME}'].CertificateArn" \
            --output text 2>/dev/null)
        if [ -n "$cert" ] && [ "$cert" != "None" ]; then
            resources="${resources}\n  - ACM certificate for '${DOMAIN_NAME}'"
            found=$((found + 1))
        fi
    fi
    
    if [ $found -gt 0 ]; then
        echo ""
        warn "Found existing resources from previous deployment:"
        echo -e "$resources"
        echo ""
        echo "Options:"
        echo "  1) Continue - reuse existing resources (recommended)"
        echo "  2) Delete all and start fresh"
        echo "  3) Cancel"
        echo ""
        read -p "Choice [1]: " choice
        
        case "${choice:-1}" in
            1)
                ok "Continuing with existing resources"
                ;;
            2)
                echo ""
                info "Cleaning up existing resources..."
                cleanup_resources
                ok "Cleanup complete. Starting fresh deployment."
                ;;
            3)
                echo "Cancelled."
                exit 0
                ;;
            *)
                echo "Invalid choice. Continuing with existing resources."
                ;;
        esac
    fi
}

cleanup_resources() {
    # Delete CloudFormation stack first (it will delete most resources)
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
        info "Deleting CloudFormation stack..."
        aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
        echo -n "Waiting for stack deletion"
        while aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; do
            echo -n "."
            sleep 5
        done
        echo ""
        ok "Stack deleted"
    fi
    
    # Empty and delete artifact bucket
    if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" 2>/dev/null; then
        info "Deleting artifact bucket..."
        aws s3 rm "s3://${ARTIFACT_BUCKET}" --recursive --quiet 2>/dev/null || true
        aws s3api delete-bucket --bucket "${ARTIFACT_BUCKET}" --region "${REGION}" 2>/dev/null || true
        ok "Artifact bucket deleted"
    fi
    
    # Empty and delete website bucket (if exists outside stack)
    if aws s3api head-bucket --bucket "${WEBSITE_BUCKET}" 2>/dev/null; then
        info "Deleting website bucket..."
        aws s3 rm "s3://${WEBSITE_BUCKET}" --recursive --quiet 2>/dev/null || true
        aws s3api delete-bucket --bucket "${WEBSITE_BUCKET}" --region "${REGION}" 2>/dev/null || true
        ok "Website bucket deleted"
    fi
    
    # Delete certificate
    if [ -n "$DOMAIN_NAME" ]; then
        local cert=$(aws acm list-certificates \
            --region us-east-1 \
            --query "CertificateSummaryList[?DomainName=='${DOMAIN_NAME}'].CertificateArn" \
            --output text 2>/dev/null)
        if [ -n "$cert" ] && [ "$cert" != "None" ]; then
            info "Deleting certificate..."
            # Need to wait a bit for CloudFront to release it
            aws acm delete-certificate --certificate-arn "$cert" --region us-east-1 2>/dev/null || \
                warn "Could not delete certificate (may be in use). Delete manually later."
        fi
    fi
}

# ============================================================
# LOAD CONFIGURATION
# ============================================================
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        first_time_setup
    fi
    
    source "$CONFIG_FILE"
    
    # Validate required settings
    if [ -z "$REGION" ] || [ -z "$USERNAME" ] || [ -z "$BUCKET_PREFIX" ]; then
        warn "Config incomplete. Running setup wizard..."
        first_time_setup
        source "$CONFIG_FILE"
    fi
    
    # Set defaults for cost protection if not in config (for old configs)
    BUDGET_LIMIT="${BUDGET_LIMIT:-5}"
    BUDGET_EMAIL="${BUDGET_EMAIL:-}"
    LAMBDA_CONCURRENCY="${LAMBDA_CONCURRENCY:-5}"

    # Session secret for signing login cookies. Generated once and persisted
    # in config.sh so it stays stable across deploys (rotating it on every
    # deploy would invalidate all existing login sessions).
    if [ -z "$SESSION_SECRET" ]; then
        SESSION_SECRET=$(openssl rand -hex 32)
        cat >> "$CONFIG_FILE" << EOF

# Session secret (auto-generated, do not share)
SESSION_SECRET="$SESSION_SECRET"
EOF
        ok "Generated new session secret (saved to config.sh)"
    fi
    
    # Get account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    
    # Derived values
    STACK_NAME="${BUCKET_PREFIX}"
    ARTIFACT_BUCKET="${BUCKET_PREFIX}-artifacts-${ACCOUNT_ID}"
    WEBSITE_BUCKET="${BUCKET_PREFIX}-website-${ACCOUNT_ID}"
    
    # Check if using custom domain
    if [ -n "$DOMAIN_NAME" ] && [ -n "$HOSTED_ZONE_ID" ]; then
        USE_CUSTOM_DOMAIN=true
    else
        USE_CUSTOM_DOMAIN=false
    fi
}

# ============================================================
# PREREQUISITE CHECKS (quick version for subsequent runs)
# ============================================================
check_prerequisites() {
    local errors=0
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        fail "AWS CLI not found"
        errors=$((errors + 1))
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        fail "AWS credentials invalid"
        errors=$((errors + 1))
    fi
    
    # Check zip / python3 / PowerShell (one of them needed to package Lambda)
    if ! command -v zip &> /dev/null && ! command -v python3 &> /dev/null && ! command -v powershell.exe &> /dev/null; then
        fail "No zip tool found (need zip, python3, or PowerShell)"
        errors=$((errors + 1))
    fi
    
    # Check openssl
    if ! command -v openssl &> /dev/null; then
        fail "openssl not found"
        errors=$((errors + 1))
    fi
    
    if [ $errors -gt 0 ]; then
        exit 1
    fi
}

# ============================================================
# HELPER FUNCTIONS
# ============================================================
generate_password_hash() {
    local password="$1"
    local salt=$(openssl rand -hex 16)
    local hash=$(printf '%s%s' "$salt" "$password" | openssl dgst -sha256 | awk '{print $2}')
    echo "sha256:${salt}:${hash}"
}

wait_for_certificate() {
    local cert_arn="$1"
    local max_attempts=30
    local attempt=0
    
    echo -n "Waiting for certificate validation"
    while [ $attempt -lt $max_attempts ]; do
        local status=$(aws acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --region us-east-1 \
            --query 'Certificate.Status' \
            --output text)
        
        if [ "$status" == "ISSUED" ]; then
            echo ""
            ok "Certificate issued!"
            return 0
        fi
        
        echo -n "."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo ""
    fail "Certificate validation timed out"
    echo "Check AWS Console → Certificate Manager (us-east-1)"
    exit 1
}

# ============================================================
# CERTIFICATE MANAGEMENT
# ============================================================
ensure_certificate() {
    header "SSL Certificate"
    
    # Check if certificate already exists
    local existing_cert=$(aws acm list-certificates \
        --region us-east-1 \
        --query "CertificateSummaryList[?DomainName=='${DOMAIN_NAME}'].CertificateArn" \
        --output text)
    
    if [ -n "$existing_cert" ] && [ "$existing_cert" != "None" ]; then
        local status=$(aws acm describe-certificate \
            --certificate-arn "$existing_cert" \
            --region us-east-1 \
            --query 'Certificate.Status' \
            --output text)
        
        if [ "$status" == "ISSUED" ]; then
            ok "Using existing certificate"
            CERTIFICATE_ARN="$existing_cert"
            return 0
        fi
    fi
    
    # Create new certificate
    info "Creating SSL certificate for ${DOMAIN_NAME}..."
    CERTIFICATE_ARN=$(aws acm request-certificate \
        --domain-name "${DOMAIN_NAME}" \
        --validation-method DNS \
        --region us-east-1 \
        --tags "Key=Project,Value=${BUCKET_PREFIX}" \
        --query 'CertificateArn' \
        --output text)
    
    ok "Certificate requested: $CERTIFICATE_ARN"
    
    # Wait for DNS validation records
    sleep 5
    
    # Get validation record
    local validation_info=$(aws acm describe-certificate \
        --certificate-arn "$CERTIFICATE_ARN" \
        --region us-east-1 \
        --query 'Certificate.DomainValidationOptions[0].ResourceRecord')
    
    local record_name=$(echo "$validation_info" | grep -o '"Name": "[^"]*"' | cut -d'"' -f4)
    local record_value=$(echo "$validation_info" | grep -o '"Value": "[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$record_name" ] || [ -z "$record_value" ]; then
        fail "Could not get validation records"
        exit 1
    fi
    
    # Create DNS validation record
    info "Creating DNS validation record..."
    local change_batch=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${record_name}",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "${record_value}"}]
    }
  }]
}
EOF
)
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --change-batch "$change_batch" \
        --output text > /dev/null
    
    ok "DNS validation record created"
    
    wait_for_certificate "$CERTIFICATE_ARN"
}

# ============================================================
# ARTIFACT BUCKET
# ============================================================
ensure_artifact_bucket() {
    header "Artifact Bucket"
    
    if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" 2>/dev/null; then
        ok "Artifact bucket exists"
    else
        info "Creating artifact bucket..."
        
        if [ "$REGION" == "us-east-1" ]; then
            aws s3api create-bucket \
                --bucket "${ARTIFACT_BUCKET}" \
                --region "${REGION}"
        else
            aws s3api create-bucket \
                --bucket "${ARTIFACT_BUCKET}" \
                --region "${REGION}" \
                --create-bucket-configuration LocationConstraint="${REGION}"
        fi
        
        aws s3api put-public-access-block \
            --bucket "${ARTIFACT_BUCKET}" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        # Tag the bucket
        aws s3api put-bucket-tagging \
            --bucket "${ARTIFACT_BUCKET}" \
            --tagging "TagSet=[{Key=Project,Value=${BUCKET_PREFIX}}]"
        
        ok "Artifact bucket created"
    fi
}

# ============================================================
# LAMBDA DEPLOYMENT
# ============================================================
deploy_lambda() {
    header "Lambda Function"
    
    info "Packaging Lambda code..."
    cd "${SCRIPT_DIR}/lambda"
    rm -f sync-function.zip
    
    # Package the Lambda code. Try tools in order of availability so this
    # works on Linux, macOS and Windows:
    #   1) zip        (Linux/macOS, Git Bash)
    #   2) python3    (cross-platform fallback, almost always present on *nix)
    #   3) powershell (Windows without zip)
    if command -v zip &> /dev/null; then
        zip -j sync-function.zip index.mjs > /dev/null
    elif command -v python3 &> /dev/null; then
        python3 -c "import zipfile; z=zipfile.ZipFile('sync-function.zip','w',zipfile.ZIP_DEFLATED); z.write('index.mjs','index.mjs'); z.close()"
    elif command -v powershell.exe &> /dev/null; then
        powershell.exe -Command "Compress-Archive -Path 'index.mjs' -DestinationPath 'sync-function.zip' -Force"
    else
        fail "No zip tool found. Install 'zip' or 'python3'."
        exit 1
    fi
    
    if [ ! -f sync-function.zip ]; then
        fail "Failed to create Lambda package"
        exit 1
    fi
    
    info "Uploading to S3..."
    aws s3 cp sync-function.zip "s3://${ARTIFACT_BUCKET}/lambda/sync-function.zip" --quiet
    ok "Lambda package uploaded"
    
    cd "${SCRIPT_DIR}"
}

# ============================================================
# PASSWORD SETUP
# ============================================================
setup_password() {
    header "Password Setup"
    
    # Check if stack exists and has a password
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
        echo "Stack exists. Keep existing password? [Y/n]"
        read -r KEEP_PW
        if [ "$KEEP_PW" != "n" ] && [ "$KEEP_PW" != "N" ]; then
            PASSWORD_HASH="USE_PREVIOUS"
            ok "Keeping existing password"
            return 0
        fi
    fi
    
    echo "Enter password for user '${USERNAME}':"
    read -s PASSWORD
    echo ""
    
    if [ -z "$PASSWORD" ]; then
        fail "Password cannot be empty"
        exit 1
    fi
    
    echo "Confirm password:"
    read -s PASSWORD_CONFIRM
    echo ""
    
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        fail "Passwords do not match"
        exit 1
    fi
    
    PASSWORD_HASH=$(generate_password_hash "$PASSWORD")
    ok "Password hash generated"
}

# ============================================================
# CLOUDFORMATION DEPLOYMENT
# ============================================================
deploy_stack() {
    header "Deploying Infrastructure"
    
    local params=(
        "AdminUsername=${USERNAME}"
        "BucketPrefix=${BUCKET_PREFIX}"
        "SessionSecret=${SESSION_SECRET}"
    )
    
    if [ "$PASSWORD_HASH" != "USE_PREVIOUS" ]; then
        params+=("AdminPasswordHash=${PASSWORD_HASH}")
    fi
    
    if [ "$USE_CUSTOM_DOMAIN" == "true" ]; then
        params+=("DomainName=${DOMAIN_NAME}")
        params+=("HostedZoneId=${HOSTED_ZONE_ID}")
        params+=("CertificateArn=${CERTIFICATE_ARN}")
    fi
    
    # Cost protection parameters
    params+=("BudgetLimit=${BUDGET_LIMIT}")
    params+=("LambdaConcurrencyLimit=${LAMBDA_CONCURRENCY}")
    if [ -n "$BUDGET_EMAIL" ]; then
        params+=("BudgetAlertEmail=${BUDGET_EMAIL}")
    fi
    
    info "Deploying CloudFormation stack: ${STACK_NAME}"
    if [ "$USE_CUSTOM_DOMAIN" == "true" ]; then
        echo "   (CloudFront deployment takes 5-10 minutes...)"
    fi
    if [ "$BUDGET_LIMIT" -gt 0 ]; then
        echo "   Budget: \$${BUDGET_LIMIT}/month (auto-disable at 100%)"
        echo "   Lambda concurrency limit: ${LAMBDA_CONCURRENCY}"
    fi
    
    aws cloudformation deploy \
        --template-file "${SCRIPT_DIR}/stack.yaml" \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameter-overrides "${params[@]}" \
        --tags "Project=${BUCKET_PREFIX}" \
        --no-fail-on-empty-changeset
    
    ok "Stack deployed successfully"
}

# ============================================================
# UPLOAD HTML FILES
# ============================================================
upload_website() {
    header "Uploading Website"
    
    # Get bucket name from stack
    local bucket=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='WebsiteBucketName'].OutputValue" \
        --output text 2>/dev/null)
    
    if [ -z "$bucket" ] || [ "$bucket" == "None" ]; then
        fail "Could not find website bucket"
        exit 1
    fi
    
    info "Uploading HTML files to ${bucket}..."

    # The AWS variant serves ONLY the files in aws/website/ (index.html with the
    # API + admin panel, and login.html). The other index-*.html files in the
    # project root belong to different deployment variants (Local, Gist,
    # Self-Hosted) and must NOT be uploaded here to avoid name clashes.
    for file in "${SCRIPT_DIR}/website/"*.html; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            aws s3 cp "$file" "s3://${bucket}/${filename}" \
                --content-type "text/html; charset=utf-8" --quiet
            ok "Uploaded ${filename}"
        fi
    done
    
    # Invalidate CloudFront cache (there is always a distribution, with or
    # without a custom domain)
    local dist_id=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
        --output text)

    if [ -n "$dist_id" ] && [ "$dist_id" != "None" ]; then
        info "Invalidating CloudFront cache..."
        aws cloudfront create-invalidation \
            --distribution-id "$dist_id" \
            --paths "/*" \
            --output text --query 'Invalidation.Id' > /dev/null
        ok "Cache invalidated"
    fi
}

# ============================================================
# SHOW RESULTS
# ============================================================
show_results() {
    header "Deployment Complete! 🎉"
    
    local website_url=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" \
        --output text)

    local cf_domain=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDomainName'].OutputValue" \
        --output text)

    echo -e "${BOLD}Your website is ready:${NC}"
    echo ""
    echo -e "  ${GREEN}${website_url}${NC}"
    echo ""
    if [ "$USE_CUSTOM_DOMAIN" == "true" ]; then
        echo "  (CloudFront domain: ${cf_domain})"
        echo ""
    fi
    echo "Login:"
    echo "  Username: ${USERNAME}"
    echo "  Password: (the password you entered)"
    echo ""
    echo "The sync API is served under ${website_url}/api/ (via CloudFront)."
    echo ""
    
    # Show cost protection info
    if [ "$BUDGET_LIMIT" -gt 0 ]; then
        echo "────────────────────────────────────────"
        echo -e "${BOLD}Cost Protection:${NC}"
        echo "  Budget Limit:     \$${BUDGET_LIMIT}/month"
        echo "  Lambda Limit:     ${LAMBDA_CONCURRENCY} concurrent executions"
        echo "  Auto-Disable:     CloudFront stops at 100% budget"
        if [ -n "$BUDGET_EMAIL" ]; then
            echo "  Alerts:           ${BUDGET_EMAIL}"
        fi
        echo ""
        warn "If site goes offline due to budget: Re-enable in AWS Console"
        echo "   → CloudFront → Distributions → Enable"
        echo ""
    fi
    
    echo "────────────────────────────────────────"
    echo "Commands:"
    echo "  ./deploy.sh --upload    Update HTML files"
    echo "  ./deploy.sh --delete    Delete everything"
}

# ============================================================
# DELETE STACKS
# ============================================================
delete_all() {
    check_prerequisites
    load_config
    
    header "Deleting Deployment"
    
    # Show what exists
    local found=0
    echo "Checking for resources..."
    echo ""
    
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
        echo "  - CloudFormation stack: ${STACK_NAME}"
        found=$((found + 1))
    fi
    
    if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" 2>/dev/null; then
        echo "  - S3 bucket: ${ARTIFACT_BUCKET}"
        found=$((found + 1))
    fi
    
    if aws s3api head-bucket --bucket "${WEBSITE_BUCKET}" 2>/dev/null; then
        echo "  - S3 bucket: ${WEBSITE_BUCKET}"
        found=$((found + 1))
    fi
    
    if [ -n "$DOMAIN_NAME" ]; then
        local cert=$(aws acm list-certificates \
            --region us-east-1 \
            --query "CertificateSummaryList[?DomainName=='${DOMAIN_NAME}'].CertificateArn" \
            --output text 2>/dev/null)
        if [ -n "$cert" ] && [ "$cert" != "None" ]; then
            echo "  - ACM certificate: ${DOMAIN_NAME}"
            found=$((found + 1))
        fi
    fi
    
    if [ $found -eq 0 ]; then
        echo "No resources found."
        exit 0
    fi
    
    echo ""
    read -p "Delete all these resources? [y/N] " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    cleanup_resources
    
    echo ""
    ok "All resources deleted!"
    echo ""
    echo "To also remove the config file:"
    echo "  rm config.sh"
}

# ============================================================
# UPLOAD ONLY
# ============================================================
upload_only() {
    check_prerequisites
    load_config
    upload_website
    ok "Upload complete!"
}

# ============================================================
# MAIN
# ============================================================
case "${1:-}" in
    --delete)
        delete_all
        ;;
    --upload)
        upload_only
        ;;
    --help|-h)
        echo "PZ Skill Books - AWS Deployment"
        echo ""
        echo "Usage:"
        echo "  ./deploy.sh              Deploy everything (interactive setup on first run)"
        echo "  ./deploy.sh --upload     Upload HTML files only"
        echo "  ./deploy.sh --delete     Delete all AWS resources"
        echo "  ./deploy.sh --help       Show this help"
        ;;
    "")
        load_config  # This triggers first_time_setup if no config exists
        check_existing_resources
        
        header "PZ Skill Books - Deployment"
        echo "Region:   $REGION"
        echo "Username: $USERNAME"
        echo "Prefix:   $BUCKET_PREFIX"
        if [ "$USE_CUSTOM_DOMAIN" == "true" ]; then
            echo "Domain:   $DOMAIN_NAME"
        else
            echo "Domain:   (S3 website URL)"
        fi
        echo ""
        
        if [ "$USE_CUSTOM_DOMAIN" == "true" ]; then
            ensure_certificate
        fi
        
        ensure_artifact_bucket
        deploy_lambda
        setup_password
        deploy_stack
        upload_website
        show_results
        ;;
    *)
        fail "Unknown option: $1"
        echo "Run './deploy.sh --help' for usage."
        exit 1
        ;;
esac
