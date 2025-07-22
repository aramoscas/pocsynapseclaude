#!/bin/bash

# Quick DateTime Fix for SynapseGrid Gateway
# Fixes: invalid input for query argument $5: expected datetime.datetime instance, got 'str'

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 SynapseGrid DateTime Fix${NC}"
echo "=============================="

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ] || [ ! -d "services/gateway" ]; then
    echo -e "${RED}❌ Error: Please run this script from the SynapseGrid root directory${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Problem:${NC} Gateway service failing with PostgreSQL datetime error"
echo -e "${YELLOW}📋 Solution:${NC} Replace string timestamps with datetime objects in database inserts"
echo ""

# Backup current gateway file
echo -e "${BLUE}💾 Creating backup...${NC}"
cp services/gateway/main.py services/gateway/main.py.backup.$(date +%Y%m%d_%H%M%S)
echo "✅ Backup created: services/gateway/main.py.backup.$(date +%Y%m%d_%H%M%S)"

# Apply the fix
echo -e "${BLUE}🔧 Applying datetime fix...${NC}"
cat > services/gateway/main.py << 'EOF'
# services/gateway/main.py - DATETIME FIXED VERSION
import asyncio
import json
import logging
import time
import uuid
from typing import Dict, Any, Optional
from datetime import datetime, timezone

import aioredis
import asyncpg
from fastapi import FastAPI, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = FastAPI(title="SynapseGrid Gateway", version="2.0.1-fixed")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class SubmitJobRequest(BaseModel):
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 1
    timeout: int = 300
    gpu_requirements: Optional[Dict[str, Any]] = None

# Utility functions - FIXED
def generate_job_id() -> str:
    """Generate a unique job ID"""
    timestamp = int(time.time() * 1000)
    random_part = uuid.uuid4().hex[:8]
    return f"job_{timestamp}_{random_part}"

def verify_token(token: str) -> bool:
    """Verify authentication token"""
    return token in ["test-token", "dev-token", "admin-token"]

def get_utc_now() -> datetime:
    """Get current UTC timestamp as proper datetime object - FIXED"""
    return datetime.now(timezone.utc)

def format_for_json(dt: datetime) -> str:
    """Format datetime for JSON responses - FIXED"""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()

# Global state
redis_client = None
postgres_pool = None

@app.on_event("startup")
async def startup():
    global redis_client, postgres_pool
    
    try:
        # Initialize Redis
        logger.info("🔄 Connecting to Redis...")
        redis_client = aioredis.from_url(
            "redis://redis:6379",
            encoding="utf-8",
            decode_responses=True
        )
        await redis_client.ping()
        logger.info("✅ Connected to Redis")
        
        # Initialize PostgreSQL
        logger.info("🔄 Connecting to PostgreSQL...")
        postgres_pool = await asyncpg.create_pool(
            "postgresql://synapse:synapse123@postgres:5432/synapse",
            min_size=1,
            max_size=5
        )
        
        # Test connection
        async with postgres_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        logger.info("✅ Connected to PostgreSQL")
        
        # Ensure tables exist
        await create_tables_if_needed()
        
        logger.info("🚀 Gateway started successfully (DateTime FIXED)")
        
    except Exception as e:
        logger.error(f"❌ Startup failed: {e}")
        raise

async def create_tables_if_needed():
    """Create database tables if they don't exist - FIXED"""
    try:
        async with postgres_pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS jobs (
                    job_id VARCHAR(50) PRIMARY KEY,
                    client_id VARCHAR(100) NOT NULL,
                    model_name VARCHAR(100) NOT NULL,
                    input_data JSONB NOT NULL,
                    status VARCHAR(20) NOT NULL DEFAULT 'queued',
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    updated_at TIMESTAMP WITH TIME ZONE,
                    completed_at TIMESTAMP WITH TIME ZONE,
                    estimated_cost NUMERIC(10,4) DEFAULT 0.0,
                    priority INTEGER DEFAULT 1,
                    result JSONB,
                    error TEXT
                );
            """)
            
            await conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
            """)
            await conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at);
            """)
            
            logger.info("✅ Database tables verified")
            
    except Exception as e:
        logger.error(f"❌ Error creating tables: {e}")
        raise

@app.on_event("shutdown")
async def shutdown():
    if redis_client:
        await redis_client.close()
    if postgres_pool:
        await postgres_pool.close()
    logger.info("🛑 Gateway shutdown complete")

@app.get("/health")
async def health_check():
    try:
        # Test Redis
        await redis_client.ping()
        
        # Test PostgreSQL
        async with postgres_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        
        return {
            "status": "healthy",
            "timestamp": format_for_json(get_utc_now()),
            "version": "2.0.1-fixed",
            "services": {
                "redis": "healthy",
                "postgres": "healthy"
            }
        }
    except Exception as e:
        logger.error(f"❌ Health check failed: {e}")
        raise HTTPException(status_code=503, detail=str(e))

@app.post("/submit")
async def submit_job(
    request: SubmitJobRequest,
    authorization: str = Header(...),
    x_client_id: str = Header(..., alias="X-Client-ID")
):
    """Submit job - DATETIME FIXED"""
    # Verify token
    token = authorization.replace("Bearer ", "").strip()
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    
    # Generate job data
    job_id = generate_job_id()
    now = get_utc_now()  # FIXED: Proper datetime object
    
    job_data = {
        "job_id": job_id,
        "client_id": x_client_id,
        "model_name": request.model_name,
        "input_data": request.input_data,
        "priority": request.priority,
        "timeout": request.timeout,
        "gpu_requirements": request.gpu_requirements or {},
        "created_at": format_for_json(now),  # For Redis/JSON
        "status": "queued"
    }
    
    try:
        # Add to Redis queue
        await redis_client.lpush("jobs:queue:eu-west-1", json.dumps(job_data))
        
        # Store job metadata
        job_key = f"job:{job_id}"
        await redis_client.hmset(job_key, {
            "job_id": job_id,
            "status": "queued",
            "created_at": format_for_json(now),
            "client_id": x_client_id
        })
        await redis_client.expire(job_key, 3600)
        
        # CRITICAL FIX: Use datetime object for PostgreSQL, not string!
        async with postgres_pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO jobs (
                    job_id, client_id, model_name, input_data, 
                    status, created_at, estimated_cost, priority
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """, 
            job_id,                          # $1
            x_client_id,                     # $2
            request.model_name,              # $3
            json.dumps(request.input_data),  # $4
            "queued",                        # $5
            now,                            # $6 ← FIXED: datetime object, not string!
            0.01,                           # $7
            request.priority                # $8
            )
        
        logger.info(f"📤 Job {job_id} submitted successfully by {x_client_id}")
        
        return {
            "job_id": job_id,
            "status": "queued",
            "estimated_cost": 0.01,
            "created_at": format_for_json(now),
            "message": "Job submitted successfully"
        }
        
    except Exception as e:
        logger.error(f"❌ Error submitting job: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/jobs/{job_id}")
