# shared/models.py
from dataclasses import dataclass
from typing import Dict, Any, Optional, List
from datetime import datetime
from pydantic import BaseModel
import uuid

# === Job Models ===
@dataclass
class JobRequest:
    job_id: str
    model_name: str
    input_data: str  # JSON serialized
    timeout: int = 300
    priority: int = 1
    gpu_requirements: Optional[Dict[str, Any]] = None

@dataclass
class JobResponse:
    job_id: str
    success: bool
    result: Optional[str] = None  # JSON serialized
    error: Optional[str] = None
    execution_time: Optional[float] = None
    node_id: Optional[str] = None

# === Node Models ===
@dataclass
class GPUInfo:
    name: str
    memory_gb: float
    compute_capability: float
    driver_version: str
    cuda_cores: Optional[int] = None
    tensor_cores: Optional[int] = None

@dataclass
class NodeInfo:
    node_id: str
    region: str
    gpu_info: GPUInfo
    cpu_info: Dict[str, Any]
    memory_gb: float
    disk_gb: float
    network_speed_mbps: float
    energy_cost_kwh: float
    status: str = "initializing"
    
@dataclass
class NodeCapabilities:
    supported_models: List[str]
    max_batch_size: int
    supported_frameworks: List[str]  # ["onnx", "pytorch", "tensorflow"]
    confidential_compute: bool = False

# === Heartbeat Models ===
@dataclass
class NodeHeartbeat:
    node_id: str
    timestamp: datetime
    status: str
    current_load: float  # 0.0 to 1.0
    available_memory_gb: float
    gpu_utilization: float
    temperature_celsius: Optional[float] = None
    last_job_id: Optional[str] = None

# === Performance Models ===
@dataclass
class JobMetrics:
    job_id: str
    node_id: str
    model_name: str
    input_size_bytes: int
    execution_time_ms: float
    gpu_memory_used_gb: float
    energy_consumed_kwh: float
    success: bool
    error_type: Optional[str] = None

# === Token Models ===
class TokenBalance(BaseModel):
    client_id: str
    nrg_balance: float
    lear_balance: float
    last_updated: datetime

class Transaction(BaseModel):
    tx_id: str
    client_id: str
    job_id: Optional[str]
    amount: float
    token_type: str  # "NRG" or "LEAR"
    transaction_type: str  # "debit", "credit", "reward"
    timestamp: datetime

# === Client Models ===
class ClientInfo(BaseModel):
    client_id: str
    api_key_hash: str
    created_at: datetime
    last_active: datetime
    total_jobs: int = 0
    total_spent_nrg: float = 0.0

# === Region Models ===
@dataclass
class RegionInfo:
    region_id: str
    name: str
    country: str
    datacenter_locations: List[str]
    avg_energy_cost_kwh: float
    carbon_intensity_gco2_kwh: float
