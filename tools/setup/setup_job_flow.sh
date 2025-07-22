#!/bin/bash

# Setup Job Flow Verification Tools
# Usage: ./tools/setup/setup_job_flow.sh [--full]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[SETUP]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🚀 SynapseGrid Job Flow Setup"
echo "============================="

# Check if we're in the project root
if [ ! -f "docker-compose.yml" ] && [ ! -f "Makefile" ]; then
    error "Please run this script from the project root directory"
    exit 1
fi

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y redis-tools postgresql-client curl jq bc
    elif command -v brew >/dev/null 2>&1; then
        brew install redis postgresql curl jq bc
    else
        warning "Please install manually: redis-tools, postgresql-client, curl, jq, bc"
    fi
}

# Create job flow verifier
create_job_flow_verifier() {
    log "Creating job flow verifier..."
    cat > scripts/flow/job_flow_verifier.sh << 'SCRIPT_EOF'
#!/bin/bash
# Main Job Flow Verifier
source "$(dirname "$0")/../utils/common.sh"

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

case "$1" in
    test)
        log "Running end-to-end job flow test..."
        source "$(dirname "$0")/test_job_submission.sh"
        ;;
    monitor)
        log "Monitoring job $2..."
        source "$(dirname "$0")/monitor_job.sh" "$2"
        ;;
    status)
        log "Checking system status..."
        source "$(dirname "$0")/check_status.sh"
        ;;
    *)
        echo "Usage: $0 {test|monitor <job_id>|status}"
        exit 1
        ;;
esac
SCRIPT_EOF
    chmod +x scripts/flow/job_flow_verifier.sh
    success "Job flow verifier created"
}

# Create common utilities
create_common_utils() {
    log "Creating common utilities..."
    cat > scripts/utils/common.sh << 'COMMON_EOF'
#!/bin/bash
# Common utilities for all scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅${NC} $1"; }
warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
error() { echo -e "${RED}❌${NC} $1"; }
info() { echo -e "${CYAN}ℹ️${NC} $1"; }

# Configuration
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check service health
check_service() {
    local service=$1
    local url=$2
    
    if curl -s --max-time 3 "$url" >/dev/null 2>&1; then
        success "$service is healthy"
        return 0
    else
        warning "$service is not responding"
        return 1
    fi
}

# Redis operations
redis_cmd() {
    if command_exists redis-cli; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
    else
        warning "redis-cli not available"
        return 1
    fi
}

# Generate job ID
generate_job_id() {
    echo "job_$(date +%s)_$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)"
}
COMMON_EOF
    success "Common utilities created"
}

