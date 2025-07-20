-- sql/init.sql
-- SynapseGrid Enhanced Database Schema

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Clients table
CREATE TABLE IF NOT EXISTS clients (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(64) NOT NULL,
    nrg_balance DECIMAL(18, 8) DEFAULT 0.0,
    lear_balance DECIMAL(18, 8) DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_jobs INTEGER DEFAULT 0,
    total_spent_nrg DECIMAL(18, 8) DEFAULT 0.0,
    status VARCHAR(20) DEFAULT 'active',
    
    CONSTRAINT clients_client_id_check CHECK (length(client_id) > 0),
    CONSTRAINT clients_nrg_balance_check CHECK (nrg_balance >= 0),
    CONSTRAINT clients_lear_balance_check CHECK (lear_balance >= 0)
);

-- Enhanced Jobs table
CREATE TABLE IF NOT EXISTS jobs (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) UNIQUE NOT NULL,
    client_id VARCHAR(64) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    input_data JSONB NOT NULL,
    gpu_requirements JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'queued',
    priority INTEGER DEFAULT 1,
    estimated_cost DECIMAL(10, 6) NOT NULL,
    actual_cost DECIMAL(10, 6),
    assigned_node VARCHAR(64),
    result JSONB,
    error TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    execution_time_ms INTEGER,
    retry_count INTEGER DEFAULT 0,
    target_node_type VARCHAR(50),
    
    CONSTRAINT jobs_job_id_check CHECK (length(job_id) > 0),
    CONSTRAINT jobs_status_check CHECK (status IN ('queued', 'dispatched', 'running', 'completed', 'failed', 'cancelled')),
    CONSTRAINT jobs_priority_check CHECK (priority >= 1 AND priority <= 10)
);

-- Enhanced Nodes table with native node support
CREATE TABLE IF NOT EXISTS nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    region VARCHAR(50) NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    gpu_info JSONB NOT NULL,
    cpu_info JSONB NOT NULL,
    memory_gb DECIMAL(8, 2) NOT NULL,
    disk_gb DECIMAL(10, 2) NOT NULL,
    network_speed_mbps INTEGER NOT NULL,
    energy_cost_kwh DECIMAL(8, 4) NOT NULL,
    capabilities JSONB NOT NULL,
    status VARCHAR(20) DEFAULT 'offline',
    current_load DECIMAL(3, 2) DEFAULT 0.0,
    capacity DECIMAL(3, 2) DEFAULT 1.0,
    success_rate DECIMAL(4, 3) DEFAULT 1.0,
    avg_latency_ms INTEGER DEFAULT 100,
    total_jobs_completed INTEGER DEFAULT 0,
    total_execution_time_ms BIGINT DEFAULT 0,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT nodes_status_check CHECK (status IN ('offline', 'available', 'busy', 'failed', 'maintenance', 'stale'))
);

-- Job execution history
CREATE TABLE IF NOT EXISTS job_executions (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) NOT NULL,
    node_id VARCHAR(64) NOT NULL,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    execution_time_ms INTEGER,
    gpu_memory_used_gb DECIMAL(8, 3),
    energy_consumed_kwh DECIMAL(10, 6),
    success BOOLEAN NOT NULL,
    error_type VARCHAR(100),
    error_message TEXT,
    
    CONSTRAINT job_executions_execution_time_check CHECK (execution_time_ms >= 0)
);

-- Transactions table
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    tx_id VARCHAR(64) UNIQUE NOT NULL,
    client_id VARCHAR(64),
    node_id VARCHAR(64),
    job_id VARCHAR(64),
    amount DECIMAL(18, 8) NOT NULL,
    token_type VARCHAR(10) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    blockchain_tx_hash VARCHAR(66),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP,
    
    CONSTRAINT transactions_token_type_check CHECK (token_type IN ('NRG', 'LEAR')),
    CONSTRAINT transactions_type_check CHECK (transaction_type IN ('debit', 'credit', 'reward', 'penalty'))
);

-- Native job tracking
CREATE TABLE IF NOT EXISTS native_job_queue (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) NOT NULL,
    node_id VARCHAR(64),
    queued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_at TIMESTAMP,
    status VARCHAR(20) DEFAULT 'queued',
    node_type VARCHAR(50) DEFAULT 'mac_m2_native',
    
    CONSTRAINT native_job_queue_status_check CHECK (status IN ('queued', 'assigned', 'completed', 'failed'))
);

