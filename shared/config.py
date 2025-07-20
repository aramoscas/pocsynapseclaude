# shared/config.py
import os
from dataclasses import dataclass

@dataclass
class Config:
    # Database URLs
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379")
    POSTGRES_URL: str = os.getenv("POSTGRES_URL", "postgresql://synapse:synapse123@localhost:5432/synapse")
    
    # Service Configuration
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    
    # Gateway Configuration
    GATEWAY_HOST: str = os.getenv("GATEWAY_HOST", "0.0.0.0")
    GATEWAY_PORT: int = int(os.getenv("GATEWAY_PORT", "8080"))
    
    # Security
    JWT_SECRET: str = os.getenv("JWT_SECRET", "synapse-secret-key-change-in-production")
    TOKEN_CACHE_TTL: int = int(os.getenv("TOKEN_CACHE_TTL", "15"))
    
    # Job Configuration
    DEFAULT_JOB_TIMEOUT: int = int(os.getenv("DEFAULT_JOB_TIMEOUT", "300"))
    MAX_RETRIES: int = int(os.getenv("MAX_RETRIES", "3"))
    
    # Node Configuration
    NODE_HEARTBEAT_INTERVAL: int = int(os.getenv("NODE_HEARTBEAT_INTERVAL", "10"))
    NODE_TIMEOUT: int = int(os.getenv("NODE_TIMEOUT", "30"))
    
    # Blockchain Configuration
    POLYGON_RPC_URL: str = os.getenv("POLYGON_RPC_URL", "https://polygon-rpc.com")
    CONTRACT_ADDRESS_NRG: str = os.getenv("CONTRACT_ADDRESS_NRG", "")
    CONTRACT_ADDRESS_LEAR: str = os.getenv("CONTRACT_ADDRESS_LEAR", "")
    
    # Monitoring
    PROMETHEUS_PORT: int = int(os.getenv("PROMETHEUS_PORT", "9090"))
    GRAFANA_PORT: int = int(os.getenv("GRAFANA_PORT", "3001"))
