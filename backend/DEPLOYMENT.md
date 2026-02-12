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

4. **Verify deployment:**
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
- **Database:** Located at `livedata.db` in the container (ephemeral - consider adding persistent volume)

### Database Backup (Important!)

Railway's filesystem is ephemeral. For production:

1. Add a persistent volume in Railway settings
2. Or migrate to PostgreSQL/MySQL for better reliability
3. Set up automated backups

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
