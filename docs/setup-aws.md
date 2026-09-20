# AWS Deployment Guide

Vollständige Anleitung für das Deployment der PZ Skill Books Website auf AWS mit Cookie-basierter Authentifizierung, DynamoDB-Speicherung und CloudFront CDN.

## Inhaltsverzeichnis

1. [Überblick](#überblick)
2. [Architektur](#architektur)
3. [Voraussetzungen](#voraussetzungen)
4. [Deployment](#deployment)
5. [Konfiguration](#konfiguration)
6. [Verwendung](#verwendung)
7. [Administration](#administration)
8. [Kosten](#kosten)
9. [Troubleshooting](#troubleshooting)
10. [Technische Details](#technische-details)

---

## Überblick

### Was du bekommst

| Feature | Beschreibung |
|---------|-------------|
| 🌐 **Custom Domain** | Eigene Domain mit HTTPS (z.B. `zomboid.deine-domain.de`) |
| 🔐 **Login-System** | Cookie-basierte Authentifizierung (kein Popup) |
| 💾 **Cloud-Sync** | Fortschritt wird automatisch in DynamoDB gespeichert |
| 👥 **Multi-User** | Mehrere Benutzer mit eigenem Fortschritt |
| 👑 **Admin-Panel** | Benutzer verwalten direkt über die Webseite |
| ⚡ **CDN** | Schnelle Auslieferung über CloudFront weltweit |
| 🔒 **Sicherheit** | HTTPS, gehashte Passwörter, verschlüsselte Daten |

### Kosten

| Service | Monatliche Kosten |
|---------|------------------|
| Lambda | ~$0.00 (Free Tier: 1M Requests) |
| DynamoDB | ~$0.00 (Free Tier: 25 GB + 200M Requests) |
| S3 | ~$0.01 |
| CloudFront | ~$0.01 |
| **Route53 Zone** | **$0.50** |
| **Gesamt** | **~$0.50/Monat** |

> **Hinweis:** Ohne Custom Domain (nur CloudFront-URL) ist es praktisch kostenlos.

---

## Architektur

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Route53 DNS                                  │
│                 zomboid.deine-domain.de                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CloudFront Distribution                        │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │ CloudFront      │              │                 │          │
│  │ Function        │◄────────────►│ Cache Policy    │          │
│  │ (Auth-Check)    │              │                 │          │
│  └─────────────────┘              └─────────────────┘          │
│           │                              │                      │
│           │ /login.html                  │ /*                   │
│           │ /api/*                       │                      │
│           │ (durchlassen)                │                      │
│           │                              │                      │
│           │ /* ohne Cookie               │                      │
│           │ → Redirect zu /login.html    │                      │
└───────────┼──────────────────────────────┼──────────────────────┘
            │                              │
            ▼                              ▼
    ┌───────────────┐              ┌───────────────┐
    │ Lambda URL    │              │ S3 Bucket     │
    │ (API)         │              │ (Website)     │
    │               │              │               │
    │ /api/login    │              │ index.html    │
    │ /api/logout   │              │ login.html    │
    │ /api/sync     │              │               │
    │ /api/session  │              │               │
    │ /api/admin/*  │              │               │
    └───────┬───────┘              └───────────────┘
            │
            ▼
    ┌───────────────────────────────────────┐
    │           DynamoDB                     │
    │  ┌─────────────┐  ┌─────────────┐     │
    │  │ Users       │  │ Progress    │     │
    │  │ Table       │  │ Table       │     │
    │  ├─────────────┤  ├─────────────┤     │
    │  │ username PK │  │ visibleId PK│     │
    │  │ passwordHash│  │ progress    │     │
    │  │ isAdmin     │  │ updatedAt   │     │
    │  │ createdAt   │  │             │     │
    │  └─────────────┘  └─────────────┘     │
    └───────────────────────────────────────┘
```

### Komponenten

| Komponente | Zweck |
|------------|-------|
| **Route53** | DNS für Custom Domain |
| **ACM Certificate** | SSL/TLS Zertifikat (automatisch, kostenlos) |
| **CloudFront** | CDN + Routing (Website vs API) |
| **CloudFront Function** | Auth-Check für geschützte Seiten |
| **S3 Bucket** | Statische Website-Dateien |
| **Lambda Function URL** | API für Login/Logout/Sync |
| **DynamoDB** | Benutzer- und Fortschrittsdaten |

---

## Voraussetzungen

### 1. AWS Account

Falls noch nicht vorhanden: [AWS Account erstellen](https://portal.aws.amazon.com/billing/signup)

### 2. AWS CLI

Installation prüfen:
```bash
aws --version
```

Falls nicht installiert: [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

**Windows (empfohlen):**
```powershell
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

**macOS:**
```bash
brew install awscli
```

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### 3. AWS Credentials

Credentials konfigurieren:
```bash
aws configure
```

Du brauchst:
- **Access Key ID** 
- **Secret Access Key**
- **Default Region** (z.B. `eu-central-1`)

> **Tipp:** Erstelle einen IAM User mit `AdministratorAccess` für das Deployment.
> AWS Console → IAM → Users → Add User → Attach policies directly → AdministratorAccess

### 4. Route53 Hosted Zone (optional)

Für Custom Domain brauchst du eine Hosted Zone in Route53.

Falls du noch keine hast:
1. AWS Console → Route53 → Hosted Zones → Create
2. Domain-Name eingeben
3. NS-Records bei deinem Domain-Registrar hinterlegen

### 5. Tools

- **Bash Shell** (Git Bash unter Windows, Terminal unter macOS/Linux)
- **7-Zip** (Windows) oder **zip** (macOS/Linux) für Lambda-Packaging
- **curl** für Tests (optional)

---

## Deployment

### Schnellstart

```bash
cd aws

# 1. Lambda-Code verpacken
cd lambda
zip -j api-function.zip index.mjs   # Linux/macOS
# oder
7z a -tzip api-function.zip index.mjs   # Windows mit 7-Zip

# 2. Konfiguration anpassen
cd ..
cp config.example.sh config.sh
nano config.sh   # Werte anpassen

# 3. Deployen
./deploy.sh
```

### Manuelle Schritte (detailliert)

#### Schritt 1: Artifact-Bucket erstellen

```bash
aws s3 mb s3://pz-skillbooks-artifacts-YOUR_ACCOUNT_ID --region eu-central-1
```

#### Schritt 2: Lambda-Code hochladen

```bash
cd aws/lambda
zip -j api-function.zip index.mjs
aws s3 cp api-function.zip s3://pz-skillbooks-artifacts-YOUR_ACCOUNT_ID/lambda/api-function.zip
```

#### Schritt 3: Session-Secret generieren

```bash
openssl rand -hex 32
# Ausgabe merken: z.B. a1b2c3d4e5f6...
```

#### Schritt 4: Admin-Passwort hashen

```bash
SALT=$(openssl rand -hex 16)
PASSWORD="dein-passwort"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')
echo "sha256:${SALT}:${HASH}"
# Ausgabe merken: sha256:abc123...:def456...
```

#### Schritt 5: CloudFormation Stack deployen

```bash
aws cloudformation create-stack \
  --stack-name pz-skillbooks \
  --template-body file://stack.yaml \
  --parameters \
    ParameterKey=BucketPrefix,ParameterValue=pz-skillbooks-XXXX \
    ParameterKey=DomainName,ParameterValue=zomboid.deine-domain.de \
    ParameterKey=HostedZoneId,ParameterValue=Z1234567890ABC \
    ParameterKey=CertificateArn,ParameterValue=arn:aws:acm:us-east-1:... \
    ParameterKey=AdminUsername,ParameterValue=zombie \
    ParameterKey=AdminPasswordHash,ParameterValue='sha256:...:...' \
    ParameterKey=SessionSecret,ParameterValue=a1b2c3d4e5f6... \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1
```

> **Wichtig:** Das ACM-Zertifikat muss in `us-east-1` erstellt werden (CloudFront-Anforderung)!

#### Schritt 6: Auf Stack-Completion warten

```bash
aws cloudformation wait stack-create-complete --stack-name pz-skillbooks --region eu-central-1
```

#### Schritt 7: Lambda-Permission hinzufügen

**WICHTIG:** Lambda Function URLs benötigen zwei Permissions!

```bash
# Permission 1: InvokeFunctionUrl (normalerweise via CloudFormation)
# Permission 2: InvokeFunction (MUSS manuell hinzugefügt werden!)
aws lambda add-permission \
  --function-name pz-skillbooks-XXXX-api \
  --statement-id FunctionURLInvokeAccess \
  --action lambda:InvokeFunction \
  --principal "*" \
  --region eu-central-1
```

> **Ohne diese zweite Permission gibt die Lambda URL immer 403 Forbidden zurück!**

#### Schritt 8: Website-Dateien hochladen

```bash
aws s3 cp website/index.html s3://pz-skillbooks-XXXX-website-YOUR_ACCOUNT_ID/index.html \
  --content-type "text/html; charset=utf-8"
aws s3 cp website/login.html s3://pz-skillbooks-XXXX-website-YOUR_ACCOUNT_ID/login.html \
  --content-type "text/html; charset=utf-8"
```

#### Schritt 9: Admin-User anlegen

```bash
aws dynamodb put-item \
  --table-name pz-skillbooks-XXXX-users \
  --item '{
    "username": {"S": "zombie"},
    "passwordHash": {"S": "sha256:...:..."},
    "isAdmin": {"BOOL": true},
    "createdAt": {"S": "2024-01-01T00:00:00Z"}
  }' \
  --region eu-central-1
```

#### Schritt 10: CloudFront Cache invalidieren

```bash
DIST_ID=$(aws cloudformation describe-stacks --stack-name pz-skillbooks \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output text)
aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
```

---

## Konfiguration

### config.sh

```bash
# AWS Region
REGION="eu-central-1"

# Login-Benutzername
USERNAME="zombie"

# Ressourcen-Prefix (muss eindeutig sein)
BUCKET_PREFIX="pz-skillbooks-1234"

# Custom Domain (leer lassen für CloudFront-URL)
DOMAIN_NAME="zomboid.deine-domain.de"

# Route53 Hosted Zone ID
HOSTED_ZONE_ID="Z1234567890ABC"

# ACM Certificate ARN (muss in us-east-1 sein!)
CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/abc-123-..."
```

### CloudFormation Parameter

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `BucketPrefix` | Prefix für alle Ressourcen | `pz-skillbooks-1234` |
| `DomainName` | Custom Domain | `zomboid.nubilum.net` |
| `HostedZoneId` | Route53 Zone ID | `Z1N8OULFQL47F3` |
| `CertificateArn` | ACM Cert in us-east-1 | `arn:aws:acm:us-east-1:...` |
| `AdminUsername` | Erster Admin-User | `zombie` |
| `AdminPasswordHash` | Gehashtes Passwort | `sha256:salt:hash` |
| `SessionSecret` | Cookie-Signatur-Key | 64 Hex-Zeichen |

---

## Verwendung

### Login

1. Öffne `https://zomboid.deine-domain.de`
2. Du wirst automatisch zu `/login.html` weitergeleitet
3. Username + Passwort eingeben
4. Nach erfolgreichem Login: Redirect zur Haupt-App

### Fortschritt speichern

- Checkboxen anklicken → Fortschritt wird automatisch alle 500ms gespeichert
- Kein manuelles Speichern nötig
- Sync-Status wird oben angezeigt: "✓ Synced" / "↻ Saving..." / "✗ Sync error"

### Export/Import

- **Export:** Speichert aktuellen Fortschritt als JSON-Datei
- **Import:** Lädt Fortschritt aus JSON-Datei (überschreibt Server-Daten)

### Logout

- Klick auf "Logout" oben rechts
- Session-Cookie wird gelöscht
- Redirect zur Login-Seite

---

## Administration

### Admin-Panel öffnen

Als Admin-User siehst du oben rechts den "👑 Admin" Button.

### Benutzer verwalten

Im Admin-Panel kannst du:
- Alle Benutzer sehen
- Neue Benutzer anlegen (mit/ohne Admin-Rechte)
- Benutzer löschen (inkl. deren Fortschritt)

### Benutzer via CLI anlegen

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
# Neues Passwort hashen
SALT=$(openssl rand -hex 16)
PASSWORD="neues-passwort"
HASH=$(echo -n "${SALT}${PASSWORD}" | openssl dgst -sha256 | awk '{print $2}')

# User updaten
aws dynamodb update-item \
  --table-name pz-skillbooks-XXXX-users \
  --key '{"username": {"S": "zombie"}}' \
  --update-expression "SET passwordHash = :ph" \
  --expression-attribute-values '{":ph": {"S": "sha256:'$SALT':'$HASH'"}}' \
  --region eu-central-1
```

---

## Kosten

### Kostenaufschlüsselung

| Service | Free Tier | Danach | Erwartete Kosten |
|---------|-----------|--------|------------------|
| **Lambda** | 1M Requests/Monat | $0.20/1M | ~$0.00 |
| **DynamoDB** | 25 GB + 200M Requests | $0.25/GB | ~$0.00 |
| **S3** | 5 GB | $0.023/GB | ~$0.01 |
| **CloudFront** | 1 TB/Monat | $0.085/GB | ~$0.01 |
| **Route53 Zone** | - | $0.50/Zone | **$0.50** |
| **Route53 Queries** | - | $0.40/1M | ~$0.01 |

### Gesamt: ~$0.50/Monat

> **Ohne Custom Domain:** Praktisch $0 (nur minimale S3/CloudFront-Kosten)

### Kostenalarm einrichten

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "PZ-Skillbooks-Cost-Alert" \
  --alarm-description "Alert when costs exceed $1" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:YOUR_ACCOUNT:billing-alerts \
  --region us-east-1
```

---

## Troubleshooting

### Lambda URL gibt 403 Forbidden

**Problem:** Die Lambda URL gibt immer "Forbidden" zurück, obwohl alles korrekt konfiguriert ist.

**Lösung:** Lambda Function URLs benötigen **zwei** Permissions:
1. `lambda:InvokeFunctionUrl` (wird via CloudFormation erstellt)
2. `lambda:InvokeFunction` (muss manuell hinzugefügt werden!)

```bash
aws lambda add-permission \
  --function-name FUNCTION_NAME \
  --statement-id FunctionURLInvokeAccess \
  --action lambda:InvokeFunction \
  --principal "*" \
  --region eu-central-1
```

> **Hinweis:** Dies ist ein undokumentiertes AWS-Verhalten. Die offizielle Dokumentation erwähnt nur die erste Permission.

### CloudFormation Stack schlägt fehl

**Validation Error bei Lambda URL:**
```
PropertyValidation: Property "Cors" is not valid
```
→ CORS in CloudFormation für Lambda URLs wird nicht unterstützt. CORS muss nach dem Deployment manuell konfiguriert werden (falls nötig).

**Bucket existiert bereits:**
→ Bucket-Namen sind global eindeutig. Wähle einen anderen `BucketPrefix`.

### Certificate Validation hängt

ACM-Zertifikate brauchen DNS-Validierung:
1. Prüfe ob die CNAME-Records in Route53 erstellt wurden
2. Warte bis zu 30 Minuten
3. Falls immer noch "Pending": Prüfe ob die Hosted Zone korrekt mit der Domain verbunden ist

### Login funktioniert nicht

1. **Prüfe Passwort-Hash:**
   ```bash
   aws dynamodb get-item \
     --table-name pz-skillbooks-XXXX-users \
     --key '{"username": {"S": "zombie"}}' \
     --region eu-central-1
   ```

2. **Prüfe Lambda-Logs:**
   ```bash
   aws logs tail /aws/lambda/pz-skillbooks-XXXX-api --follow --region eu-central-1
   ```

3. **Teste API direkt:**
   ```bash
   curl -X POST "https://deine-domain/api/login" \
     -H "Content-Type: application/json" \
     -d '{"username":"zombie","password":"dein-passwort"}'
   ```

### Änderungen werden nicht angezeigt

CloudFront cached Inhalte. Nach Änderungen:

```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR_DIST_ID \
  --paths "/*"
```

---

## Technische Details

### API Endpoints

| Endpoint | Method | Auth | Beschreibung |
|----------|--------|------|-------------|
| `/api/login` | POST | ❌ | Login, setzt Session-Cookie |
| `/api/logout` | GET | ❌ | Löscht Session-Cookie |
| `/api/session` | GET | ✅ | Gibt aktuelle Session-Info zurück |
| `/api/sync` | GET | ✅ | Lädt Fortschritt |
| `/api/sync` | POST | ✅ | Speichert Fortschritt |
| `/api/admin/users` | GET | ✅👑 | Liste aller User (nur Admin) |
| `/api/admin/users` | POST | ✅👑 | User anlegen (nur Admin) |
| `/api/admin/users/:id` | DELETE | ✅👑 | User löschen (nur Admin) |

### Session-Cookie Format

```
pz_session=BASE64_PAYLOAD.HMAC_SIGNATURE
```

**Payload (Base64-decoded):**
```json
{
  "username": "zombie",
  "exp": 1735689600000
}
```

**Signatur:** HMAC-SHA256 mit `SESSION_SECRET`

### Passwort-Hash Format

```
sha256:SALT:HASH
```

- **SALT:** 32 Hex-Zeichen (16 Bytes)
- **HASH:** SHA256(SALT + PASSWORD) als 64 Hex-Zeichen

### DynamoDB Schema

**Users Table:**
```
Primary Key: username (String)
Attributes:
  - passwordHash (String): "sha256:salt:hash"
  - isAdmin (Boolean)
  - createdAt (String): ISO 8601
```

**Progress Table:**
```
Primary Key: visibleId (String) - SHA256(username).slice(0,16)
Attributes:
  - username (String): Referenz
  - progress (Map): {"Skill|Volume": true, ...}
  - updatedAt (String): ISO 8601
```

### CloudFront Function (Auth)

Die CloudFront Function prüft bei jedem Request:
1. Ist der Pfad `/api/*` oder `/login.html`? → Durchlassen
2. Existiert Cookie `pz_session`? → Durchlassen
3. Sonst → Redirect zu `/login.html`

> **Hinweis:** Die Function validiert das Cookie nicht kryptografisch. Die echte Validierung passiert in der Lambda.

---

## Löschen / Aufräumen

### Stack löschen

```bash
# CloudFormation Stack löschen
aws cloudformation delete-stack --stack-name pz-skillbooks --region eu-central-1

# Warten bis gelöscht
aws cloudformation wait stack-delete-complete --stack-name pz-skillbooks --region eu-central-1
```

### S3 Buckets manuell löschen

S3 Buckets mit Inhalt werden nicht automatisch gelöscht:

```bash
# Website-Bucket leeren und löschen
aws s3 rm s3://pz-skillbooks-XXXX-website-YOUR_ACCOUNT --recursive
aws s3 rb s3://pz-skillbooks-XXXX-website-YOUR_ACCOUNT

# Artifact-Bucket leeren und löschen
aws s3 rm s3://pz-skillbooks-XXXX-artifacts-YOUR_ACCOUNT --recursive
aws s3 rb s3://pz-skillbooks-XXXX-artifacts-YOUR_ACCOUNT
```

### ACM Certificate löschen

Falls nicht mehr benötigt:
```bash
aws acm delete-certificate \
  --certificate-arn arn:aws:acm:us-east-1:... \
  --region us-east-1
```

---

## Changelog

### v2.0 (2024-09)
- Umstellung von Basic Auth auf Cookie-basierte Authentifizierung
- DynamoDB statt S3 für Datenspeicherung
- Multi-User-Support mit Admin-Panel
- CloudFront Function für Auth-Redirect
- Alle Requests über CloudFront (kein separater API-Endpoint)

### v1.0 (2024-08)
- Initiale Version mit S3 + Lambda URL
- Basic Auth über Header
- Single-User Setup
