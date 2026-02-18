"""
Developing Baseball – Stuff+ Backend API
==========================================
FastAPI server with:
  • Stuff+ prediction (same model as BPC Portal)
  • User authentication (signup / login with JWT)
  • Per-user pitch storage (SQLite)

Usage:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from fastapi import FastAPI, HTTPException, Depends, status, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from typing import Optional
import numpy as np
import dill
import os
import sys
import sqlite3
import json
import uuid
from datetime import datetime, timedelta, timezone
from contextlib import contextmanager

from jose import jwt, JWTError
import bcrypt
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modeling.aStuffPlusModel2 import aStuffPlusModel

JWT_SECRET = os.environ.get("JWT_SECRET", "dev-secret-change-in-production-abc123")
if JWT_SECRET == "dev-secret-change-in-production-abc123":
    import warnings
    warnings.warn(
        "WARNING: Using default JWT_SECRET! Set JWT_SECRET environment variable in production.",
        RuntimeWarning
    )
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_DAYS = 90

# CORS allowed origins
ALLOWED_ORIGINS = os.environ.get("CORS_ORIGINS", "*").split(",")

security = HTTPBearer()
limiter = Limiter(key_func=get_remote_address, default_limits=["1000/hour"])


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "livedata.db")

app = FastAPI(
    title="Developing Baseball API",
    description="Stuff+ predictions, user auth, and pitch storage",
    version="2.0.0",
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

def init_db():
    """Create tables if they don't exist."""
    with get_db() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                email TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                account_type TEXT NOT NULL DEFAULT 'personal',
                created_at TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS pitches (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                profile_id TEXT,
                pitch_type TEXT NOT NULL,
                pitch_speed REAL,
                induced_vert_break REAL,
                horz_break REAL,
                release_height REAL,
                release_side REAL,
                extension_ft REAL,
                total_spin REAL,
                tilt_string TEXT,
                spin_axis REAL,
                efficiency REAL,
                active_spin REAL,
                gyro REAL,
                pitcher_hand TEXT,
                stuff_plus REAL,
                stuff_plus_raw REAL,
                notes TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (profile_id) REFERENCES profiles(id)
            )
        """)
        conn.commit()
    migrate_db()


def migrate_db():
    """Add new columns/tables and migrate existing data for existing deployments."""
    with get_db() as conn:
        # Add account_type to users if missing (existing DBs)
        try:
            conn.execute("ALTER TABLE users ADD COLUMN account_type TEXT DEFAULT 'personal'")
            conn.commit()
        except sqlite3.OperationalError:
            pass  # Column already exists

        # Add profile_id to pitches if missing
        try:
            conn.execute("ALTER TABLE pitches ADD COLUMN profile_id TEXT")
            conn.commit()
        except sqlite3.OperationalError:
            pass

        # Migrate: for users with no profile, create one and assign pitches (existing users → personal)
        users = conn.execute("SELECT id, name FROM users").fetchall()
        for user in users:
            has_profile = conn.execute(
                "SELECT 1 FROM profiles WHERE user_id = ? LIMIT 1", (user["id"],)
            ).fetchone()
            if not has_profile:
                conn.execute(
                    "UPDATE users SET account_type = 'personal' WHERE id = ?",
                    (user["id"],),
                )
                profile_id = str(uuid.uuid4())
                now = datetime.now(timezone.utc).isoformat()
                conn.execute(
                    "INSERT INTO profiles (id, user_id, name, created_at) VALUES (?, ?, ?, ?)",
                    (profile_id, user["id"], user["name"], now),
                )
                conn.execute(
                    "UPDATE pitches SET profile_id = ? WHERE user_id = ?",
                    (profile_id, user["id"]),
                )
        conn.commit()


@contextmanager
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------

def create_token(user_id: str, email: str) -> str:
    payload = {
        "sub": user_id,
        "email": email,
        "exp": datetime.now(timezone.utc) + timedelta(days=JWT_EXPIRE_DAYS),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


# ---------------------------------------------------------------------------
# Stuff+ Model
# ---------------------------------------------------------------------------

MODEL_PATH = os.environ.get(
    "STUFF_PLUS_MODEL_PATH",
    os.path.join(os.path.dirname(__file__), "stuff_plus_model2020_2025_2.pkl"),
)

model_college = None


def load_stuff_plus_model():
    global model_college
    if not os.path.exists(MODEL_PATH):
        print(f"WARNING: Model file not found at {MODEL_PATH}")
        return
    dill._dill._reverse_typemap[
        "modeling.aStuffPlusModel.aStuffPlusModel"
    ] = "modeling.aStuffPlusModel2.aStuffPlusModel"
    with open(MODEL_PATH, "rb") as f:
        model_college = dill.load(f)
    model_college.predict_single_pitch = aStuffPlusModel.predict_single_pitch.__get__(
        model_college
    )
    print(f"Stuff+ model loaded from {MODEL_PATH}")


def velocity_penalty(pitch_type: str, avg_velo: float, pfx_z_inches: float, stuff_val: float) -> tuple:
    penalty = 0
    capped_stuff = stuff_val
    if pfx_z_inches > 17:
        pitch_type = "FF"
    fastball_types = ["FF", "SI"]
    if pitch_type in fastball_types:
        avg_mlb = 93
        if avg_velo < avg_mlb:
            penalty = avg_mlb - avg_velo
        if avg_velo < 90:
            capped_stuff = min(capped_stuff, 105)
    elif pitch_type in ("CU", "KC", "ST"):
        avg_mlb = 75
        if avg_velo < avg_mlb:
            penalty = (avg_mlb - avg_velo) * 1.0
    elif pitch_type in ("SL", "FC"):
        avg_mlb = 82
        if avg_velo < avg_mlb:
            penalty = (avg_mlb - avg_velo) * 1.0
    elif pitch_type in ("CH", "SP", "FS"):
        avg_mlb = 78
        if avg_velo < avg_mlb:
            penalty = (avg_mlb - avg_velo) * 1.0
    penalty = min(30, penalty)
    return capped_stuff - penalty, penalty


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

# Auth
class SignupRequest(BaseModel):
    email: str
    name: str
    password: str
    account_type: str = "personal"  # "personal" | "team"

class LoginRequest(BaseModel):
    email: str
    password: str

class AuthResponse(BaseModel):
    token: str
    user_id: str
    email: str
    name: str
    account_type: str = "personal"
    default_profile_id: Optional[str] = None  # For personal: the single profile id

class ProfileResponse(BaseModel):
    id: str
    name: str
    created_at: str


class CreateProfileRequest(BaseModel):
    name: str

# Pitch prediction
class PitchRequest(BaseModel):
    pitch_type: str = Field(..., description="Pitch type code")
    release_speed: float
    pfx_x: float
    pfx_z: float
    release_extension: float
    release_spin_rate: float
    spin_axis: float
    release_pos_x: float
    release_pos_z: float
    p_throws: str
    fb_velo: float
    fb_ivb: float
    fb_hmov: float

class PitchResponse(BaseModel):
    stuff_plus: float
    stuff_plus_raw: float
    velocity_penalty: float


class SuggestResponse(BaseModel):
    suggestion: str

# Saved pitch
class SavePitchRequest(BaseModel):
    profile_id: Optional[str] = None  # Required for team; for personal, use default profile
    pitch_type: str
    pitch_speed: Optional[float] = None
    induced_vert_break: Optional[float] = None
    horz_break: Optional[float] = None
    release_height: Optional[float] = None
    release_side: Optional[float] = None
    extension_ft: Optional[float] = None
    total_spin: Optional[float] = None
    tilt_string: Optional[str] = None
    spin_axis: Optional[float] = None
    efficiency: Optional[float] = None
    active_spin: Optional[float] = None
    gyro: Optional[float] = None
    pitcher_hand: str = "R"
    stuff_plus: Optional[float] = None
    stuff_plus_raw: Optional[float] = None
    notes: Optional[str] = None

class SavedPitchResponse(BaseModel):
    id: str
    pitch_type: str
    pitch_speed: Optional[float] = None
    induced_vert_break: Optional[float] = None
    horz_break: Optional[float] = None
    release_height: Optional[float] = None
    release_side: Optional[float] = None
    extension_ft: Optional[float] = None
    total_spin: Optional[float] = None
    tilt_string: Optional[str] = None
    spin_axis: Optional[float] = None
    efficiency: Optional[float] = None
    active_spin: Optional[float] = None
    gyro: Optional[float] = None
    pitcher_hand: str
    stuff_plus: Optional[float] = None
    stuff_plus_raw: Optional[float] = None
    notes: Optional[str] = None
    created_at: str


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

@app.on_event("startup")
async def startup_event():
    init_db()
    load_stuff_plus_model()


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
async def health_check():
    return {"status": "healthy", "model_loaded": model_college is not None}


# ---------------------------------------------------------------------------
# Auth endpoints
# ---------------------------------------------------------------------------

@app.post("/auth/signup", response_model=AuthResponse)
@limiter.limit("5/hour")
async def signup(request: Request, req: SignupRequest):
    if len(req.password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")
    if not req.email or "@" not in req.email:
        raise HTTPException(status_code=400, detail="Invalid email address")
    account_type = (req.account_type or "personal").lower()
    if account_type not in ("personal", "team"):
        account_type = "personal"

    user_id = str(uuid.uuid4())
    hashed = hash_password(req.password)
    now = datetime.now(timezone.utc).isoformat()
    default_profile_id = None

    with get_db() as conn:
        existing = conn.execute("SELECT id FROM users WHERE email = ?", (req.email.lower(),)).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="An account with this email already exists")
        conn.execute(
            "INSERT INTO users (id, email, name, password_hash, account_type, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            (user_id, req.email.lower(), req.name.strip(), hashed, account_type, now),
        )
        if account_type == "personal":
            profile_id = str(uuid.uuid4())
            conn.execute(
                "INSERT INTO profiles (id, user_id, name, created_at) VALUES (?, ?, ?, ?)",
                (profile_id, user_id, req.name.strip(), now),
            )
            default_profile_id = profile_id
        conn.commit()

    token = create_token(user_id, req.email.lower())
    return AuthResponse(
        token=token, user_id=user_id, email=req.email.lower(), name=req.name.strip(),
        account_type=account_type, default_profile_id=default_profile_id,
    )


@app.post("/auth/login", response_model=AuthResponse)
@limiter.limit("10/minute")
async def login(request: Request, req: LoginRequest):
    with get_db() as conn:
        user = conn.execute(
            "SELECT id, email, name, password_hash, account_type FROM users WHERE email = ?",
            (req.email.lower(),),
        ).fetchone()

    if not user or not verify_password(req.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    account_type = (user["account_type"] or "personal")
    default_profile_id = None
    if account_type == "personal":
        with get_db() as conn:
            profile = conn.execute(
                "SELECT id FROM profiles WHERE user_id = ? ORDER BY created_at ASC LIMIT 1",
                (user["id"],),
            ).fetchone()
            if profile:
                default_profile_id = profile["id"]
            else:
                profile_id = str(uuid.uuid4())
                now = datetime.now(timezone.utc).isoformat()
                conn.execute(
                    "INSERT INTO profiles (id, user_id, name, created_at) VALUES (?, ?, ?, ?)",
                    (profile_id, user["id"], user["name"], now),
                )
                conn.commit()
                default_profile_id = profile_id

    token = create_token(user["id"], user["email"])
    return AuthResponse(
        token=token, user_id=user["id"], email=user["email"], name=user["name"],
        account_type=account_type, default_profile_id=default_profile_id,
    )


@app.get("/auth/me")
async def get_me(payload: dict = Depends(verify_token)):
    with get_db() as conn:
        user = conn.execute(
            "SELECT id, email, name, account_type, created_at FROM users WHERE id = ?",
            (payload["sub"],),
        ).fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    account_type = user["account_type"] or "personal"
    default_profile_id = None
    if account_type == "personal":
        profile = conn.execute(
            "SELECT id FROM profiles WHERE user_id = ? ORDER BY created_at ASC LIMIT 1",
            (user["id"],),
        ).fetchone()
        if profile:
            default_profile_id = profile["id"]
    return {
        "user_id": user["id"],
        "email": user["email"],
        "name": user["name"],
        "account_type": account_type,
        "default_profile_id": default_profile_id,
    }


# ---------------------------------------------------------------------------
# Profiles (for team accounts; personal has one auto-created)
# ---------------------------------------------------------------------------

@app.get("/profiles", response_model=list[ProfileResponse])
async def get_profiles(payload: dict = Depends(verify_token)):
    user_id = payload["sub"]
    with get_db() as conn:
        rows = conn.execute(
            "SELECT id, name, created_at FROM profiles WHERE user_id = ? ORDER BY name ASC",
            (user_id,),
        ).fetchall()
    return [
        ProfileResponse(id=r["id"], name=r["name"], created_at=r["created_at"])
        for r in rows
    ]


@app.post("/profiles", response_model=ProfileResponse, status_code=201)
async def create_profile(
    req: CreateProfileRequest,
    payload: dict = Depends(verify_token),
):
    with get_db() as conn:
        profile_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            "INSERT INTO profiles (id, user_id, name, created_at) VALUES (?, ?, ?, ?)",
            (profile_id, payload["sub"], (req.name or "New Profile").strip(), now),
        )
        conn.commit()
        row = conn.execute(
            "SELECT id, name, created_at FROM profiles WHERE id = ?", (profile_id,)
        ).fetchone()
    return ProfileResponse(id=row["id"], name=row["name"], created_at=row["created_at"])


# ---------------------------------------------------------------------------
# Stuff+ prediction (no auth required — keeps existing behavior)
# ---------------------------------------------------------------------------

@app.post("/predict", response_model=PitchResponse)
@limiter.limit("300/hour")
async def predict_stuff_plus(request: Request, pitch_request: PitchRequest):
    if model_college is None:
        raise HTTPException(status_code=503, detail="Stuff+ model not loaded")
    valid_types = {"FF", "SI", "FC", "SL", "CU", "CH", "ST", "FS", "KC"}
    if pitch_request.pitch_type not in valid_types:
        raise HTTPException(status_code=400, detail=f"Invalid pitch type '{pitch_request.pitch_type}'")
    if pitch_request.p_throws not in ("R", "L"):
        raise HTTPException(status_code=400, detail="p_throws must be 'R' or 'L'")
    try:
        raw_stuff = model_college.predict_single_pitch(
            pitch_type=pitch_request.pitch_type,
            release_speed=pitch_request.release_speed,
            pfx_x=pitch_request.pfx_x,
            pfx_z=pitch_request.pfx_z,
            release_extension=pitch_request.release_extension,
            release_spin_rate=pitch_request.release_spin_rate,
            spin_axis=pitch_request.spin_axis,
            release_pos_x=pitch_request.release_pos_x,
            release_pos_z=pitch_request.release_pos_z,
            p_throws=pitch_request.p_throws,
            fb_velo=pitch_request.fb_velo,
            fb_ivb=pitch_request.fb_ivb,
            fb_hmov=pitch_request.fb_hmov,
        )
        pfx_z_inches = pitch_request.pfx_z * 12
        adjusted_stuff, penalty = velocity_penalty(
            pitch_request.pitch_type, pitch_request.release_speed, pfx_z_inches, raw_stuff
        )
        final_stuff = float(np.clip(adjusted_stuff, 60, 140))
        return PitchResponse(
            stuff_plus=round(final_stuff, 1),
            stuff_plus_raw=round(final_stuff, 1),
            velocity_penalty=0, 
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")


def _run_prediction(
    pitch_type: str,
    release_speed: float,
    pfx_x: float,
    pfx_z: float,
    release_extension: float,
    release_spin_rate: float,
    spin_axis: float,
    release_pos_x: float,
    release_pos_z: float,
    p_throws: str,
    fb_velo: float,
    fb_ivb: float,
    fb_hmov: float,
) -> float:
    """Run a single Stuff+ prediction; returns final stuff_plus value."""
    if model_college is None:
        return 0.0
    raw_stuff = model_college.predict_single_pitch(
        pitch_type=pitch_type,
        release_speed=release_speed,
        pfx_x=pfx_x,
        pfx_z=pfx_z,
        release_extension=release_extension,
        release_spin_rate=release_spin_rate,
        spin_axis=spin_axis,
        release_pos_x=release_pos_x,
        release_pos_z=release_pos_z,
        p_throws=p_throws,
        fb_velo=fb_velo,
        fb_ivb=fb_ivb,
        fb_hmov=fb_hmov,
    )
    pfx_z_inches = pfx_z * 12
    adjusted_stuff, _ = velocity_penalty(
        pitch_type, release_speed, pfx_z_inches, raw_stuff
    )
    return float(np.clip(adjusted_stuff, 60, 140))


@app.post("/predict/suggest", response_model=SuggestResponse)
@limiter.limit("100/hour")
async def suggest_improvement(request: Request, pitch_request: PitchRequest):
    """Run variations (+1 mph, ±1" IVB, ±1" HB, ±1 mph, ±100 rpm) and suggest what would most improve Stuff+."""
    if model_college is None:
        raise HTTPException(status_code=503, detail="Stuff+ model not loaded")
    valid_types = {"FF", "SI", "FC", "SL", "CU", "CH", "ST", "FS", "KC"}
    if pitch_request.pitch_type not in valid_types:
        raise HTTPException(status_code=400, detail=f"Invalid pitch type '{pitch_request.pitch_type}'")
    if pitch_request.p_throws not in ("R", "L"):
        raise HTTPException(status_code=400, detail="p_throws must be 'R' or 'L'")

    base = pitch_request
    inch_to_ft = 1.0 / 12.0

    def run(mod_speed=0, mod_pfx_x=0, mod_pfx_z=0, mod_spin=0):
        return _run_prediction(
            base.pitch_type,
            base.release_speed + mod_speed,
            base.pfx_x + mod_pfx_x,
            base.pfx_z + mod_pfx_z,
            base.release_extension,
            base.release_spin_rate + mod_spin,
            base.spin_axis,
            base.release_pos_x,
            base.release_pos_z,
            base.p_throws,
            base.fb_velo,
            base.fb_ivb,
            base.fb_hmov,
        )

    variations = [
        (+1, 0, 0, 0, "adding 1 mph"),
        (0, 0, inch_to_ft, 0, "adding 1\" IVB"),
        (0, 0, -inch_to_ft, 0, "subtracting 1\" IVB"),
        (0, inch_to_ft, 0, 0, "adding 1\" HB"),
        (0, -inch_to_ft, 0, 0, "subtracting 1\" HB"),
        (-1, 0, 0, 0, "subtracting 1 mph"),
        (0, 0, 0, 100, "adding 100 rpm spin"),
        (0, 0, 0, -100, "subtracting 100 rpm spin"),
    ]

    baseline = run()
    best_improvement = 0.0
    best_suggestion = None

    for mod_speed, mod_pfx_x, mod_pfx_z, mod_spin, label in variations:
        score = run(mod_speed, mod_pfx_x, mod_pfx_z, mod_spin)
        improvement = score - baseline
        if improvement > best_improvement:
            best_improvement = improvement
            best_suggestion = label

    if best_suggestion and best_improvement > 0:
        suggestion = f"To improve Stuff+: try {best_suggestion} (+{best_improvement:.1f})"
    elif best_suggestion:
        suggestion = f"Current Stuff+ is near optimal. Small gains possible: try {best_suggestion}."
    else:
        suggestion = "Current Stuff+ looks strong for this pitch."

    return SuggestResponse(suggestion=suggestion)


# ---------------------------------------------------------------------------
# Pitch storage (auth required)
# ---------------------------------------------------------------------------

@app.post("/pitches", response_model=SavedPitchResponse, status_code=201)
async def save_pitch(req: SavePitchRequest, payload: dict = Depends(verify_token)):
    pitch_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()
    user_id = payload["sub"]

    with get_db() as conn:
        profile_id = req.profile_id
        if not profile_id:
            profile = conn.execute(
                "SELECT id FROM profiles WHERE user_id = ? ORDER BY created_at ASC LIMIT 1",
                (user_id,),
            ).fetchone()
            if profile:
                profile_id = profile["id"]
        if profile_id:
            owner = conn.execute(
                "SELECT user_id FROM profiles WHERE id = ?", (profile_id,)
            ).fetchone()
            if not owner or owner["user_id"] != user_id:
                raise HTTPException(status_code=403, detail="Invalid profile")
        conn.execute(
            """INSERT INTO pitches
               (id, user_id, profile_id, pitch_type, pitch_speed, induced_vert_break, horz_break,
                release_height, release_side, extension_ft, total_spin, tilt_string,
                spin_axis, efficiency, active_spin, gyro, pitcher_hand,
                stuff_plus, stuff_plus_raw, notes, created_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                pitch_id, user_id, profile_id, req.pitch_type, req.pitch_speed,
                req.induced_vert_break, req.horz_break, req.release_height,
                req.release_side, req.extension_ft, req.total_spin,
                req.tilt_string, req.spin_axis, req.efficiency, req.active_spin,
                req.gyro, req.pitcher_hand, req.stuff_plus, req.stuff_plus_raw,
                req.notes, now,
            ),
        )
        conn.commit()

    return SavedPitchResponse(
        id=pitch_id, pitch_type=req.pitch_type, pitch_speed=req.pitch_speed,
        induced_vert_break=req.induced_vert_break, horz_break=req.horz_break,
        release_height=req.release_height, release_side=req.release_side,
        extension_ft=req.extension_ft, total_spin=req.total_spin,
        tilt_string=req.tilt_string, spin_axis=req.spin_axis,
        efficiency=req.efficiency, active_spin=req.active_spin,
        gyro=req.gyro, pitcher_hand=req.pitcher_hand,
        stuff_plus=req.stuff_plus, stuff_plus_raw=req.stuff_plus_raw,
        notes=req.notes, created_at=now,
    )