# Create individual flow scripts
create_flow_scripts() {
    log "Creating individual flow scripts..."
    
    # Test job submission
    cat > scripts/flow/test_job_submission.sh << 'TEST_EOF'
#!/bin/bash
# Test job submission and flow
source "$(dirname "$0")/../utils/common.sh"

submit_and_monitor_job() {
    info "Submitting test job..."
    
    local response=$(curl -s -X POST "$GATEWAY_URL/submit" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token" \
        -H "X-Client-ID: flow-test" \
        -d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}}')
    
    local job_id=$(echo "$response" | jq -r '.job_id // "failed"' 2>/dev/null || echo "failed")
    
    if [ "$job_id" != "failed" ] && [ -n "$job_id" ]; then
        success "Job submitted: $job_id"
        monitor_job_completion "$job_id"
    else
        error "Job submission failed: $response"
        return 1
    fi
}

monitor_job_completion() {
    local job_id=$1
    local max_wait=60
    local elapsed=0
    
    info "Monitoring job $job_id (timeout: ${max_wait}s)"
    
    while [ $elapsed -lt $max_wait ]; do
        echo -n "."
        
        # Check for result in Redis
        if redis_cmd EXISTS "result:$job_id" | grep -q "1"; then
            echo ""
            success "Job $job_id completed!"
            redis_cmd HGETALL "result:$job_id" | head -10
            return 0
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    echo ""
    warning "Job monitoring timeout after ${max_wait}s"
    return 1
}

# Run the test
submit_and_monitor_job
TEST_EOF
    chmod +x scripts/flow/test_job_submission.sh
    
    # Monitor specific job
    cat > scripts/flow/monitor_job.sh << 'MONITOR_EOF'
#!/bin/bash
# Monitor specific job by ID
source "$(dirname "$0")/../utils/common.sh"

if [ -z "$1" ]; then
    error "Usage: $0 <job_id>"
    exit 1
fi

JOB_ID=$1
info "Monitoring job: $JOB_ID"

echo "Job Data:"
redis_cmd HGETALL "job:$JOB_ID" || warning "No job data found"

echo ""
echo "Result Data:"
redis_cmd HGETALL "result:$JOB_ID" || warning "No result found"

echo ""
echo "Queue Status:"
echo "  Pending: $(redis_cmd LLEN "jobs:queue:eu-west-1" || echo "N/A")"
echo "  Processing: $(redis_cmd LLEN "jobs:processing:eu-west-1" || echo "N/A")"
MONITOR_EOF
    chmod +x scripts/flow/monitor_job.sh
    
    # Check system status
    cat > scripts/flow/check_status.sh << 'STATUS_EOF'
#!/bin/bash
# Check system status
source "$(dirname "$0")/../utils/common.sh"

echo "System Status Check"
echo "==================="

# Gateway
echo "Gateway:"
check_service "Gateway" "$GATEWAY_URL/health"

# Redis
echo "Redis:"
if redis_cmd ping >/dev/null; then
    success "Redis is responding"
else
    warning "Redis is not responding"
fi

# Queue status
echo ""
echo "Queue Status:"
echo "  Pending jobs: $(redis_cmd LLEN "jobs:queue:eu-west-1" || echo "N/A")"
echo "  Processing jobs: $(redis_cmd LLEN "jobs:processing:eu-west-1" || echo "N/A")"
echo "  Available nodes: $(redis_cmd SCARD "nodes:eu-west-1:available" || echo "N/A")"
echo "  Native nodes: $(redis_cmd SCARD "native_nodes" || echo "N/A")"
STATUS_EOF
    chmod +x scripts/flow/check_status.sh
    
    success "Flow scripts created"
}

# Create monitoring scripts
create_monitoring_scripts() {
    log "Creating monitoring scripts..."
    
    cat > scripts/monitoring/real_time_monitor.sh << 'MONITOR_EOF'
#!/bin/bash
# Real-time monitoring dashboard
source "$(dirname "$0")/../utils/common.sh"

show_dashboard() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           SYNAPSEGRID REAL-TIME DASHBOARD                    ║${NC}"
        echo -e "${CYAN}║                   $(date +'%Y-%m-%d %H:%M:%S')                      ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        
        echo ""
        echo -e "${PURPLE}🔧 SYSTEM STATUS${NC}"
        check_service "Gateway" "$GATEWAY_URL/health" >/dev/null && echo "Gateway: 🟢" || echo "Gateway: 🔴"
        redis_cmd ping >/dev/null && echo "Redis: 🟢" || echo "Redis: 🔴"
        
        echo ""
        echo -e "${YELLOW}📊 QUEUE METRICS${NC}"
        echo "Pending: $(redis_cmd LLEN "jobs:queue:eu-west-1" || echo "0")"
        echo "Processing: $(redis_cmd LLEN "jobs:processing:eu-west-1" || echo "0")"
        echo "Nodes: $(redis_cmd SCARD "nodes:eu-west-1:available" || echo "0")"
        
        echo ""
        echo "Commands: 't'=test job, 'q'=quit"
        
        read -t 5 -n 1 input
        case $input in
            t)
                echo ""
                info "Submitting test job..."
                curl -s -X POST "$GATEWAY_URL/submit" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer test-token" \
                    -H "X-Client-ID: monitor-test" \
                    -d '{"model_name": "test"}' | jq '.job_id' 2>/dev/null || echo "submitted"
                sleep 2
                ;;
            q) break ;;
        esac
    done
}

show_dashboard
MONITOR_EOF
    chmod +x scripts/monitoring/real_time_monitor.sh
    
    success "Monitoring scripts created"
}

# Create debug tools
create_debug_tools() {
    log "Creating debug tools..."
    
    cat > tools/debug/debug_system.sh << 'DEBUG_EOF'
#!/bin/bash
# System debugging tool
source "$(dirname "$0")/../../scripts/utils/common.sh"

echo "SynapseGrid Debug Information"
echo "============================="

echo "Environment:"
echo "  OS: $(uname -s)"
echo "  Architecture: $(uname -m)"
echo "  Docker: $(docker --version 2>/dev/null || echo "Not available")"
echo "  Docker Compose: $(docker-compose --version 2>/dev/null || echo "Not available")"

echo ""
echo "Services:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep synapse || echo "No synapse containers running"

echo ""
echo "Network:"
check_service "Gateway" "$GATEWAY_URL/health"
redis_cmd ping >/dev/null && success "Redis accessible" || warning "Redis not accessible"

echo ""
echo "Redis Debug:"
if command_exists redis-cli; then
    echo "  Database size: $(redis_cmd DBSIZE || echo "N/A")"
    echo "  Memory usage: $(redis_cmd INFO memory | grep used_memory_human | cut -d: -f2 || echo "N/A")"
    echo "  Connected clients: $(redis_cmd INFO clients | grep connected_clients | cut -d: -f2 || echo "N/A")"
fi
DEBUG_EOF
    chmod +x tools/debug/debug_system.sh
    
    success "Debug tools created"
}

