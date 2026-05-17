FROM python:3.12-slim

WORKDIR /app

# Install dependencies first for layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Cloud Run sets PORT env var
ENV PORT=8080

# Orchestrator stays warm (min-instances=1 in Cloud Run config)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
