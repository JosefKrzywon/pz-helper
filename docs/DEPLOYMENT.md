# Deployment Cheatsheet

Schnelle Referenz für häufige Deployment-Aufgaben.

## Voraussetzungen

```bash
# AWS CLI Version prüfen
aws --version

# AWS Verbindung testen
aws sts get-caller-identity
```

---

## Initiales Deployment

### 1. Artifact Bucket erstellen (einmalig)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 mb s3://pz-skillbooks-artifacts-${ACCOUNT_ID} --region eu-central-1
```

### 2. Lambda Code hochladen

```bash
cd aws/lambda

# Linux/macOS
zip -j api-function.zip index.mjs

# Windows (7-Zip)
7z a -tzip api-function.zip index.mjs

# Upload
aws s3 cp api-function.zip s3://pz-skillbooks-artifacts-${ACCOUNT_ID}/lambda/api-function.zip
```

### 3. Secrets generieren

```bash
# Session Secret (64 Hex-Zeichen)
SESSION_SECRET=$(openssl rand -hex 32)
echo "Session Secret: $SESSION_SECRET"

# Admin Passwort hashen
SALT=$(openssl rand -hex 16)
PASSWORD="dein-passwort-hier"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')
ADMIN_HASH="sha256:${SALT}:${HASH}"
echo "Admin Hash: $ADMIN_HASH"
```

### 4. CloudFormation Stack deployen

```bash
aws cloudformation create-stack \
  --stack-name pz-skillbooks \
  --template-body file://aws/stack.yaml \
  --parameters \
    ParameterKey=BucketPrefix,ParameterValue=pz-skillbooks-XXXX \
    ParameterKey=DomainName,ParameterValue=zomboid.deine-domain.de \
    ParameterKey=HostedZoneId,ParameterValue=ZXXXXXXXXXX \
    ParameterKey=CertificateArn,ParameterValue=arn:aws:acm:us-east-1:XXXX:certificate/XXXX \
    ParameterKey=AdminUsername,ParameterValue=zombie \
    ParameterKey=AdminPasswordHash,ParameterValue="$ADMIN_HASH" \
    ParameterKey=SessionSecret,ParameterValue="$SESSION_SECRET" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1

# Warten
aws cloudformation wait stack-create-complete --stack-name pz-skillbooks --region eu-central-1
```

### 5. WICHTIG: Lambda Permission hinzufügen

```bash
# OHNE diese Permission gibt Lambda URL 403 Forbidden!
aws lambda add-permission \
  --function-name pz-skillbooks-XXXX-api \
  --statement-id FunctionURLInvokeAccess \
  --action lambda:InvokeFunction \
  --principal "*" \
  --region eu-central-1
```

### 6. Website-Dateien hochladen

```bash
BUCKET=$(aws cloudformation describe-stacks --stack-name pz-skillbooks \
  --query 'Stacks[0].Outputs[?OutputKey==`WebsiteBucketName`].OutputValue' --output text)

aws s3 cp aws/website/index.html s3://${BUCKET}/index.html --content-type "text/html; charset=utf-8"
aws s3 cp aws/website/login.html s3://${BUCKET}/login.html --content-type "text/html; charset=utf-8"
```

### 7. Admin User anlegen

```bash
aws dynamodb put-item \
  --table-name pz-skillbooks-XXXX-users \
  --item '{
    "username": {"S": "zombie"},
    "passwordHash": {"S": "'"$ADMIN_HASH"'"},
    "isAdmin": {"BOOL": true},
    "createdAt": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
  }' \
  --region eu-central-1
```

### 8. Cache invalidieren

```bash
DIST_ID=$(aws cloudformation describe-stacks --stack-name pz-skillbooks \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output text)

aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
```

---

## Häufige Aufgaben

### Website-Änderungen deployen

```bash
# Dateien hochladen
aws s3 cp aws/website/index.html s3://${BUCKET}/index.html --content-type "text/html; charset=utf-8"

# Cache invalidieren
aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/index.html"
```

### Lambda-Code aktualisieren

```bash
# Neu packen
cd aws/lambda
zip -j api-function.zip index.mjs

