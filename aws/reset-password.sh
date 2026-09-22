#!/bin/bash
#
# Zomboid Helper - Admin Password Reset
#
# Resets (or creates) a user's password directly in the DynamoDB Users table.
#
# SECURITY: This script talks to DynamoDB via the AWS CLI. It can therefore
# only be run by someone with valid AWS credentials for this account that
# have write access to the Users table (i.e. the account owner / admin).
# There is no way to run it anonymously or from the website.
#
# Usage:
#   ./reset-password.sh              # reset the admin user from config.sh
#   ./reset-password.sh <username>   # reset a specific user
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }

# --- Load config -------------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    fail "config.sh not found. Run ./deploy.sh first."
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

REGION="${REGION:-eu-central-1}"
BUCKET_PREFIX="${BUCKET_PREFIX:?BUCKET_PREFIX missing in config.sh}"
USERS_TABLE="${BUCKET_PREFIX}-users"

# --- Verify AWS access (only the account owner has this) ---------------------
if ! aws sts get-caller-identity &>/dev/null; then
    fail "No valid AWS credentials. Only the account owner can reset passwords."
    exit 1
fi

# --- Determine target user ---------------------------------------------------
TARGET_USER="${1:-${USERNAME}}"
if [ -z "$TARGET_USER" ]; then
    fail "No username given and USERNAME not set in config.sh."
    echo "Usage: ./reset-password.sh <username>"
    exit 1
fi

echo "Resetting password for user '${TARGET_USER}' in table '${USERS_TABLE}' (${REGION})"
echo ""

# --- Read new password (hidden) ----------------------------------------------
read -s -p "New password: " PW; echo
read -s -p "Confirm password: " PW2; echo
if [ -z "$PW" ]; then
    fail "Password cannot be empty."
    exit 1
fi
if [ "$PW" != "$PW2" ]; then
    fail "Passwords do not match."
    exit 1
fi

# --- Generate salted SHA-256 hash (same scheme as the Lambda) ----------------
SALT=$(openssl rand -hex 16)
HASH=$(printf '%s%s' "$SALT" "$PW" | openssl dgst -sha256 | awk '{print $2}')
PASSWORD_HASH="sha256:${SALT}:${HASH}"
unset PW PW2

# --- Does the user already exist? (preserve isAdmin/createdAt) ----------------
EXISTING=$(aws dynamodb get-item \
    --table-name "$USERS_TABLE" \
    --region "$REGION" \
    --key "{\"username\":{\"S\":\"${TARGET_USER}\"}}" \
    --query 'Item' --output json 2>/dev/null || echo "null")

IS_ADMIN="true"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
if [ "$EXISTING" != "null" ] && [ -n "$EXISTING" ]; then
    # keep existing isAdmin flag if present
    if echo "$EXISTING" | grep -q '"isAdmin"'; then
        if echo "$EXISTING" | grep -A1 '"isAdmin"' | grep -q 'false'; then
            IS_ADMIN="false"
        fi
    fi
    ok "User exists - updating password (isAdmin=${IS_ADMIN})"
else
    ok "User does not exist - creating as admin"
fi

# --- Write the item ----------------------------------------------------------
aws dynamodb put-item \
    --table-name "$USERS_TABLE" \
    --region "$REGION" \
    --item "{
        \"username\":     {\"S\": \"${TARGET_USER}\"},
        \"passwordHash\": {\"S\": \"${PASSWORD_HASH}\"},
        \"isAdmin\":      {\"BOOL\": ${IS_ADMIN}},
        \"createdAt\":    {\"S\": \"${CREATED_AT}\"}
    }"

unset PASSWORD_HASH HASH SALT
echo ""
ok "Password for '${TARGET_USER}' has been reset."
echo "You can now log in at your site with the new password."
