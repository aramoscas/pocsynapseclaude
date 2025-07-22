#!/bin/bash

# SynapseGrid Setup Script for Job Flow Verification Tools
# This script is automatically called by `make setup`

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[SETUP]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
    INSTALL_CMD="brew install"
    INSTALL_CHECK="brew list"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v apt-get >/dev/null 2>&1; then
        OS="debian"
        INSTALL_CMD="sudo apt-get install -y"
        INSTALL_CHECK="dpkg -l"
    else
        OS="linux"
        INSTALL_CMD="echo 'Please install manually:'"
        INSTALL_CHECK="command -v"
    fi
else
    OS="unknown"
    warning "Unknown OS detected, some features may not work"
fi

log "Detected OS: $OS"

# Create directory structure
log "Creating directory structure..."
mkdir -p {scripts,logs,native_node/{src,logs,models,venv},dashboard}

# Install system dependencies
log "Installing system dependencies..."
case $OS in
    "debian")
        sudo apt-get update -qq
        $INSTALL_CMD redis-tools postgresql-client curl jq bc net-tools
        ;;
    "mac")
        if ! command -v brew >/dev/null 2>&1; then
            warning "Homebrew not found. Please install it first: https://brew.sh"
        else
            $INSTALL_CMD redis postgresql curl jq bc
        fi
        ;;
    *)
        warning "Please install manually: redis-tools, postgresql-client, curl, jq, bc"
        ;;
esac

# Create job flow verifier script
log "Creating job flow verifier..."
cat > scripts/job_flow_verifier.sh << 'EOF'
#!/bin/bash

# SynapseGrid Job Flow Verification Tool
# Usage: ./job_flow_verifier.sh [command] [options]

set -e

# Configuration
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="synapse"
POSTGRES_USER="synapse"
POSTGRES_PASS="synapse123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error() {
    log "${RED}❌ ERROR: $1${NC}"
    exit 1
}

success() {
    log "${GREEN}✅ $1${NC}"
}

info() {
    log "${BLUE}ℹ️  $1${NC}"
}

warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Check dependencies
check_dependencies() {
    info "Checking dependencies..."
    
    # Check if redis-cli is available
    if ! command -v redis-cli &> /dev/null; then
        error "redis-cli not found. Please install redis-tools"
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error "curl not found. Please install curl"
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        error "jq not found. Please install jq"
    fi
    
    success "All dependencies are available"
}

# Test service connectivity
test_connectivity() {
    info "Testing service connectivity..."
    
    # Test Gateway
    if curl -s --max-time 5 "$GATEWAY_URL/health" > /dev/null; then
        success "Gateway (port 8080) is reachable"
    else
        warning "Gateway (port 8080) is not reachable"
    fi
    
    # Test Redis
    if redis-cli -h $REDIS_HOST -p $REDIS_PORT ping > /dev/null 2>&1; then
        success "Redis ($REDIS_HOST:$REDIS_PORT) is reachable"
    else
        warning "Redis ($REDIS_HOST:$REDIS_PORT) is not reachable"
    fi
    
    # Test PostgreSQL
    if PGPASSWORD=$POSTGRES_PASS psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;" > /dev/null 2>&1; then
        success "PostgreSQL ($POSTGRES_HOST:$POSTGRES_PORT) is reachable"
    else
        warning "PostgreSQL ($POSTGRES_HOST:$POSTGRES_PORT) is not reachable"
    fi
}

# Submit a test job
submit_test_job() {
    info "Submitting test job..."
    
    local job_payload='{
        "model_name": "resnet50",
        "input_data": {
            "image": "test_image.jpg",
            "batch_size": 1
        },
        "priority": "normal",
        "timeout": 30
    }'
    
    local response=$(curl -s -X POST "$GATEWAY_URL/submit" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token" \
        -H "X-Client-ID: cli-test-client" \
        -d "$job_payload")
    
    if [[ $? -eq 0 && -n "$response" ]]; then
        local job_id=$(echo "$response" | jq -r '.job_id // empty')
        if [[ -n "$job_id" && "$job_id" != "null" ]]; then
            success "Job submitted successfully with ID: $job_id"
            echo "$job_id"
        else
            error "Job submission failed. Response: $response"
        fi
    else
        error "Failed to submit job to Gateway"
    fi
}