# Hochladen
aws s3 cp api-function.zip s3://pz-skillbooks-artifacts-${ACCOUNT_ID}/lambda/api-function.zip

# Lambda aktualisieren
aws lambda update-function-code \
  --function-name pz-skillbooks-XXXX-api \
  --s3-bucket pz-skillbooks-artifacts-${ACCOUNT_ID} \
  --s3-key lambda/api-function.zip \
  --region eu-central-1
```

### Neuen User anlegen

```bash
# Passwort hashen
SALT=$(openssl rand -hex 16)
PASSWORD="neues-passwort"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')

# User anlegen
aws dynamodb put-item \
  --table-name pz-skillbooks-XXXX-users \
  --item '{
    "username": {"S": "neuer-user"},
    "passwordHash": {"S": "sha256:'$SALT':'$HASH'"},
    "isAdmin": {"BOOL": false},
    "createdAt": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
  }' \
  --region eu-central-1
```

### Passwort zurücksetzen

```bash
SALT=$(openssl rand -hex 16)
PASSWORD="neues-passwort"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')

aws dynamodb update-item \
  --table-name pz-skillbooks-XXXX-users \
  --key '{"username": {"S": "zombie"}}' \
  --update-expression "SET passwordHash = :ph" \
  --expression-attribute-values '{":ph": {"S": "sha256:'$SALT':'$HASH'"}}' \
  --region eu-central-1
```

### User löschen

```bash
# User löschen
aws dynamodb delete-item \
  --table-name pz-skillbooks-XXXX-users \
  --key '{"username": {"S": "zu-loeschender-user"}}' \
  --region eu-central-1

# Optional: Progress auch löschen
# visibleId = SHA256(username).slice(0,16)
```

### Alle User auflisten

```bash
aws dynamodb scan \
  --table-name pz-skillbooks-XXXX-users \
  --projection-expression "username, isAdmin, createdAt" \
  --region eu-central-1
```

---

## Debugging

### Lambda Logs ansehen

```bash
aws logs tail /aws/lambda/pz-skillbooks-XXXX-api --follow --region eu-central-1
```

### API direkt testen

```bash
# Login
curl -X POST "https://zomboid.deine-domain.de/api/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"zombie","password":"dein-passwort"}' \
  -c cookies.txt

# Session prüfen
curl "https://zomboid.deine-domain.de/api/session" -b cookies.txt

# Sync testen
curl "https://zomboid.deine-domain.de/api/sync" -b cookies.txt
```

### Stack Status prüfen

```bash
aws cloudformation describe-stacks --stack-name pz-skillbooks --region eu-central-1 \
  --query 'Stacks[0].StackStatus'
```

### Stack Events bei Fehlern

```bash
aws cloudformation describe-stack-events --stack-name pz-skillbooks --region eu-central-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]'
```

---

## Aufräumen

### Alles löschen

```bash
# CloudFormation Stack löschen
aws cloudformation delete-stack --stack-name pz-skillbooks --region eu-central-1
aws cloudformation wait stack-delete-complete --stack-name pz-skillbooks --region eu-central-1

# S3 Buckets manuell löschen (haben Inhalt)
aws s3 rm s3://pz-skillbooks-XXXX-website-${ACCOUNT_ID} --recursive
aws s3 rb s3://pz-skillbooks-XXXX-website-${ACCOUNT_ID}

aws s3 rm s3://pz-skillbooks-artifacts-${ACCOUNT_ID} --recursive
aws s3 rb s3://pz-skillbooks-artifacts-${ACCOUNT_ID}
```

---

## Wichtige ARNs & IDs

Nach dem Deployment kannst du diese mit `describe-stacks` abrufen:

```bash
aws cloudformation describe-stacks --stack-name pz-skillbooks --region eu-central-1 \
  --query 'Stacks[0].Outputs'
```

| Output | Beschreibung |
|--------|-------------|
| `WebsiteURL` | Die URL deiner Website |
| `WebsiteBucketName` | S3 Bucket für HTML-Dateien |
| `UsersTableName` | DynamoDB Table für User |
| `ProgressTableName` | DynamoDB Table für Fortschritt |
| `CloudFrontDistributionId` | Für Cache-Invalidierung |
