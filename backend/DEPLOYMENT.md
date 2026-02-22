# Backend Deployment Guide

## Railway Deployment

### Required Environment Variables

Set these in your Railway project's "Variables" tab:

```bash
JWT_SECRET=<generate-a-long-random-string>
PORT=8000  # Railway sets this automatically
```

### Generate a secure JWT secret:

```bash
# Option 1: Using Python
python3 -c "import secrets; print(secrets.token_urlsafe(64))"

# Option 2: Using OpenSSL
openssl rand -base64 64 | tr -d '\n'
```

### Deployment Steps

1. **Push code to GitHub:**
   ```bash
   git add .
   git commit -m "Ready for deployment"
   git push origin main
   ```

2. **In Railway:**
   - Create new project
   - Select "Deploy from GitHub repo"
   - Choose your repository
   - Railway will detect the Dockerfile automatically

3. **Set environment variables:**
   - Go to your service settings
   - Click "Variables"
   - Add `JWT_SECRET` with your generated secret

4. **Add a persistent volume (required for pitch history):**
   - Without this, pitch history is wiped on every redeploy.
   - In Railway: right-click the project canvas → "Add Volume" (or use Command Palette ⌘K)
   - Connect the volume to your backend service
   - Set the mount path to `/data` (or any path—the app uses `RAILWAY_VOLUME_MOUNT_PATH` automatically)
   - Redeploy so the volume is attached

5. **Verify deployment:**
   - Check the deployment logs
   - Visit `https://your-app.up.railway.app/health`
   - Should return: `{"status":"healthy","model_loaded":true}`

### Security Checklist

- [ ] `JWT_SECRET` is set to a random value (not the default)
- [ ] `CORS` origins are restricted (update `allow_origins` in main.py)
- [ ] Rate limiting is enabled (see TODO)
- [ ] Database backups are configured

### CORS Configuration (Production)

Update `main.py` line 62:

```python
# Development (current):
allow_origins=["*"]

# Production:
allow_origins=[
    "https://your-ios-app-domain.com",  # If you have a web version
    # Add other allowed origins
]
```

For iOS-only apps, you can keep `["*"]` but consider adding rate limiting.

### Monitoring

- **Health check:** `GET /health`
- **Railway metrics:** CPU, memory, and request logs in the dashboard
- **Database:** Uses `livedata.db`. When `RAILWAY_VOLUME_MOUNT_PATH` is set (volume attached), the DB is stored there and persists across redeploys. Without a volume, data is lost on restart.

### Database persistence (required)

The backend automatically uses Railway's volume when one is attached. Add a volume and set its mount path (e.g. `/data`); Railway provides `RAILWAY_VOLUME_MOUNT_PATH` at runtime. See step 4 in Deployment Steps above.

### Rate Limiting (TODO)

Add `slowapi` to prevent abuse:

```bash
pip install slowapi
```

Update `main.py`:
```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address, default_limits=["100/hour"])
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Apply to endpoints:
@app.post("/auth/login")
@limiter.limit("10/minute")
async def login(request: Request, ...):
    ...
```