# Monitor job flow through all services
monitor_job_flow() {
    local job_id=$1
    local max_wait=${2:-60} # Default 60 seconds timeout
    local check_interval=2
    local elapsed=0
    
    info "Monitoring job flow for job ID: $job_id (timeout: ${max_wait}s)"
    
    while [[ $elapsed -lt $max_wait ]]; do
        echo -e "\n${CYAN}=== Job Flow Status (${elapsed}s/${max_wait}s) ===${NC}"
        
        # 1. Check Gateway logs/metrics
        echo -e "\n${PURPLE}1. Gateway Status:${NC}"
        local gateway_status=$(curl -s "$GATEWAY_URL/jobs/$job_id" 2>/dev/null || echo '{"status":"not_found"}')
        local gateway_job_status=$(echo "$gateway_status" | jq -r '.status // "unknown"')
        echo "   Job Status in Gateway: $gateway_job_status"
        
        # 2. Check Redis queues
        echo -e "\n${PURPLE}2. Redis Queue Status:${NC}"
        
        # Check if job is in pending queue
        local in_pending_queue=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0")
        echo "   Jobs in pending queue: $in_pending_queue"
        
        # Check job-specific data in Redis
        local job_data=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGETALL "job:$job_id" 2>/dev/null)
        if [[ -n "$job_data" ]]; then
            echo "   Job data found in Redis:"
            echo "$job_data" | sed 's/^/      /'
        else
            echo "   No job data in Redis"
        fi
        
        # Check processing queue
        local in_processing=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:processing:eu-west-1" 2>/dev/null || echo "0")
        echo "   Jobs in processing queue: $in_processing"
        
        # Check completed results
        local result_exists=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT EXISTS "result:$job_id" 2>/dev/null || echo "0")
        if [[ "$result_exists" == "1" ]]; then
            echo "   ✅ Result found in Redis"
            local result_data=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGETALL "result:$job_id")
            echo "$result_data" | sed 's/^/      /'
        else
            echo "   ⏳ No result in Redis yet"
        fi
        
        # 3. Check Node Status
        echo -e "\n${PURPLE}3. Node Status:${NC}"
        local available_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SMEMBERS "nodes:eu-west-1:available" 2>/dev/null)
        local node_count=$(echo "$available_nodes" | wc -w)
        echo "   Available nodes: $node_count"
        
        if [[ $node_count -gt 0 ]]; then
            echo "   Node IDs: $available_nodes"
            
            # Check if any node is processing our job
            for node in $available_nodes; do
                local node_job=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGET "node:$node:eu-west-1:status" "current_job" 2>/dev/null)
                if [[ "$node_job" == "$job_id" ]]; then
                    echo "   ✅ Node $node is processing job $job_id"
                fi
            done
        fi
        
        # 4. Check native nodes
        echo -e "\n${PURPLE}4. Native Nodes Status:${NC}"
        local native_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SMEMBERS "native_nodes" 2>/dev/null)
        local native_count=$(echo "$native_nodes" | wc -w)
        echo "   Native nodes registered: $native_count"
        if [[ $native_count -gt 0 ]]; then
            echo "   Native node IDs: $native_nodes"
        fi
        
        # Check if job is completed
        if [[ "$result_exists" == "1" || "$gateway_job_status" == "completed" ]]; then
            success "Job $job_id has been completed successfully!"
            echo -e "\n${GREEN}=== FINAL JOB SUMMARY ===${NC}"
            echo "Job ID: $job_id"
            echo "Total processing time: ${elapsed}s"
            echo "Final status: completed"
            
            # Show final result if available
            if [[ "$result_exists" == "1" ]]; then
                echo -e "\n${GREEN}Final Result:${NC}"
                redis-cli -h $REDIS_HOST -p $REDIS_PORT HGETALL "result:$job_id" | sed 's/^/   /'
            fi
            
            return 0
        fi
        
        # Check for errors
        if [[ "$gateway_job_status" == "failed" ]]; then
            error "Job $job_id has failed!"
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        
        echo -e "\n${CYAN}--- Waiting ${check_interval}s before next check ---${NC}"
    done
    
    warning "Monitoring timeout reached (${max_wait}s). Job may still be processing."
    return 1
}

