#!/bin/bash

# SynapseGrid Real-Time Job Flow Monitor
# Usage: ./real_time_monitor.sh

# Configuration
GATEWAY_URL="http://localhost:8080"
REDIS_HOST="localhost"
REDIS_PORT="6379"

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
            
            # Node details
            if [[ $docker_count -gt 0 ]]; then
                for node in $docker_nodes; do
                    local node_status=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGET "node:$node:eu-west-1:status" "status" 2>/dev/null || echo "unknown")
                    local current_job=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGET "node:$node:eu-west-1:status" "current_job" 2>/dev/null || echo "idle")
                    local node_icon=$([ "$node_status" = "available" ] && echo "🟢" || echo "🟡")
                    printf "│   └─ %-15s │ %-10s │ Job: %-35s │\n" "$node" "$node_icon $node_status" "$current_job"
                done
            fi
            
            if [[ $native_count -gt 0 ]]; then
                for node in $native_nodes; do
                    local last_seen=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGET "node:$node:eu-west-1:info" "last_seen" 2>/dev/null || echo "never")
                    local node_icon="🟢"  # Assume native nodes are healthy if registered
                    printf "│   └─ %-15s │ %-10s │ Last seen: %-28s │\n" "$node" "$node_icon native" "$last_seen"
                done
            fi
        else
            printf "│ %-76s │\n" "❌ Cannot retrieve node status (Redis unavailable)"
        fi
        
        echo "└─────────────────────────────────────────────────────────────────────────────────┘"
        
        # Recent Activity
        echo -e "\n${BLUE}📈 RECENT ACTIVITY${NC}"
        echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
        
        if [[ "$redis_health" == "PONG" ]]; then
            # Recent jobs (last 5 results)
            local recent_results=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT KEYS "result:*" 2>/dev/null | head -5)
            if [[ -n "$recent_results" ]]; then
                printf "│ %-76s │\n" "Recent Completed Jobs:"
                for result_key in $recent_results; do
                    local job_id=$(echo "$result_key" | sed 's/result://')
                    local status=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGET "$result_key" "success" 2>/dev/null || echo "unknown")
                    local timestamp=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGET "$result_key" "timestamp" 2>/dev/null || echo "unknown")
                    local status_icon=$([ "$status" = "true" ] && echo "✅" || echo "❌")
                    printf "│   %s %-20s │ %-10s │ %-35s │\n" "$status_icon" "$job_id" "$status" "$timestamp"
                done
            else
                printf "│ %-76s │\n" "No recent activity"
            fi
        else
            printf "│ %-76s │\n" "❌ Cannot retrieve activity (Redis unavailable)"
        fi
        
        echo "└─────────────────────────────────────────────────────────────────────────────────┘"
        
        # Live Job Flow Trace
        echo -e "\n${PURPLE}🔄 LIVE JOB FLOW TRACE${NC}"
        echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
        
        if [[ "$redis_health" == "PONG" ]]; then
            # Monitor for new jobs in real-time
            local latest_job=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LINDEX "jobs:queue:eu-west-1" 0 2>/dev/null)
            if [[ -n "$latest_job" && "$latest_job" != "nil" ]]; then
                printf "│ %-76s │\n" "🔄 Latest queued job: $latest_job"
                
                # Try to get job details
                local job_data=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGETALL "job:$latest_job" 2>/dev/null)
                if [[ -n "$job_data" ]]; then
                    printf "│ %-76s │\n" "   └─ Job details available in Redis"
                fi
            else
                printf "│ %-76s │\n" "💤 No jobs currently in queue"
            fi
            
            # Check processing status
            local processing_job=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LINDEX "jobs:processing:eu-west-1" 0 2>/dev/null)
            if [[ -n "$processing_job" && "$processing_job" != "nil" ]]; then
                printf "│ %-76s │\n" "⚙️  Currently processing: $processing_job"
            fi
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

# Performance monitoring mode
performance_mode() {
    echo -e "${CYAN}🏃‍♂️ Performance Monitoring Mode${NC}\n"
    
    local start_time=$(date +%s)
    local job_count=0
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        clear
        echo -e "${CYAN}PERFORMANCE METRICS (Runtime: ${elapsed}s)${NC}\n"
        
        # Throughput metrics
        if [[ "$elapsed" -gt 0 ]]; then
            local throughput=$(echo "scale=2; $job_count / $elapsed" | bc 2>/dev/null || echo "0")
            echo "Jobs processed: $job_count"
            echo "Throughput: $throughput jobs/second"
        fi
        
        # Queue lengths over time
        local pending=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0")
        local processing=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:processing:eu-west-1" 2>/dev/null || echo "0")
        
        echo -e "\nCurrent Queue State:"
        echo "Pending: $pending"
        echo "Processing: $processing"
        
        # Memory usage simulation
        local redis_info=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT INFO memory 2>/dev/null || echo "")
        if [[ -n "$redis_info" ]]; then
            local used_memory=$(echo "$redis_info" | grep "used_memory_human" | cut -d: -f2 | tr -d '\r\n')
            echo "Redis Memory: $used_memory"
        fi
        
        sleep 2
    done
}

# Debug mode with detailed logging
debug_mode() {
    echo -e "${RED}🐛 Debug Mode - Detailed Service Communication${NC}\n"
    
    # Start monitoring all Redis operations
    redis-cli -h $REDIS_HOST -p $REDIS_PORT MONITOR > /tmp/redis_debug.log &
    local redis_monitor_pid=$!
    
    echo "Started Redis monitoring (PID: $redis_monitor_pid)"
    echo "Log file: /tmp/redis_debug.log"
    echo -e "\nPress Ctrl+C to stop...\n"
    
    # Tail the log file with filtering
    tail -f /tmp/redis_debug.log | while read line; do
        # Filter for SynapseGrid related operations
        if [[ "$line" =~ (job|node|result|queue) ]]; then
            local timestamp=$(date +'%H:%M:%S')
            echo "[$timestamp] $line"
        fi
    done
    
    # Cleanup on exit
    trap "kill $redis_monitor_pid 2>/dev/null; rm -f /tmp/redis_debug.log" EXIT
}

# Main menu
show_menu() {
    echo -e "${CYAN}SynapseGrid Real-Time Monitor${NC}\n"
    echo "Select monitoring mode:"
    echo "1) Real-time Dashboard"
    echo "2) Performance Metrics"
    echo "3) Debug Mode"
    echo "4) Exit"
    echo ""
    read -p "Enter choice [1-4]: " choice
    
    case $choice in
        1) show_realtime_dashboard ;;
        2) performance_mode ;;
        3) debug_mode ;;
        4) exit 0 ;;
        *) echo "Invalid choice"; show_menu ;;
    esac
}

# Signal handling
trap 'echo -e "\n\n${YELLOW}Monitoring stopped.${NC}"; exit 0' SIGINT SIGTERM

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt-get update && sudo apt-get install -y jq
fi

if ! command -v bc &> /dev/null; then
    echo "Installing bc..."
    sudo apt-get install -y bc
fi

# Main execution
if [[ "$1" == "--performance" ]]; then
    performance_mode
elif [[ "$1" == "--debug" ]]; then
    debug_mode
elif [[ "$1" == "--dashboard" ]]; then
    show_realtime_dashboard
else
    show_menu
fi
