-- Tables de base pour SynapseGrid
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(50) PRIMARY KEY,
    model_name VARCHAR(100),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nodes (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);
