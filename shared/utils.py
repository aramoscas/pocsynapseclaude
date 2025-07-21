"""Shared utilities for all services"""

import os
import redis.asyncio as redis
from sqlalchemy import create_engine
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

async def get_redis_client():
    """Get Redis client"""
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
    return await redis.from_url(redis_url, decode_responses=True)

def get_postgres_engine():
    """Get PostgreSQL engine"""
    postgres_url = os.getenv("POSTGRES_URL", "postgresql://synapse:synapse123@localhost:5432/synapse")
    return create_engine(postgres_url)

async def get_async_postgres_session():
    """Get async PostgreSQL session"""
    postgres_url = os.getenv("POSTGRES_URL", "postgresql://synapse:synapse123@localhost:5432/synapse")
    # Convert to async URL
    async_url = postgres_url.replace("postgresql://", "postgresql+asyncpg://")
    
    engine = create_async_engine(async_url)
    async_session = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )
    
    async with async_session() as session:
        yield session