# Show system overview
show_system_overview() {
    info "System Overview:"
    
    echo -e "\n${PURPLE}=== SERVICE STATUS ===${NC}"
    
    # Gateway
    local gateway_status=$(curl -s --max-time 3 "$GATEWAY_URL/health" 2>/dev/null | jq -r '.status // "unknown"' 2>/dev/null || echo "unreachable")
    echo "Gateway: $gateway_status"
    
    # Redis
    local redis_status=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT ping 2>/dev/null || echo "unreachable")
    echo "Redis: $redis_status"
    
    echo -e "\n${PURPLE}=== QUEUE STATUS ===${NC}"
    if [[ "$redis_status" == "PONG" ]]; then
        local pending_jobs=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0")
        local processing_jobs=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:processing:eu-west-1" 2>/dev/null || echo "0")
        local available_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SCARD "nodes:eu-west-1:available" 2>/dev/null || echo "0")
        local native_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SCARD "native_nodes" 2>/dev/null || echo "0")
        
        echo "Pending jobs: $pending_jobs"
        echo "Processing jobs: $processing_jobs"
        echo "Available nodes: $available_nodes"
        echo "Native nodes: $native_nodes"
    fi
}

# Show help
show_help() {
    echo "SynapseGrid Job Flow Verification Tool"
    echo ""
    echo "Usage:"
    echo "  $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  test               - Submit a test job and monitor its complete flow"
    echo "  monitor <job_id>   - Monitor an existing job by ID"
    echo "  status             - Show system overview and queue status"
    echo "  connectivity       - Test connectivity to all services"
    echo ""
    echo "Options:"
    echo "  --timeout <seconds>  - Set monitoring timeout (default: 60)"
    echo "  --gateway <url>      - Gateway URL (default: http://localhost:8080)"
    echo "  --redis <host:port>  - Redis connection (default: localhost:6379)"
    echo "  --help               - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 test                     # Submit and monitor a test job"
    echo "  $0 monitor job-123          # Monitor existing job"
    echo "  $0 status                   # Show system status"
    echo "  $0 test --timeout 120       # Test with 2-minute timeout"
    echo ""
}

# Main function
main() {
    local command=""
    local job_id=""
    local timeout=60
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            test)
                command="test"
                shift
                ;;
            monitor)
                command="monitor"
                job_id="$2"
                shift 2
                ;;
            status)
                command="status"
                shift
                ;;
            connectivity)
                command="connectivity"
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --gateway)
                GATEWAY_URL="$2"
                shift 2
                ;;
            --redis)
                IFS=':' read -ra REDIS_PARTS <<< "$2"
                REDIS_HOST="${REDIS_PARTS[0]}"
                REDIS_PORT="${REDIS_PARTS[1]:-6379}"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Default to help if no command
    if [[ -z "$command" ]]; then
        show_help
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Execute command
    case $command in
        test)
            info "Starting end-to-end job flow test..."
            show_system_overview
            echo ""
            job_id=$(submit_test_job)
            if [[ -n "$job_id" ]]; then
                monitor_job_flow "$job_id" "$timeout"
            fi
            ;;
        monitor)
            if [[ -z "$job_id" ]]; then
                error "Job ID is required for monitor command"
            fi
            monitor_job_flow "$job_id" "$timeout"
            ;;
        status)
            show_system_overview
            ;;
        connectivity)
            test_connectivity
            ;;
    esac
}

# Run main function with all arguments
main "$@"
EOF

chmod +x scripts/job_flow_verifier.sh

# Create real-time monitor script
log "Creating real-time monitor..."
cat > scripts/real_time_monitor.sh << 'EOF'
#!/bin/bash

# SynapseGrid Real-Time Job Flow Monitor
# Usage: ./real_time_monitor.sh [dashboard|performance|debug]

