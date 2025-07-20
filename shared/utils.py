# shared/utils.py
import hashlib
import jwt
import uuid
import time
import json
from datetime import datetime, timedelta
from typing import Dict, Any, Optional
from .config import Config

config = Config()

def generate_job_id() -> str:
    """Generate unique job ID"""
    return f"job_{uuid.uuid4().hex[:12]}"

def generate_node_id() -> str:
    """Generate unique node ID"""
    return f"node_{uuid.uuid4().hex[:8]}"

def verify_token(token: str) -> bool:
    """Verify JWT token"""
    try:
        payload = jwt.decode(token, config.JWT_SECRET, algorithms=["HS256"])
        return payload.get("exp", 0) > time.time()
    except jwt.InvalidTokenError:
        return False

def create_token(client_id: str, expires_in: int = 3600) -> str:
    """Create JWT token for client"""
    payload = {
        "client_id": client_id,
        "exp": time.time() + expires_in,
        "iat": time.time()
    }
    return jwt.encode(payload, config.JWT_SECRET, algorithm="HS256")

def hash_api_key(api_key: str) -> str:
    """Hash API key for storage"""
    return hashlib.sha256(api_key.encode()).hexdigest()

def estimate_job_cost(model_name: str, input_size: int, gpu_type: str = "generic") -> float:
    """Estimate job cost in $NRG tokens"""
    base_cost = 0.01  # Base cost per job
    
    # Model complexity multiplier
    model_multipliers = {
        "resnet50": 1.0,
        "bert-base": 1.5,
        "gpt-3.5": 2.0,
        "stable-diffusion": 3.0,
        "llama-7b": 4.0,
        "llama-13b": 6.0,
        "llama-70b": 20.0
    }
    
    model_mult = model_multipliers.get(model_name.lower(), 1.0)
    size_mult = max(1.0, input_size / (1024 * 1024))
    
    gpu_multipliers = {
        "rtx3060": 1.0,
        "rtx3090": 0.8,
        "a100": 0.6,
        "m1": 1.2,
        "m2": 0.9,  # M2 is efficient
        "generic": 1.0
    }
    
    gpu_mult = gpu_multipliers.get(gpu_type.lower(), 1.0)
    
    return base_cost * model_mult * size_mult * gpu_mult

def calculate_energy_cost(power_watts: float, execution_time_seconds: float, 
                         energy_price_kwh: float) -> float:
    """Calculate energy cost for job execution"""
    energy_kwh = (power_watts * execution_time_seconds) / (1000 * 3600)
    return energy_kwh * energy_price_kwh

def get_gpu_efficiency_score(gpu_name: str) -> float:
    """Get efficiency score for GPU (performance per watt)"""
    efficiency_scores = {
        "nvidia_a100": 1.0,
        "nvidia_rtx_4090": 0.85,
        "nvidia_rtx_3090": 0.75,
        "apple_m1": 0.95,
        "apple_m2": 0.97,
        "apple_m3": 0.99,
        "generic": 0.50
    }
    
    return efficiency_scores.get(gpu_name.lower(), 0.50)

def validate_model_name(model_name: str) -> bool:
    """Validate model name"""
    supported_models = [
        "resnet50", "bert-base", "gpt-3.5", "stable-diffusion",
        "llama-7b", "llama-13b", "llama-70b", "whisper-base",
        "gpt2", "t5-small"
    ]
    return model_name.lower() in supported_models

def get_region_from_ip(ip_address: str) -> str:
    """Get region from IP address (simplified)"""
    return "eu-west-1"  # Default region
