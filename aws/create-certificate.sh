#!/bin/bash
#
# PZ Skillbücher - Create ACM Certificate
#
# Creates an ACM certificate in us-east-1 (required for CloudFront)
# and sets up DNS validation via Route53.
#
# Usage: ./create-certificate.sh <domain> <hosted-zone-id>
# Example: ./create-certificate.sh zomboid.example.com Z1234567890ABC
#
set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <domain> <hosted-zone-id>"
    echo "Example: $0 zomboid.example.com Z1234567890ABC"
    exit 1
fi

DOMAIN="$1"
HOSTED_ZONE_ID="$2"
REGION="us-east-1"  # Must be us-east-1 for CloudFront

echo "========================================"
echo "Creating ACM Certificate"
echo "========================================"
echo "Domain:  ${DOMAIN}"
echo "Zone ID: ${HOSTED_ZONE_ID}"
echo "Region:  ${REGION}"
echo "========================================"
echo ""

# Request certificate
echo "Requesting certificate..."
CERT_ARN=$(aws acm request-certificate \
    --domain-name "${DOMAIN}" \
    --validation-method DNS \
    --region "${REGION}" \
    --query 'CertificateArn' \
    --output text)

echo "Certificate ARN: ${CERT_ARN}"
echo ""

# Wait for validation details to be available
echo "Waiting for validation details..."
sleep 5

# Get DNS validation record
VALIDATION=$(aws acm describe-certificate \
    --certificate-arn "${CERT_ARN}" \
    --region "${REGION}" \
    --query 'Certificate.DomainValidationOptions[0].ResourceRecord')

RECORD_NAME=$(echo "$VALIDATION" | jq -r '.Name')
RECORD_VALUE=$(echo "$VALIDATION" | jq -r '.Value')

echo "DNS validation record:"
echo "  Name:  ${RECORD_NAME}"
echo "  Value: ${RECORD_VALUE}"
echo ""

# Create Route53 validation record
echo "Creating Route53 validation record..."
CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${RECORD_NAME}",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "${RECORD_VALUE}"}]
    }
  }]
}
EOF
)

aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --change-batch "${CHANGE_BATCH}" \
    --output text > /dev/null

echo "Validation record created."
echo ""

# Wait for validation
echo "Waiting for certificate validation (this may take a few minutes)..."
aws acm wait certificate-validated \
    --certificate-arn "${CERT_ARN}" \
    --region "${REGION}"

echo ""
echo "========================================"
echo "Certificate validated!"
echo "========================================"
echo ""
echo "Certificate ARN (use this in website-stack.yaml):"
echo "  ${CERT_ARN}"
echo ""
echo "Save this ARN! You'll need it for the website deployment."