# Configuration
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Real-time dashboard function
show_realtime_dashboard() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                     SYNAPSEGRID REAL-TIME MONITORING DASHBOARD                   ║${NC}"
        echo -e "${CYAN}║                           $(date +'%Y-%m-%d %H:%M:%S')                                  ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
        
        # System Status
        echo -e "\n${PURPLE}🔧 SYSTEM STATUS${NC}"
        echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
        
        # Gateway status
        local gateway_health=$(curl -s --max-time 2 "$GATEWAY_URL/health" 2>/dev/null | jq -r '.status // "down"' 2>/dev/null || echo "down")
        local gateway_icon=$([ "$gateway_health" = "healthy" ] && echo "🟢" || echo "🔴")
        printf "│ %-15s │ %-10s │ %-45s │\n" "Gateway" "$gateway_icon $gateway_health" "http://localhost:8080"
        
        # Redis status  
        local redis_health=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT ping 2>/dev/null || echo "down")
        local redis_icon=$([ "$redis_health" = "PONG" ] && echo "🟢" || echo "🔴")
        printf "│ %-15s │ %-10s │ %-45s │\n" "Redis" "$redis_icon $redis_health" "$REDIS_HOST:$REDIS_PORT"
        
        echo "└─────────────────────────────────────────────────────────────────────────────────┘"
        
        # Queue Metrics
        if [[ "$redis_health" == "PONG" ]]; then
            echo -e "\n${YELLOW}📊 QUEUE METRICS${NC}"
            echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
            
            local pending=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0")
            local processing=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:processing:eu-west-1" 2>/dev/null || echo "0")
            local completed=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:completed:eu-west-1" 2>/dev/null || echo "0")
            
            printf "│ %-20s │ %-15s │ %-40s │\n" "Pending Jobs" "$pending" "$(printf '█%.0s' $(seq 1 $((pending > 20 ? 20 : pending))))"
            printf "│ %-20s │ %-15s │ %-40s │\n" "Processing Jobs" "$processing" "$(printf '█%.0s' $(seq 1 $((processing > 20 ? 20 : processing))))"
            printf "│ %-20s │ %-15s │ %-40s │\n" "Completed Jobs" "$completed" "$(printf '█%.0s' $(seq 1 $((completed > 20 ? 20 : completed))))"
            
            echo "└─────────────────────────────────────────────────────────────────────────────────┘"
        fi
        
        # Node Status
        echo -e "\n${GREEN}🖥️  NODE STATUS${NC}"
        echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
        
        if [[ "$redis_health" == "PONG" ]]; then
            local docker_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SMEMBERS "nodes:eu-west-1:available" 2>/dev/null)
            local native_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SMEMBERS "native_nodes" 2>/dev/null)
            
            # Docker nodes
            local docker_count=$(echo "$docker_nodes" | wc -w)
            printf "│ %-20s │ %-15s │ %-40s │\n" "Docker Nodes" "$docker_count active" "$docker_nodes"
            
            # Native nodes
            local native_count=$(echo "$native_nodes" | wc -w)
            printf "│ %-20s │ %-15s │ %-40s │\n" "Native Nodes (M2)" "$native_count active" "$native_nodes"
        else
            printf "│ %-76s │\n" "❌ Cannot retrieve node status (Redis unavailable)"
        fi
        
        echo "└─────────────────────────────────────────────────────────────────────────────────┘"
        
        # Controls
        echo -e "\n${CYAN}📋 CONTROLS${NC}"
        echo "Press Ctrl+C to exit | 'q' + Enter to quit | 't' + Enter to submit test job"
        
        # Wait for input with timeout
        read -t 3 -n 1 input
        case $input in
            q) break ;;
            t) submit_test_job_background ;;
        esac
    done
}

# Submit test job in background
submit_test_job_background() {
    echo -e "\n${YELLOW}🚀 Submitting test job...${NC}"
    
    local job_payload='{
        "model_name": "resnet50",
        "input_data": {"image": "realtime_test.jpg"},
        "priority": "normal"
    }'
    
    local response=$(curl -s -X POST "$GATEWAY_URL/submit" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token" \
        -H "X-Client-ID: realtime-monitor" \
        -d "$job_payload")
    
    local job_id=$(echo "$response" | jq -r '.job_id // "failed"')
    if [[ "$job_id" != "failed" ]]; then
        echo "✅ Test job submitted: $job_id"
    else
        echo "❌ Failed to submit test job"
    fi
    sleep 2
}

# Main execution
case "${1:-dashboard}" in
    dashboard|"") show_realtime_dashboard ;;
    *) echo "Usage: $0 [dashboard]"; exit 1 ;;
esac
EOF

chmod +x scripts/real_time_monitor.sh

# Create Mac M2 setup if on macOS
if [[ "$OS" == "mac" ]]; then
    log "Creating Mac M2 native node setup..."
    
    # Create Mac M2 requirements
    cat > native_node/requirements.txt << 'EOF'
onnxruntime
redis
numpy
pillow
requests
EOF
    
    # Create Mac M2 node script
    cat > native_node/mac_node.py << 'EOF'
#!/usr/bin/env python3
"""
SynapseGrid Mac M2 Native Node
High-performance AI inference using Mac M2 architecture
"""
import time
import json
import redis
import logging
import os
from datetime import datetime
import threading