# Create maintenance tools
create_maintenance_tools() {
    log "Creating maintenance tools..."
    
    cat > tools/maintenance/cleanup.sh << 'CLEANUP_EOF'
#!/bin/bash
# Cleanup tool
source "$(dirname "$0")/../../scripts/utils/common.sh"

cleanup_redis() {
    log "Cleaning Redis queues..."
    redis_cmd DEL "jobs:queue:eu-west-1" >/dev/null || true
    redis_cmd DEL "jobs:processing:eu-west-1" >/dev/null || true
    success "Redis queues cleaned"
}

cleanup_logs() {
    log "Cleaning log files..."
    rm -f logs/*.log 2>/dev/null || true
    success "Log files cleaned"
}

cleanup_exports() {
    log "Cleaning old exports..."
    find exports/ -name "*.csv" -mtime +7 -delete 2>/dev/null || true
    find exports/ -name "logs_*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    success "Old exports cleaned"
}

case "$1" in
    redis) cleanup_redis ;;
    logs) cleanup_logs ;;
    exports) cleanup_exports ;;
    all) cleanup_redis; cleanup_logs; cleanup_exports ;;
    *) 
        echo "Usage: $0 {redis|logs|exports|all}"
        exit 1
        ;;
esac
CLEANUP_EOF
    chmod +x tools/maintenance/cleanup.sh
    
    success "Maintenance tools created"
}

# Create configuration files
create_configs() {
    log "Creating configuration files..."
    
    cat > configs/development/config.env << 'CONFIG_EOF'
# Development Configuration
GATEWAY_URL=http://localhost:8080
REDIS_HOST=localhost
REDIS_PORT=6379
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
LOG_LEVEL=DEBUG
ENVIRONMENT=development
CONFIG_EOF

    cat > configs/production/config.env << 'CONFIG_EOF'
# Production Configuration
GATEWAY_URL=https://api.synapsegrid.com
REDIS_HOST=redis-cluster
REDIS_PORT=6379
POSTGRES_HOST=postgres-primary
POSTGRES_PORT=5432
LOG_LEVEL=INFO
ENVIRONMENT=production
CONFIG_EOF
    
    success "Configuration files created"
}

# Create documentation
create_documentation() {
    log "Creating documentation..."
    
    cat > docs/job_flow_tools.md << 'DOC_EOF'
# SynapseGrid Job Flow Verification Tools

## Structure

```
scripts/
├── flow/              # Job flow verification
│   ├── job_flow_verifier.sh     # Main verifier
│   ├── test_job_submission.sh   # Test submission
│   ├── monitor_job.sh           # Monitor specific job
│   └── check_status.sh          # System status
├── utils/             # Common utilities
│   └── common.sh                # Shared functions
├── tests/             # Test scripts
└── monitoring/        # Monitoring tools
    └── real_time_monitor.sh     # Live dashboard

tools/
├── setup/             # Installation tools
│   └── setup_job_flow.sh       # Main setup
├── debug/             # Debug tools
│   └── debug_system.sh         # System debug
└── maintenance/       # Maintenance tools
    └── cleanup.sh               # Cleanup tool
```

## Usage

### Setup
```bash
./tools/setup/setup_job_flow.sh
```

### Job Flow Testing
```bash
# Complete flow test
./scripts/flow/job_flow_verifier.sh test

# Monitor specific job
./scripts/flow/job_flow_verifier.sh monitor job-123

# Check system status
./scripts/flow/job_flow_verifier.sh status
```

### Monitoring
```bash
# Real-time dashboard
./scripts/monitoring/real_time_monitor.sh
```

### Debug
```bash
# System debug info
./tools/debug/debug_system.sh
```

### Maintenance
```bash
# Cleanup
./tools/maintenance/cleanup.sh all
```
DOC_EOF
    
    success "Documentation created"
}

# Main setup function
main() {
    if [ "$1" = "--full" ]; then
        install_dependencies
    fi
    
    create_common_utils
    create_job_flow_verifier
    create_flow_scripts
    create_monitoring_scripts
    create_debug_tools
    create_maintenance_tools
    create_configs
    create_documentation
    
    success "Job Flow Verification Tools setup complete!"
    echo ""
    echo "🎯 Quick Start:"
    echo "  ./scripts/flow/job_flow_verifier.sh test"
    echo "  ./scripts/monitoring/real_time_monitor.sh"
    echo ""
    echo "📚 Documentation:"
    echo "  cat docs/job_flow_tools.md"
}

main "$@"
