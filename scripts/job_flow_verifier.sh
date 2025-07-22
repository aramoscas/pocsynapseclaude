#!/bin/bash

# SynapseGrid Job Flow Verification Tool
# Usage: ./job_flow_verifier.sh [job_id] [options]

set -e

# Configuration
GATEWAY_URL="http://localhost:8080"
REDIS_HOST="localhost"
REDIS_PORT="6379"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
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
        error "redis-cli not found. Please install redis-tools: sudo apt-get install redis-tools"
    fi
    
    # Check if psql is available
    if ! command -v psql &> /dev/null; then
        error "psql not found. Please install postgresql-client: sudo apt-get install postgresql-client"
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error "curl not found. Please install curl: sudo apt-get install curl"
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        error "jq not found. Please install jq: sudo apt-get install jq"
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
    
    # Job flow tracking
    local stages=(
        "gateway_received"
        "redis_queued"
        "dispatcher_picked"
        "node_assigned"
        "node_processing"
        "result_aggregated"
        "job_completed"
    )
    
    local completed_stages=()
    
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
        
        # 5. Check PostgreSQL for persistent job data
        echo -e "\n${PURPLE}5. PostgreSQL Status:${NC}"
        local db_job_status=$(PGPASSWORD=$POSTGRES_PASS psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT status FROM jobs WHERE job_id='$job_id';" 2>/dev/null | xargs || echo "")
        
        if [[ -n "$db_job_status" ]]; then
            echo "   Job status in DB: $db_job_status"
        else
            echo "   No job record in PostgreSQL yet"
        fi
        
        # 6. Service Health Check
        echo -e "\n${PURPLE}6. Service Health:${NC}"
        
        # Gateway health
        local gateway_health=$(curl -s "$GATEWAY_URL/health" 2>/dev/null | jq -r '.status // "unknown"' 2>/dev/null || echo "unreachable")
        echo "   Gateway: $gateway_health"
        
        # Redis health
        local redis_health=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT ping 2>/dev/null || echo "unreachable")
        echo "   Redis: $redis_health"
        
        # Check if job is completed
        if [[ "$result_exists" == "1" || "$db_job_status" == "completed" || "$gateway_job_status" == "completed" ]]; then
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
        if [[ "$gateway_job_status" == "failed" || "$db_job_status" == "failed" ]]; then
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
    
    # PostgreSQL
    local postgres_status=$(PGPASSWORD=$POSTGRES_PASS psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;" > /dev/null 2>&1 && echo "PONG" || echo "unreachable")
    echo "PostgreSQL: $postgres_status"
    
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
    echo "  --interval <seconds> - Set check interval (default: 2)"
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