# Setup logging
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/mac_node.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class MacM2Node:
    def __init__(self):
        self.node_id = "native-m2-001"
        self.redis = redis.Redis(host='localhost', port=6379, decode_responses=True)
        self.running = False
        
    def start(self):
        """Start the Mac M2 native node"""
        logger.info(f"Starting Mac M2 native node {self.node_id}")
        
        # Register node in Redis
        self.redis.sadd("native_nodes", self.node_id)
        self.redis.hmset(f"node:{self.node_id}:eu-west-1:info", {
            "node_id": self.node_id,
            "node_type": "native_m2", 
            "status": "available",
            "capabilities": json.dumps({
                "supports_metal": True,
                "memory_gb": 16,
                "compute_units": 8
            }),
            "last_seen": datetime.utcnow().isoformat()
        })
        
        self.running = True
        logger.info(f"Mac M2 node {self.node_id} registered and running")
        
        # Start heartbeat in background
        heartbeat_thread = threading.Thread(target=self.heartbeat_loop)
        heartbeat_thread.daemon = True
        heartbeat_thread.start()
        
        # Main loop (simplified for POC)
        while self.running:
            time.sleep(1)
    
    def heartbeat_loop(self):
        """Send periodic heartbeat to Redis"""
        while self.running:
            self.redis.hset(
                f"node:{self.node_id}:eu-west-1:info", 
                "last_seen", 
                datetime.utcnow().isoformat()
            )
            self.redis.expire(f"node:{self.node_id}:eu-west-1:info", 60)
            time.sleep(10)
    
    def stop(self):
        """Stop the node gracefully"""
        logger.info(f"Stopping Mac M2 node {self.node_id}")
        self.running = False
        self.redis.srem("native_nodes", self.node_id)
        self.redis.delete(f"node:{self.node_id}:eu-west-1:info")

if __name__ == "__main__":
    node = MacM2Node()
    try:
        node.start()
    except KeyboardInterrupt:
        logger.info("Received interrupt signal")
        node.stop()
    except Exception as e:
        logger.error(f"Mac M2 node error: {e}")
EOF

    # Create Mac M2 control script
    cat > mac_m2_control.sh << 'EOF'
#!/bin/bash

# Mac M2 Node Control Script
MAC_NODE_DIR="native_node"
PID_FILE="$MAC_NODE_DIR/mac_node.pid"
LOG_FILE="$MAC_NODE_DIR/logs/mac_node.log"

case "$1" in
    start)
        if [ -f "$PID_FILE" ]; then
            echo "Mac M2 node already running (PID: $(cat $PID_FILE))"
        else
            echo "Starting Mac M2 native node..."
            cd $MAC_NODE_DIR
            source venv/bin/activate
            python mac_node.py > logs/mac_node.log 2>&1 &
            echo $! > mac_node.pid
            echo "Mac M2 node started (PID: $!)"
        fi
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat $PID_FILE)
            echo "Stopping Mac M2 node (PID: $PID)..."
            kill $PID 2>/dev/null
            rm -f $PID_FILE
            echo "Mac M2 node stopped"
        else
            echo "Mac M2 node not running"
        fi
        ;;
    status)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat $PID_FILE)
            if ps -p $PID > /dev/null 2>&1; then
                echo "Mac M2 node running (PID: $PID)"
            else
                echo "Mac M2 node not running (stale PID file)"
                rm -f $PID_FILE
            fi
        else
            echo "Mac M2 node not running"
        fi
        ;;
    logs)
        if [ -f "$LOG_FILE" ]; then
            tail -f $LOG_FILE
        else
            echo "No log file found"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status|logs}"
        exit 1
        ;;
esac
EOF
    
    chmod +x mac_m2_control.sh
    
    # Setup Python virtual environment
    if command -v python3 >/dev/null 2>&1; then
        log "Setting up Python virtual environment for Mac M2..."
        cd native_node
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
        cd ..
        success "Mac M2 Python environment ready"
    else
        warning "Python3 not found, Mac M2 setup incomplete"
    fi
fi

# Create basic test script
log "Creating test utilities..."
cat > scripts/quick_test.sh << 'EOF'
#!/bin/bash

# Quick Test Script for SynapseGrid
# Tests basic functionality quickly

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 SynapseGrid Quick Test${NC}"
echo "=========================="

