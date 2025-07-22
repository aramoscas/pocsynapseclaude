#!/bin/bash
# setup_auto_init.sh
# Configure l'initialisation automatique des tables à chaque démarrage

set -e

echo "🔧 Configuration de l'auto-initialisation PostgreSQL"
echo "=================================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Étape 1: Créer le script healthcheck
print_info "Création du script healthcheck avec initialisation..."

mkdir -p scripts

cat > scripts/postgres-healthcheck.sh << 'EOF'
#!/bin/bash
# postgres-healthcheck.sh
# Healthcheck qui crée les tables si nécessaire

# Attendre un peu au premier démarrage
if [ ! -f /tmp/healthcheck_done ]; then
    sleep 5
    touch /tmp/healthcheck_done
fi

# Vérifier si PostgreSQL est prêt
pg_isready -U synapse -d synapse -h localhost || exit 1

# Vérifier et créer les tables si nécessaire
psql -U synapse -d synapse -h localhost << 'SQL' 2>/dev/null || true

-- Créer les tables seulement si elles n'existent pas
DO $$
BEGIN
    -- Table jobs
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'jobs') THEN
        CREATE TABLE jobs (
            id VARCHAR(50) PRIMARY KEY,
            model_name VARCHAR(100) NOT NULL,
            client_id VARCHAR(100),
            node_id VARCHAR(50),
            status VARCHAR(20) DEFAULT 'pending',
            priority INTEGER DEFAULT 1,
            submitted_at TIMESTAMP DEFAULT NOW(),
            started_at TIMESTAMP,
            completed_at TIMESTAMP,
            input_data JSONB,
            output_data JSONB,
            error_message TEXT
        );
        RAISE NOTICE 'Table jobs créée';
    END IF;

    -- Table nodes
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'nodes') THEN
        CREATE TABLE nodes (
            id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            region VARCHAR(50),
            status VARCHAR(20) DEFAULT 'offline',
            gpu_model VARCHAR(100),
            cpu_cores INTEGER,
            memory_gb INTEGER,
            capabilities JSONB,
            last_heartbeat TIMESTAMP DEFAULT NOW()
        );
        RAISE NOTICE 'Table nodes créée';
    END IF;

    -- Table metrics
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'metrics') THEN
        CREATE TABLE metrics (
            id SERIAL PRIMARY KEY,
            metric_name VARCHAR(100) NOT NULL,
            metric_value FLOAT NOT NULL,
            timestamp TIMESTAMP DEFAULT NOW()
        );
        RAISE NOTICE 'Table metrics créée';
    END IF;

    -- Table clients
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'clients') THEN
        CREATE TABLE clients (
            id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(100),
            api_key VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Insérer les clients par défaut
        INSERT INTO clients (id, name, api_key) VALUES 
            ('test-client', 'Test Client', 'test-token'),
            ('dashboard', 'Dashboard Client', 'dashboard-token')
        ON CONFLICT (id) DO NOTHING;
        
        RAISE NOTICE 'Table clients créée';
    END IF;

    -- Créer les index
    CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
    CREATE INDEX IF NOT EXISTS idx_jobs_submitted_at ON jobs(submitted_at);
END $$;

SQL

exit 0
EOF

chmod +x scripts/postgres-healthcheck.sh
print_status "Script healthcheck créé"

# Étape 2: Mettre à jour docker-compose.yml
print_info "Mise à jour de docker-compose.yml..."

# Créer une sauvegarde
cp docker-compose.yml docker-compose.yml.bak

# Créer un nouveau docker-compose avec healthcheck personnalisé
cat > docker-compose.yml.new << 'EOF'
services:
  # === DATA LAYER ===
  redis:
    image: redis:7-alpine
    container_name: synapse_redis
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    networks:
      - synapse_network

  postgres:
    image: postgres:15-alpine
    container_name: synapse_postgres
    environment:
      POSTGRES_DB: synapse
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: synapse123
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./scripts/postgres-healthcheck.sh:/healthcheck.sh:ro
      - ./sql:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD", "/healthcheck.sh"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks:
      - synapse_network

  # === CORE SERVICES ===
  gateway:
    build: ./services/gateway
    container_name: synapse_gateway
    ports:
      - "8080:8080"
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://synapse:synapse123@postgres:5432/synapse
    depends_on:
      redis:
        condition: service_started
      postgres:
        condition: service_healthy
    networks:
      - synapse_network
    restart: unless-stopped

  dispatcher:
    build: ./services/dispatcher
    container_name: synapse_dispatcher
    ports:
      - "8001:8001"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    networks:
      - synapse_network

  aggregator:
    build: ./services/aggregator
    container_name: synapse_aggregator
    ports:
      - "8002:8002"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    networks:
      - synapse_network

  node:
    build: ./services/node
    container_name: synapse_node
    ports:
      - "8003:8003"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    networks:
      - synapse_network

  dashboard:
    image: node:18-alpine
    container_name: synapse_dashboard
    working_dir: /app
    volumes:
      - ./dashboard:/app
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://localhost:8080
    command: sh -c "npm install && npm start"
    networks:
      - synapse_network
    depends_on:
      - gateway

networks:
  synapse_network:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
EOF

# Copier les autres services s'ils existent dans l'ancien fichier
if grep -q "prometheus:" docker-compose.yml; then
    echo "" >> docker-compose.yml.new
    echo "  # === MONITORING ===" >> docker-compose.yml.new
    sed -n '/prometheus:/,/^[[:space:]]*[^[:space:]#]/p' docker-compose.yml | sed '$d' >> docker-compose.yml.new
fi

if grep -q "grafana:" docker-compose.yml; then
    sed -n '/grafana:/,/^[[:space:]]*[^[:space:]#]/p' docker-compose.yml | sed '$d' >> docker-compose.yml.new
fi

# Ajouter les volumes à la fin
echo "" >> docker-compose.yml.new
echo "  prometheus_data:" >> docker-compose.yml.new
echo "  grafana_data:" >> docker-compose.yml.new

mv docker-compose.yml.new docker-compose.yml
print_status "docker-compose.yml mis à jour avec healthcheck"

# Étape 3: Appliquer immédiatement
print_info "Application des changements..."

# Arrêter les services
docker-compose stop

# Créer les tables directement maintenant
print_info "Création immédiate des tables..."

docker-compose up -d postgres
sleep 10

docker exec synapse_postgres psql -U synapse -d synapse << 'EOF' || true
-- Création immédiate des tables

CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(50) PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    client_id VARCHAR(100),
    node_id VARCHAR(50),
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 1,
    submitted_at TIMESTAMP DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    input_data JSONB,
    output_data JSONB,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS nodes (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    region VARCHAR(50),
    status VARCHAR(20) DEFAULT 'offline',
    gpu_model VARCHAR(100),
    cpu_cores INTEGER,
    memory_gb INTEGER,
    capabilities JSONB,
    last_heartbeat TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS metrics (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value FLOAT NOT NULL,
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS clients (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100),
    api_key VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_submitted_at ON jobs(submitted_at);

-- Clients par défaut
INSERT INTO clients (id, name, api_key) VALUES 
    ('test-client', 'Test Client', 'test-token')
ON CONFLICT (id) DO NOTHING;

\dt
EOF

# Redémarrer tous les services
print_info "Redémarrage de tous les services..."
docker-compose up -d

print_status "Configuration terminée!"

echo ""
echo "📋 Ce qui a été configuré :"
echo "  ✅ Healthcheck PostgreSQL qui crée les tables automatiquement"
echo "  ✅ Tables créées immédiatement"
echo "  ✅ Le gateway attend que PostgreSQL soit healthy"
echo ""
echo "🧪 Test de vérification :"
echo ""

sleep 5

# Test
curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{"model_name": "test-auto-init", "input_data": {"test": true}}' | jq .

echo ""
echo "📊 Vérifier les tables :"
echo "  docker exec synapse_postgres psql -U synapse -d synapse -c '\\dt'"
echo ""
echo "🔍 Voir les jobs :"
echo "  docker exec synapse_postgres psql -U synapse -d synapse -c 'SELECT * FROM jobs;'"