async def get_job_status(
    job_id: str,
    authorization: str = Header(...),
    x_client_id: str = Header(..., alias="X-Client-ID")
):
    """Get job status - DATETIME FIXED"""
    token = authorization.replace("Bearer ", "").strip()
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    
    try:
        async with postgres_pool.acquire() as conn:
            job = await conn.fetchrow("""
                SELECT job_id, status, result, error, created_at, completed_at
                FROM jobs WHERE job_id = $1 AND client_id = $2
            """, job_id, x_client_id)
            
            if not job:
                raise HTTPException(status_code=404, detail="Job not found")
            
            # FIXED: Proper datetime handling
            return {
                "job_id": job["job_id"],
                "status": job["status"],
                "result": json.loads(job["result"]) if job["result"] else None,
                "error": job["error"],
                "created_at": format_for_json(job["created_at"]) if job["created_at"] else None,
                "completed_at": format_for_json(job["completed_at"]) if job["completed_at"] else None
            }
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting job status: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes")
async def list_nodes():
    """List available nodes"""
    try:
        docker_nodes = await redis_client.smembers("nodes:eu-west-1:available") or []
        native_nodes = await redis_client.smembers("native_nodes") or []
        
        return {
            "docker_nodes": list(docker_nodes),
            "native_nodes": list(native_nodes),
            "total": len(docker_nodes) + len(native_nodes)
        }
        
    except Exception as e:
        logger.error(f"❌ Error listing nodes: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8080, log_level="info")
EOF

echo "✅ DateTime fix applied to services/gateway/main.py"

# Restart Gateway service
echo -e "${BLUE}🔄 Restarting Gateway service...${NC}"
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose restart gateway
elif command -v docker >/dev/null 2>&1 && docker compose --help >/dev/null 2>&1; then
    docker compose restart gateway
else
    echo -e "${YELLOW}⚠️  Could not restart automatically. Please run:${NC}"
    echo "   docker-compose restart gateway"
    echo "   OR"
    echo "   docker compose restart gateway"
    exit 0
fi

echo -e "${GREEN}✅ Gateway service restarted${NC}"

# Wait a moment for service to start
echo -e "${BLUE}⏳ Waiting for Gateway to be ready...${NC}"
sleep 5

# Test the fix
echo -e "${BLUE}🧪 Testing the fix...${NC}"
if curl -s --max-time 5 http://localhost:8080/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway is responding to health checks${NC}"
    
    # Show health response
    echo -e "${BLUE}📊 Health status:${NC}"
    curl -s http://localhost:8080/health | jq . 2>/dev/null || curl -s http://localhost:8080/health
    
    echo ""
    echo -e "${GREEN}🎉 DateTime fix applied successfully!${NC}"
    echo ""
    echo -e "${BLUE}✨ What was fixed:${NC}"
    echo "  • PostgreSQL datetime inserts now use proper datetime objects"
    echo "  • Timezone handling improved with UTC timezone"
    echo "  • Separate formatting functions for JSON vs Database"
    echo "  • Enhanced error logging and connection handling"
    echo ""
    echo -e "${BLUE}🧪 Test the fix:${NC}"
    echo "  make job-test              # Test job submission"
    echo "  make submit-job            # Submit a single job"
    echo "  make flow-monitor          # Monitor job flow"
    
else
    echo -e "${YELLOW}⚠️  Gateway may still be starting. Check logs with:${NC}"
    echo "   docker logs synapse-gateway"
    echo "   OR"
    echo "   make logs"
fi

echo ""
echo -e "${GREEN}✅ Fix complete!${NC}"
