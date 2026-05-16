# GCP Project Setup — M0 Checklist

> **Project ID:** `mehfooz-prod`
> **Region:** `asia-south1` (Mumbai — lowest latency to Pakistan)
> Run these commands once per project. Check off each step as you go.

---

## 1. Create Project & Apply Credits

```bash
gcloud projects create mehfooz-prod --name="Mehfooz"
gcloud config set project mehfooz-prod
# Apply hackathon credits via the GCP billing console
```

---

## 2. Enable Required APIs

```bash
gcloud services enable \
  firebase.googleapis.com \
  firestore.googleapis.com \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  storage.googleapis.com \
  aiplatform.googleapis.com \
  maps-backend.googleapis.com \
  places-backend.googleapis.com \
  routes.googleapis.com \
  translate.googleapis.com \
  identitytoolkit.googleapis.com \
  fcm.googleapis.com \
  bigquery.googleapis.com \
  cloudscheduler.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com
```

---

## 3. Service Accounts

### 3a. agents-runtime (Cloud Run agents)
```bash
gcloud iam service-accounts create agents-runtime \
  --display-name="Agents Runtime (Cloud Run)"

# Firestore read/write
gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:agents-runtime@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

# Vertex AI user (Gemini)
gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:agents-runtime@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"

# Cloud Storage (photo verification)
gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:agents-runtime@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

### 3b. functions-runtime (Cloud Functions)
```bash
gcloud iam service-accounts create functions-runtime \
  --display-name="Functions Runtime"

gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:functions-runtime@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:functions-runtime@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/firebase.sdkAdminServiceAgent"
```

### 3c. ci (GitHub Actions deploy)
```bash
gcloud iam service-accounts create ci \
  --display-name="CI Deploy Service Account"

gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:ci@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:ci@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/cloudfunctions.developer"

gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:ci@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding mehfooz-prod \
  --member="serviceAccount:ci@mehfooz-prod.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Export key for GitHub Actions secret GCP_SA_KEY_CI
gcloud iam service-accounts keys create ci-key.json \
  --iam-account=ci@mehfooz-prod.iam.gserviceaccount.com
# → Add contents of ci-key.json as GitHub secret GCP_SA_KEY_CI
# → DELETE ci-key.json locally after adding to GitHub
```

---

## 4. Firebase Setup

```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Login and initialize project
firebase login
firebase use mehfooz-prod

# Initialize Firestore (native mode, asia-south1)
firebase firestore:databases:create --location=asia-south1

# Initialize Firebase Auth (enable Phone + Google providers in Firebase Console)
```

---

## 5. Cloud Scheduler Jobs

```bash
# Ingestion agent poll — every 2 minutes for weather + traffic
gcloud scheduler jobs create http ingestion-poll \
  --location=asia-south1 \
  --schedule="*/2 * * * *" \
  --uri="https://ingestion-agent-<hash>-as.a.run.app/ingest/poll" \
  --http-method=POST \
  --oidc-service-account-email=agents-runtime@mehfooz-prod.iam.gserviceaccount.com \
  --message-body='{"cities":["islamabad","rawalpindi","karachi","lahore"]}'
```

---

## 6. Cloud Storage Buckets

```bash
# Photo uploads from citizens
gsutil mb -l asia-south1 gs://mehfooz-prod-citizen-photos

# Agent artifacts and logs
gsutil mb -l asia-south1 gs://mehfooz-prod-agent-artifacts

# Set CORS for photo uploads (mobile app)
gsutil cors set docs/storage_cors.json gs://mehfooz-prod-citizen-photos
```

---

## 7. Hello-World Cloud Run Smoke Test

```bash
# Verify Cloud Run deploy works before wiring up real agents
cat > /tmp/hello_mehfooz/main.py << 'EOF'
from fastapi import FastAPI
app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok", "service": "mehfooz-hello"}
EOF

cat > /tmp/hello_mehfooz/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN pip install fastapi uvicorn
COPY main.py .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

gcloud run deploy hello-mehfooz \
  --source /tmp/hello_mehfooz \
  --region asia-south1 \
  --allow-unauthenticated \
  --quiet

# Should return {"status":"ok","service":"mehfooz-hello"}
curl $(gcloud run services describe hello-mehfooz --region asia-south1 --format 'value(status.url)')/health
```

---

## Exit Criteria Checklist

- [ ] `gcloud projects describe mehfooz-prod` returns project info
- [ ] All 15 APIs enabled (`gcloud services list --enabled`)
- [ ] Three service accounts created (`gcloud iam service-accounts list`)
- [ ] Firebase Console shows Firestore in `asia-south1` mode
- [ ] `firebase emulators:start` runs locally without errors
- [ ] Hello-world Cloud Run service returns `{"status":"ok"}`
- [ ] GitHub Actions secrets: `GCP_SA_KEY_CI` set
- [ ] Demo scenario locked: `docs/demo_scenario.md` committed
