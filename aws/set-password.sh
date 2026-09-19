#!/bin/bash
#
# PZ Skillbücher - Change Password
#
# Updates the password for the Lambda sync function.
#
set -e

# ============================================================
# CONFIGURATION - Must match deploy.sh
# ============================================================
STACK_NAME="pz-skillbuecher"
REGION="eu-central-1"
BUCKET_PREFIX="pz-skillbuecher"

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
# Check if stack exists
# ============================================================
if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
    echo "Error: Stack '${STACK_NAME}' does not exist."
    echo "Run deploy.sh first to create the stack."
    exit 1
fi

# ============================================================
# Get current username
# ============================================================
USERNAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query "Stacks[0].Outputs[?OutputKey=='Username'].OutputValue" \
    --output text)

echo "========================================"
echo "PZ Skillbücher - Change Password"
echo "========================================"
echo "Stack:    ${STACK_NAME}"
echo "Username: ${USERNAME}"
echo "========================================"
echo ""

# ============================================================
# Get new password
# ============================================================
echo "Enter new password:"
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

# ============================================================
# Update Lambda environment variable
# ============================================================
echo "Updating Lambda function..."

FUNCTION_NAME="${BUCKET_PREFIX}-sync"

# Get current environment variables
CURRENT_ENV=$(aws lambda get-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" \
    --query 'Environment.Variables' \
    --output json)

# Update with new password hash
UPDATED_ENV=$(echo "$CURRENT_ENV" | node -e "
    let data = '';
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => {
        const env = JSON.parse(data);
        env.AUTH_PASSWORD_HASH = process.argv[1];
        console.log(JSON.stringify({Variables: env}));
    });
" "$PASSWORD_HASH")

aws lambda update-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" \
    --environment "$UPDATED_ENV" \
    --output text --query 'FunctionArn' > /dev/null

echo ""
echo "========================================"
echo "Password updated successfully!"
echo "========================================"
echo ""
echo "You can now use the new password in the app."
