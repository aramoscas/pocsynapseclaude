-- SynapseGrid Complete Database Schema
-- Auto-create and fix all tables

-- Drop tables in correct order (handle dependencies)
DROP TABLE IF EXISTS job_executions CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS job_results CASCADE;
DROP TABLE IF EXISTS jobs CASCADE;
DROP TABLE IF EXISTS nodes CASCADE;
DROP TABLE IF EXISTS clients CASCADE;
DROP TABLE IF EXISTS regions CASCADE;

-- Create clients table
CREATE TABLE clients (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(128) NOT NULL,
    nrg_balance DECIMAL(18, 8) DEFAULT 1000.0,
    lear_balance DECIMAL(18, 8) DEFAULT 0.0,
    total_jobs_submitted INTEGER DEFAULT 0,
    total_nrg_spent DECIMAL(18, 8) DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active',
    CONSTRAINT clients_status_check CHECK (status IN ('active', 'suspended', 'inactive'))
);

-- Create nodes table
CREATE TABLE nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    region VARCHAR(50) DEFAULT 'eu-west-1',
    ip_address INET,
    port INTEGER DEFAULT 8003,
    capacity DECIMAL(5, 2) DEFAULT 1.0,
    current_load DECIMAL(5, 2) DEFAULT 0.0,
    gpu_info JSONB DEFAULT '{}',
    cpu_info JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'offline',
    total_jobs_completed INTEGER DEFAULT 0,
    total_nrg_earned DECIMAL(18, 8) DEFAULT 0.0,
    reliability_score DECIMAL(5, 4) DEFAULT 1.0,
    average_latency_ms INTEGER DEFAULT 100,
    last_heartbeat TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'
);

-- Create jobs table with all necessary columns
CREATE TABLE jobs (
    id VARCHAR(64) PRIMARY KEY,
    job_id VARCHAR(64) UNIQUE NOT NULL,
    client_id VARCHAR(64) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    model_version VARCHAR(50),
    input_data JSONB NOT NULL,
    output_data JSONB,
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 1,
    estimated_cost DECIMAL(10, 6) DEFAULT 0.01,
    actual_cost DECIMAL(10, 6),
    assigned_node VARCHAR(64),
    node_id VARCHAR(64),  -- For compatibility
    region_preference VARCHAR(50) DEFAULT 'eu-west-1',
    gpu_requirements JSONB DEFAULT '{}',
    error_message TEXT,
    error TEXT,  -- For compatibility
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- For compatibility
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    execution_time_ms INTEGER,
    compute_time_ms INTEGER,  -- For compatibility
    queue_time_ms INTEGER,
    tokens_used INTEGER,
    tokens_processed INTEGER,  -- For compatibility
    CONSTRAINT jobs_priority_check CHECK (priority >= 0 AND priority <= 10),
    CONSTRAINT jobs_status_check CHECK (status IN ('pending', 'queued', 'assigned', 'processing', 'completed', 'failed', 'cancelled'))
);

-- Create indexes
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_client_id ON jobs(client_id);
CREATE INDEX idx_jobs_assigned_node ON jobs(assigned_node);
CREATE INDEX idx_jobs_created_at ON jobs(created_at DESC);
CREATE INDEX idx_jobs_status_priority ON jobs(status, priority DESC);
CREATE INDEX idx_nodes_status ON nodes(status);
CREATE INDEX idx_nodes_region ON nodes(region);
CREATE INDEX idx_clients_client_id ON clients(client_id);

-- Insert default clients
INSERT INTO clients (client_id, api_key_hash, nrg_balance) VALUES
    ('test-client', encode(digest('test-token', 'sha256'), 'hex'), 1000.0),
    ('deploy-test', encode(digest('deploy-token', 'sha256'), 'hex'), 1000.0),
    ('cli', encode(digest('cli-token', 'sha256'), 'hex'), 500.0),
    ('anonymous', encode(digest('anon-token', 'sha256'), 'hex'), 100.0),
    ('debug-test', encode(digest('debug-token', 'sha256'), 'hex'), 1000.0),
    ('emergency-test', encode(digest('emergency-token', 'sha256'), 'hex'), 1000.0),
    ('test-fix', encode(digest('test-fix-token', 'sha256'), 'hex'), 1000.0)
ON CONFLICT (client_id) DO UPDATE SET 
    nrg_balance = EXCLUDED.nrg_balance,
    last_active = CURRENT_TIMESTAMP;

-- Create views for monitoring
CREATE OR REPLACE VIEW active_jobs AS
SELECT j.job_id, j.client_id, j.model_name, j.status, 
       COALESCE(j.assigned_node, j.node_id) as assigned_node,
       j.created_at, j.started_at
FROM jobs j
WHERE j.status NOT IN ('completed', 'failed', 'cancelled');

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO synapse;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO synapse;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO synapse;

-- Success message
SELECT 'Database initialized successfully!' as status;