@app.get("/pitches", response_model=list[SavedPitchResponse])
async def get_pitches(
    payload: dict = Depends(verify_token),
    limit: int = 50,
    offset: int = 0,
    pitch_type: Optional[str] = None,
    profile_id: Optional[str] = None
):
    """Get user's pitches with pagination and filtering. When profile_id is provided, only returns pitches for that profile."""
    user_id = payload["sub"]
    
    # Build query with optional filters
    query = "SELECT * FROM pitches WHERE user_id = ?"
    params = [user_id]
    
    if profile_id:
        query += " AND profile_id = ?"
        params.append(profile_id)
    
    if pitch_type:
        query += " AND pitch_type = ?"
        params.append(pitch_type.upper())
    
    query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])
    
    with get_db() as conn:
        if profile_id:
            owner = conn.execute(
                "SELECT user_id FROM profiles WHERE id = ?", (profile_id,)
            ).fetchone()
            if not owner or owner["user_id"] != user_id:
                raise HTTPException(status_code=403, detail="Invalid profile")
        rows = conn.execute(query, params).fetchall()
    return [
        SavedPitchResponse(
            id=r["id"], pitch_type=r["pitch_type"], pitch_speed=r["pitch_speed"],
            induced_vert_break=r["induced_vert_break"], horz_break=r["horz_break"],
            release_height=r["release_height"], release_side=r["release_side"],
            extension_ft=r["extension_ft"], total_spin=r["total_spin"],
            tilt_string=r["tilt_string"], spin_axis=r["spin_axis"],
            efficiency=r["efficiency"], active_spin=r["active_spin"],
            gyro=r["gyro"], pitcher_hand=r["pitcher_hand"],
            stuff_plus=r["stuff_plus"], stuff_plus_raw=r["stuff_plus_raw"],
            notes=r["notes"], created_at=r["created_at"],
        )
        for r in rows
    ]


@app.delete("/pitches/{pitch_id}", status_code=204)
async def delete_pitch(pitch_id: str, payload: dict = Depends(verify_token)):
    user_id = payload["sub"]
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM pitches WHERE id = ? AND user_id = ?", (pitch_id, user_id)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Pitch not found")
        conn.execute("DELETE FROM pitches WHERE id = ? AND user_id = ?", (pitch_id, user_id))
        conn.commit()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
