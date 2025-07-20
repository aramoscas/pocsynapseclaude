-- SynapseGrid Database Schema

CREATE TABLE IF NOT EXISTS jobs (
    job_id VARCHAR(36) PRIMARY KEY,
    client_id VARCHAR(100) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'queued',
    region VARCHAR(20),
    node_id VARCHAR(100),
    priority INTEGER DEFAULT 1,
    created_at DECIMAL(15,3) NOT NULL,
    dispatched_at DECIMAL(15,3),
    completed_at DECIMAL(15,3),
    execution_time DECIMAL(10,3),
    cost DECIMAL(10,6),
    result_data JSONB,
    error_message TEXT
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at);
CREATE INDEX idx_jobs_client_id ON jobs(client_id);

CREATE TABLE IF NOT EXISTS nodes (
    node_id VARCHAR(100) PRIMARY KEY,
    region VARCHAR(20) NOT NULL,
    gpu_type VARCHAR(50),
    gpu_memory INTEGER,
    cpu_cores INTEGER,
    status VARCHAR(20) DEFAULT 'active',
    last_seen DECIMAL(15,3),
    performance_score DECIMAL(5,2),
    total_jobs INTEGER DEFAULT 0,
    successful_jobs INTEGER DEFAULT 0,
    total_earnings DECIMAL(15,6) DEFAULT 0
);

CREATE TABLE IF NOT EXISTS clients (
    client_id VARCHAR(100) PRIMARY KEY,
    webhook_url VARCHAR(500),
    created_at DECIMAL(15,3) NOT NULL
);

-- Initial test data
INSERT INTO jobs (job_id, client_id, model_name, status, region, created_at) 
VALUES 
    ('test-job-001', 'test-client', 'resnet50', 'completed', 'eu-west-1', extract(epoch from now())),
    ('test-job-002', 'test-client', 'bert-base', 'queued', 'us-east-1', extract(epoch from now()));