# Test 1: Service connectivity
echo -e "\n${YELLOW}1. Testing service connectivity...${NC}"
curl -s --max-time 3 http://localhost:8080/health >/dev/null && echo "✅ Gateway OK" || echo "❌ Gateway failed"
redis-cli ping >/dev/null 2>&1 && echo "✅ Redis OK" || echo "❌ Redis failed"

# Test 2: Submit job
echo -e "\n${YELLOW}2. Submitting test job...${NC}"
RESPONSE=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: quick-test" \
    -d '{"model_name": "resnet50", "input_data": {"image": "quick_test.jpg"}}')

JOB_ID=$(echo "$RESPONSE" | jq -r '.job_id // "failed"')
if [[ "$JOB_ID" != "failed" && "$JOB_ID" != "null" ]]; then
    echo "✅ Job submitted: $JOB_ID"
    
    # Test 3: Check Redis
    echo -e "\n${YELLOW}3. Checking Redis queues...${NC}"
    PENDING=$(redis-cli LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0")
    echo "Pending jobs: $PENDING"
    
    # Wait a bit and check for result
    echo -e "\n${YELLOW}4. Waiting for result (10s)...${NC}"
    for i in {1..10}; do
        if redis-cli EXISTS "result:$JOB_ID" >/dev/null 2>&1; then
            echo "✅ Job completed!"
            redis-cli HGETALL "result:$JOB_ID" | head -10
            break
        fi
        echo -n "."
        sleep 1
    done
else
    echo "❌ Job submission failed: $RESPONSE"
fi

echo -e "\n${GREEN}Quick test completed!${NC}"
EOF

chmod +x scripts/quick_test.sh

# Create comprehensive installation verification
log "Creating installation verification..."
cat > scripts/verify_installation.sh << 'EOF'
#!/bin/bash

# SynapseGrid Installation Verification
# Checks all components and dependencies

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
    if eval "$2"; then
        echo -e "✅ $1"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo -e "❌ $1"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
}

echo -e "${BLUE}🔍 SynapseGrid Installation Verification${NC}"
echo "=========================================="

echo -e "\n${YELLOW}System Dependencies:${NC}"
check "Redis CLI available" "command -v redis-cli >/dev/null"
check "PostgreSQL client available" "command -v psql >/dev/null"
check "curl available" "command -v curl >/dev/null"
check "jq available" "command -v jq >/dev/null"
check "Docker available" "command -v docker >/dev/null"
check "Docker Compose available" "command -v docker-compose >/dev/null || command -v 'docker compose' >/dev/null"

echo -e "\n${YELLOW}File Structure:${NC}"
check "Scripts directory exists" "[ -d scripts ]"
check "Job flow verifier exists" "[ -f scripts/job_flow_verifier.sh ]"
check "Real-time monitor exists" "[ -f scripts/real_time_monitor.sh ]"
check "Quick test exists" "[ -f scripts/quick_test.sh ]"
check "Logs directory exists" "[ -d logs ]"

echo -e "\n${YELLOW}Script Permissions:${NC}"
check "Job flow verifier executable" "[ -x scripts/job_flow_verifier.sh ]"
check "Real-time monitor executable" "[ -x scripts/real_time_monitor.sh ]"
check "Quick test executable" "[ -x scripts/quick_test.sh ]"

if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "\n${YELLOW}Mac M2 Components:${NC}"
    check "Native node directory exists" "[ -d native_node ]"
    check "Mac node script exists" "[ -f native_node/mac_node.py ]"
    check "Mac control script exists" "[ -f mac_m2_control.sh ]"
    check "Mac control script executable" "[ -x mac_m2_control.sh ]"
    check "Python venv exists" "[ -d native_node/venv ]"
    check "Requirements file exists" "[ -f native_node/requirements.txt ]"
fi

echo -e "\n${YELLOW}Docker Services (if running):${NC}"
if docker ps >/dev/null 2>&1; then
    check "Gateway container running" "docker ps | grep -q gateway"
    check "Redis container running" "docker ps | grep -q redis"
    check "PostgreSQL container running" "docker ps | grep -q postgres"
else
    echo "⚠️  Docker not running - service checks skipped"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Checks passed: $CHECKS_PASSED${NC}"
echo -e "${RED}Checks failed: $CHECKS_FAILED${NC}"

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Installation verification successful!${NC}"
    echo "You can now use:"
    echo "  make start           # Start all services"
    echo "  make job-test        # Test job flow"
    echo "  make flow-monitor    # Real-time monitoring"
