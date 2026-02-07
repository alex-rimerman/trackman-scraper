FROM python:3.11-slim

WORKDIR /app

# Copy requirements first for better caching
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the backend code
COPY backend/ .

EXPOSE 8000

# Use shell form to expand $PORT environment variable (Railway sets this)
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}
