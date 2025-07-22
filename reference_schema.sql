-- Schéma de référence complet pour SynapseGrid

-- Table clients complète
CREATE TABLE IF NOT EXISTS clients (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(64) NOT NULL,
    nrg_balance DECIMAL(18, 8) DEFAULT 100.0,
    lear_balance DECIMAL(18, 8) DEFAULT 10.0,
    total_jobs INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table jobs complète
CREATE TABLE IF NOT EXISTS jobs (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) UNIQUE NOT NULL,
    client_id VARCHAR(64) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    input_data TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'queued',
    priority INTEGER DEFAULT 1,
    estimated_cost DECIMAL(10, 6) DEFAULT 0.01,
    assigned_node VARCHAR(64),
    result TEXT,
    error TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    execution_time_ms INTEGER,
    CONSTRAINT jobs_status_check CHECK (status IN ('queued', 'dispatched', 'running', 'completed', 'failed', 'cancelled'))
);

-- Table nodes complète
CREATE TABLE IF NOT EXISTS nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    region VARCHAR(50) DEFAULT 'eu-west-1',
    endpoint VARCHAR(255),
    status VARCHAR(20) DEFAULT 'offline',
    capabilities TEXT DEFAULT '{}',
    gpu_info TEXT DEFAULT '{}',
    cpu_cores INTEGER DEFAULT 4,
    memory_gb DECIMAL(8, 2) DEFAULT 16.0,
    success_rate DECIMAL(5, 4) DEFAULT 1.0,
    total_jobs INTEGER DEFAULT 0,
    avg_latency_ms INTEGER DEFAULT 100,
    current_load INTEGER DEFAULT 0,
    max_concurrent INTEGER DEFAULT 1,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