-- Node performance metrics
CREATE TABLE IF NOT EXISTS node_metrics (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    cpu_usage_percent DECIMAL(5, 2),
    memory_usage_percent DECIMAL(5, 2),
    gpu_usage_percent DECIMAL(5, 2),
    gpu_memory_usage_percent DECIMAL(5, 2),
    temperature_celsius DECIMAL(5, 1),
    power_consumption_watts DECIMAL(8, 2),
    network_io_mbps DECIMAL(10, 2)
);

-- Regions table
CREATE TABLE IF NOT EXISTS regions (
    id SERIAL PRIMARY KEY,
    region_id VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    country VARCHAR(50) NOT NULL,
    datacenter_locations TEXT[],
    avg_energy_cost_kwh DECIMAL(8, 4) NOT NULL,
    carbon_intensity_gco2_kwh INTEGER NOT NULL,
    active_nodes INTEGER DEFAULT 0
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_jobs_client_id ON jobs(client_id);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_target_node_type ON jobs(target_node_type);
CREATE INDEX IF NOT EXISTS idx_nodes_node_type ON nodes(node_type);
CREATE INDEX IF NOT EXISTS idx_nodes_region ON nodes(region);
CREATE INDEX IF NOT EXISTS idx_nodes_status ON nodes(status);
CREATE INDEX IF NOT EXISTS idx_native_job_queue_status ON native_job_queue(status);

-- Insert default data
INSERT INTO regions (region_id, name, country, datacenter_locations, avg_energy_cost_kwh, carbon_intensity_gco2_kwh) VALUES
    ('eu-west-1', 'Europe West 1', 'Ireland', ARRAY['Dublin'], 0.25, 300),
    ('us-east-1', 'US East 1', 'United States', ARRAY['Virginia'], 0.12, 400),
    ('ap-south-1', 'Asia Pacific South 1', 'India', ARRAY['Mumbai'], 0.08, 600),
    ('local-mac', 'Local Mac', 'Various', ARRAY['Local'], 0.15, 200)
ON CONFLICT (region_id) DO NOTHING;

-- Insert test clients
INSERT INTO clients (client_id, api_key_hash, nrg_balance, lear_balance) VALUES
    ('test-client', encode(digest('test-api-key', 'sha256'), 'hex'), 100.0, 10.0),
    ('mac-test-client', encode(digest('mac-test-key', 'sha256'), 'hex'), 1000.0, 100.0),
    ('stress-test', encode(digest('stress-test-key', 'sha256'), 'hex'), 500.0, 50.0)
ON CONFLICT (client_id) DO NOTHING;

-- Create views
CREATE OR REPLACE VIEW v_native_node_performance AS
SELECT 
    n.node_id,
    n.node_type,
    n.region,
    n.status,
    n.success_rate,
    n.total_jobs_completed,
    n.avg_latency_ms,
    n.last_seen
FROM nodes n
WHERE n.node_type LIKE '%native%';

-- Create function to update node statistics
CREATE OR REPLACE FUNCTION update_node_stats(p_node_id VARCHAR(64))
RETURNS void AS $$
DECLARE
    total_jobs INTEGER;
    total_time BIGINT;
    success_count INTEGER;
BEGIN
    SELECT 
        COUNT(*),
        COALESCE(SUM(execution_time_ms), 0),
        COUNT(*) FILTER (WHERE success = true)
    INTO total_jobs, total_time, success_count
    FROM job_executions 
    WHERE node_id = p_node_id;
    
    UPDATE nodes SET
        total_jobs_completed = total_jobs,
        total_execution_time_ms = total_time,
        success_rate = CASE 
            WHEN total_jobs > 0 THEN success_count::DECIMAL / total_jobs 
            ELSE 1.0 
        END,
        avg_latency_ms = CASE 
            WHEN total_jobs > 0 THEN (total_time / total_jobs)::INTEGER 
            ELSE 100 
        END
    WHERE node_id = p_node_id;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO synapse;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO synapse;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO synapse;