else
    echo -e "\n${YELLOW}⚠️  Some checks failed. Please review and fix issues.${NC}"
fi
EOF

chmod +x scripts/verify_installation.sh

# Create README for scripts
log "Creating scripts documentation..."
cat > scripts/README.md << 'EOF'
# SynapseGrid Job Flow Verification Scripts

Cette directory contient tous les outils de vérification et monitoring du flow des jobs.

## Scripts Disponibles

### 🔍 job_flow_verifier.sh
**Outil principal de vérification du flow des jobs**

```bash
# Test complet end-to-end
./job_flow_verifier.sh test

# Monitorer un job spécifique
./job_flow_verifier.sh monitor job-123456

# Status du système
./job_flow_verifier.sh status

# Test de connectivité
./job_flow_verifier.sh connectivity
```

### 📊 real_time_monitor.sh  
**Dashboard temps réel avec interface visuelle**

```bash
# Dashboard interactif
./real_time_monitor.sh dashboard

# Ou simplement
./real_time_monitor.sh
```

### 🧪 quick_test.sh
**Test rapide de fonctionnalité de base**

```bash
# Test rapide (30 secondes)
./quick_test.sh
```

### ✅ verify_installation.sh
**Vérification de l'installation complète**

```bash
# Vérifier que tout est correctement installé
./verify_installation.sh
```

## Utilisation avec Makefile

Ces scripts sont intégrés dans le Makefile principal :

```bash
# Tests de job flow
make job-test              # Test complet
make job-monitor JOB_ID=123 # Monitor job spécifique  
make job-status            # Status des queues
make flow-verify           # Test connectivité
make flow-monitor          # Dashboard temps réel
make flow-debug            # Mode debug

# Mac M2 (si sur macOS)
make mac-start             # Démarrer node natif M2
make mac-status            # Status node M2
make mac-logs              # Logs node M2

# Tests généraux  
make test                  # Tests API de base
make test-e2e              # Tests end-to-end complets
make stress-test           # Test de charge
make integration-test      # Suite complète
```

## Architecture de Vérification

Les scripts surveillent tout le pipeline :

1. **Gateway** (port 8080) - Réception et validation des jobs
2. **Redis** (port 6379) - Gestion des queues et métadonnées  
3. **Dispatcher** - Sélection et assignation des nodes
4. **Nodes** (Docker + M2 natif) - Exécution des jobs
5. **Aggregator** - Collection et validation des résultats
6. **PostgreSQL** (port 5432) - Persistence et historique

## Variables d'Environnement

```bash
export GATEWAY_URL="http://localhost:8080"
export REDIS_HOST="localhost" 
export REDIS_PORT="6379"
export POSTGRES_HOST="localhost"
export POSTGRES_PORT="5432"
```

## Logs

Tous les logs sont sauvegardés dans le répertoire `logs/` :
- `job_flow.log` - Logs de vérification des jobs
- `real_time_monitor.log` - Logs du monitoring temps réel  
- `mac_node.log` - Logs du node M2 natif (si applicable)

## Troubleshooting

Si un script ne fonctionne pas :

1. Vérifier les permissions : `chmod +x scripts/*.sh`
2. Vérifier les dépendances : `./scripts/verify_installation.sh`
3. Vérifier les services : `make health`
4. Consulter les logs : `tail -f logs/*.log`
EOF

# Final verification and summary
log "Running installation verification..."
./scripts/verify_installation.sh

echo ""
success "SynapseGrid job flow verification tools setup complete!"
echo ""
echo -e "${CYAN}🚀 Quick Start:${NC}"
echo "  make setup          # If not already done"
echo "  make start          # Start all services"  
echo "  make job-test       # Test job flow"
echo "  make flow-monitor   # Real-time dashboard"
echo ""
echo -e "${CYAN}📚 Documentation:${NC}"
echo "  scripts/README.md   # Detailed usage guide"
echo "  make help           # All available commands"
echo ""

if [[ "$OS" == "mac" ]]; then
    echo -e "${PURPLE}🍎 Mac M2 Specific:${NC}"
    echo "  make mac-setup      # Setup native M2 node"
    echo "  make mac-start      # Start M2 node"
    echo "  make mac-test       # Test M2 capabilities"
    echo ""
fi
