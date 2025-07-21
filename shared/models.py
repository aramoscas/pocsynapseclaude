"""Shared data models"""

from enum import Enum
from datetime import datetime
from typing import Dict, Any, Optional
from pydantic import BaseModel

class JobStatus(Enum):
    PENDING = "pending"
    ASSIGNED = "assigned"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

class NodeStatus(Enum):
    ONLINE = "online"
    OFFLINE = "offline"
    BUSY = "busy"
    MAINTENANCE = "maintenance"

class Job(BaseModel):
    job_id: str
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 1
    client_id: str
    status: JobStatus = JobStatus.PENDING
    submitted_at: datetime
    assigned_node: Optional[str] = None
    assigned_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    region: str

class Node(BaseModel):
    node_id: str
    region: str
    status: NodeStatus = NodeStatus.OFFLINE
    capabilities: Dict[str, Any]
    registered_at: datetime
    last_heartbeat: float
    cpu_usage: float = 0.0
    memory_available: float = 100.0
    success_rate: float = 100.0
    avg_response_time: float = 0.0
    uptime_hours: float = 0.0
