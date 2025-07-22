#!/bin/bash

# SynapseGrid Auto-Start Script - Production Ready
# Intelligently detects system state and starts everything properly
# Compatible with Debian + Docker + Python services + Mac M2 native nodes

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
GATEWAY_URL="http://localhost:8080"
REDIS_HOST="localhost"
REDIS_PORT="6379"
TIMEOUT=60
SCRIPT_VERSION="1.0.0"

log() { echo -e "${BLUE}[AUTOSTART]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Banner with version
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   ███████╗██╗   ██╗███╗   ██╗ █████╗ ██████╗ ███████╗███████╗   ║
║   ██╔════╝╚██╗ ██╔╝████╗  ██║██╔══██╗██╔══██╗██╔════╝██╔════╝   ║
║   ███████╗ ╚████╔╝ ██╔██╗ ██║███████║██████╔╝███████╗█████╗     ║
║   ╚════██║  ╚██╔╝  ██║╚██╗██║██╔══██║██╔═══╝ ╚════██║██╔══╝     ║
║   ███████║   ██║   ██║ ╚████║██║  ██║██║     ███████║███████╗   ║
║   ╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝   ║
║                                                                  ║
║              🧠⚡ Decentralized AI Infrastructure                 ║
║                        Auto-Start v1.0.0                        ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

# Detect system status and capabilities
detect_system() {
    log "Detecting system status and capabilities..."
    
    # OS Detection
    case "$OSTYPE" in
        darwin*) 
            IS_MAC=true
            OS_NAME="macOS"
            ;;
        linux-gnu*) 
            IS_MAC=false
            OS_NAME="Linux"
            ;;
        *) 
            IS_MAC=false
            OS_NAME="Unknown"
            ;;
    esac
    
    log "Operating System: $OS_NAME"
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running. Please start Docker first."
    fi
    
    log "✅ Docker is available and running"
    
    # Check Docker Compose
    if command -v "docker compose" >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        log "✅ Docker Compose (modern) available"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
        log "✅ Docker Compose (legacy) available"
    else
        error "Docker Compose not found. Please install docker-compose."
    fi
    
    # Check if services are already running
    SERVICES_RUNNING=false
    if docker ps --format "{{.Names}}" | grep -q "synapse"; then
        SERVICES_RUNNING=true
        RUNNING_COUNT=$(docker ps --format "{{.Names}}" | grep -c "synapse")
        log "SynapseGrid services already running ($RUNNING_COUNT containers)"
    fi
    
    # Check if setup was done
    SETUP_DONE=false
    if [ -f "scripts/job_flow_verifier.sh" ] && [ -x "scripts/job_flow_verifier.sh" ]; then
        SETUP_DONE=true
        log "✅ Job flow tools are set up"
    fi
    
    # Check essential dependencies
    DEPS_OK=true
    for cmd in curl jq redis-cli; do
        if ! command -v $cmd >/dev/null 2>&1; then
            warning "$cmd is not installed (will attempt to install)"
            DEPS_OK=false
        fi
    done
    
    if [ "$DEPS_OK" = true ]; then
        log "✅ All essential dependencies available"
    fi
    
    # Mac M2 specific checks
    if [ "$IS_MAC" = true ]; then
        if [ -f "mac_m2_control.sh" ] && [ -d "native_node" ]; then
            MAC_SETUP_DONE=true
            log "✅ Mac M2 native node environment ready"
        else
            MAC_SETUP_DONE=false
            log "Mac M2 environment not configured"
        fi
    fi
}

# Install missing dependencies intelligently
install_dependencies() {
    log "Installing missing dependencies..."
    
    case "$OS_NAME" in
        "Linux")
            if command -v apt-get >/dev/null 2>&1; then
                log "Installing dependencies via apt-get..."
                sudo apt-get update -qq
                sudo apt-get install -y redis-tools postgresql-client curl jq bc net-tools
            elif command -v yum >/dev/null 2>&1; then
                log "Installing dependencies via yum..."
                sudo yum install -y redis curl jq bc net-tools
            else
                warning "Unknown package manager. Please install manually: redis-tools, curl, jq, bc"
            fi
            ;;
        "macOS")
            if command -v brew >/dev/null 2>&1; then
                log "Installing dependencies via Homebrew..."
                brew install redis curl jq bc
            else
                warning "Homebrew not found. Please install it first: https://brew.sh"
            fi
            ;;
        *)
            warning "Unknown OS. Please install dependencies manually."
            ;;
    esac
    
    success "Dependencies installation attempted"
}

# Smart setup with error handling
smart_setup() {
    if [ "$SETUP_DONE" = false ] || [ "$DEPS_OK" = false ]; then
        log "Running setup process..."
        
        # Try to install dependencies if missing
        if [ "$DEPS_OK" = false ]; then
            install_dependencies
        fi
        
        # Run make setup
        if command -v make >/dev/null 2>&1; then
            log "Running 'make setup'..."
            if ! make setup; then
                warning "Make setup failed, trying manual setup..."
                manual_setup
            fi
        else
            log "Make not available, running manual setup..."
            manual_setup
        fi
        
        success "Setup completed"
    else
        log "Setup already complete, skipping..."
    fi
}

# Manual setup if make fails
manual_setup() {
    log "Running manual setup..."
    
    # Create directories
    mkdir -p {scripts,logs,native_node/{src,logs,models,venv},dashboard,exports}
    
    # Create basic job flow verifier if missing
    if [ ! -f "scripts/job_flow_verifier.sh" ]; then
        log "Creating basic job flow verifier..."
        cat > scripts/job_flow_verifier.sh << 'SCRIPT_EOF'
#!/bin/bash
# Basic job flow verifier
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

case "$1" in
    test)
        echo "Submitting test job..."
        response=$(curl -s -X POST "$GATEWAY_URL/submit" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer test-token" \
            -H "X-Client-ID: auto-test" \
            -d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}}')
        echo "Response: $response"
        ;;
    status)
        echo "System status:"
        curl -s "$GATEWAY_URL/health" | jq . 2>/dev/null || echo "Gateway not responding"
        redis-cli -h $REDIS_HOST -p $REDIS_PORT ping 2>/dev/null || echo "Redis not responding"
        ;;
    *)
        echo "Usage: $0 {test|status}"
        ;;
esac
SCRIPT_EOF
        chmod +x scripts/job_flow_verifier.sh
    fi
    
    # Create basic monitor if missing
    if [ ! -f "scripts/real_time_monitor.sh" ]; then
        log "Creating basic real-time monitor..."
        cat > scripts/real_time_monitor.sh << 'MONITOR_EOF'
#!/bin/bash
# Basic real-time monitor
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

echo "SynapseGrid Real-Time Monitor"
echo "============================="
echo "Gateway: $(curl -s --max-time 2 "$GATEWAY_URL/health" >/dev/null && echo "OK" || echo "DOWN")"
echo "Redis: $(redis-cli -h $REDIS_HOST -p $REDIS_PORT ping 2>/dev/null || echo "DOWN")"
echo "Pending jobs: $(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "N/A")"
echo "Processing jobs: $(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:processing:eu-west-1" 2>/dev/null || echo "N/A")"
echo "Available nodes: $(redis-cli -h $REDIS_HOST -p $REDIS_PORT SCARD "nodes:eu-west-1:available" 2>/dev/null || echo "N/A")"
MONITOR_EOF
        chmod +x scripts/real_time_monitor.sh
    fi
    
    success "Manual setup completed"
}

# Smart start services with health checking
smart_start() {
    if [ "$SERVICES_RUNNING" = false ]; then
        log "Starting SynapseGrid services..."
        
        # Check if docker-compose.yml exists
        if [ ! -f "docker-compose.yml" ]; then
            error "docker-compose.yml not found. Are you in the correct directory?"
        fi
        
        # Start services
        log "Executing: $DOCKER_COMPOSE_CMD up -d"
        if ! $DOCKER_COMPOSE_CMD up -d; then
            error "Failed to start Docker services"
        fi
        
        success "Docker services started"
        
        # Wait for services to be ready
        log "Waiting for services to be ready..."
        wait_for_services
    else
        log "Services already running, checking health..."
        check_health
    fi
}

# Wait for services to be ready with timeout
wait_for_services() {
    local elapsed=0
    local max_wait=$TIMEOUT
    
    log "Waiting up to ${max_wait}s for services to be ready..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Check Gateway
        if curl -s --max-time 2 "$GATEWAY_URL/health" >/dev/null 2>&1; then
            success "✅ Gateway is ready!"
            break
        fi
        
        echo -n "."
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        warning "⚠️  Gateway took longer than expected to start"
    fi
    
    # Check Redis with timeout
    local redis_ready=false
    for i in {1..10}; do
        if redis-cli -h $REDIS_HOST -p $REDIS_PORT ping >/dev/null 2>&1; then
            success "✅ Redis is ready!"
            redis_ready=true
            break
        fi
        sleep 2
    done
    
    if [ "$redis_ready" = false ]; then
        warning "⚠️  Redis not responding"
    fi
}

# Check service health with detailed status
check_health() {
    log "Checking service health..."
    
    local all_healthy=true
    
    # Gateway health
    if curl -s --max-time 3 "$GATEWAY_URL/health" >/dev/null 2>&1; then
        success "✅ Gateway healthy"
    else
        warning "⚠️  Gateway not responding"
        all_healthy=false
    fi
    
    # Redis health
    if redis-cli -h $REDIS_HOST -p $REDIS_PORT ping >/dev/null 2>&1; then
        success "✅ Redis healthy"
    else
        warning "⚠️  Redis not responding"
        all_healthy=false
    fi
    
    # Docker services
    local running_containers=$(docker ps --filter "name=synapse" --format "{{.Names}}" | wc -l)
    if [ $running_containers -gt 0 ]; then
        success "✅ $running_containers Docker services running"
    else
        warning "⚠️  No SynapseGrid containers running"
        all_healthy=false
    fi
    
    # Overall health status
    if [ "$all_healthy" = true ]; then
        success "🎉 All services are healthy!"
    else
        warning "⚠️  Some services have issues"
    fi
}

# Start Mac M2 node if applicable
start_mac_node() {
    if [ "$IS_MAC" = true ]; then
        log "Checking Mac M2 native node..."
        
        if [ "$MAC_SETUP_DONE" = true ]; then
            if [ -f "mac_m2_control.sh" ]; then
                # Check if already running
                if ./mac_m2_control.sh status 2>/dev/null | grep -q "running"; then
                    log "✅ Mac M2 node already running"
                else
                    log "Starting Mac M2 native node..."
                    if ./mac_m2_control.sh start; then
                        success "✅ Mac M2 node started"
                    else
                        warning "⚠️  Failed to start Mac M2 node"
                    fi
                fi
            elif command -v make >/dev/null 2>&1; then
                log "Attempting to start Mac M2 via Makefile..."
                make mac-start 2>/dev/null || warning "Mac M2 start failed"
            fi
        else
            log "Mac M2 environment not configured, skipping..."
        fi
    fi
}

# Run comprehensive verification test
run_verification() {
    log "Running system verification..."
    
    echo ""
    echo -e "${CYAN}🧪 Running Job Flow Verification Test...${NC}"
    
    # Test 1: Basic connectivity
    log "Test 1: Basic connectivity"
    local connectivity_ok=true
    
    if ! curl -s --max-time 5 "$GATEWAY_URL/health" >/dev/null; then
        warning "❌ Gateway connectivity failed"
        connectivity_ok=false
    else
        log "✅ Gateway connectivity OK"
    fi
    
    if ! redis-cli -h $REDIS_HOST -p $REDIS_PORT ping >/dev/null 2>&1; then
        warning "❌ Redis connectivity failed"
        connectivity_ok=false
    else
        log "✅ Redis connectivity OK"
    fi
    
    if [ "$connectivity_ok" = false ]; then
        warning "Skipping job submission test due to connectivity issues"
        return 1
    fi
    
    # Test 2: Job submission
    log "Test 2: Job submission"
    response=$(curl -s -X POST "$GATEWAY_URL/submit" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token" \
        -H "X-Client-ID: autostart-verification" \
        -d '{"model_name": "resnet50", "input_data": {"image": "verification_test.jpg"}}' 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        job_id=$(echo "$response" | jq -r '.job_id // "failed"' 2>/dev/null)
        if [ "$job_id" != "failed" ] && [ "$job_id" != "null" ] && [ -n "$job_id" ]; then
            success "✅ Test job submitted: $job_id"
            
            # Test 3: Job processing monitoring
            log "Test 3: Job processing monitoring (15s timeout)"
            local job_completed=false
            
            for i in {1..15}; do
                # Check if result exists
                if redis-cli -h $REDIS_HOST -p $REDIS_PORT EXISTS "result:$job_id" >/dev/null 2>&1; then
                    success "✅ Job completed successfully!"
                    
                    # Show result summary
                    result_data=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT HGETALL "result:$job_id" 2>/dev/null)
                    if [ -n "$result_data" ]; then
                        echo "   Result summary:"
                        echo "$result_data" | sed 's/^/      /'
                    fi
                    
                    job_completed=true
                    break
                fi
                
                echo -n "."
                sleep 1
            done
            
            if [ "$job_completed" = false ]; then
                warning "⚠️  Job processing timeout (may still be running)"
                
                # Show queue status
                local pending=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0")
                local processing=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT LLEN "jobs:processing:eu-west-1" 2>/dev/null || echo "0")
                echo "   Queue status: $pending pending, $processing processing"
            fi
        else
            warning "⚠️  Job submission returned unexpected response: $response"
        fi
    else
        warning "⚠️  Failed to submit test job"
    fi
    
    # Test 4: Node availability
    log "Test 4: Node availability"
    local available_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SCARD "nodes:eu-west-1:available" 2>/dev/null || echo "0")
    local native_nodes=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT SCARD "native_nodes" 2>/dev/null || echo "0")
    
    echo "   Docker nodes available: $available_nodes"
    echo "   Native M2 nodes: $native_nodes"
    
    if [ "$available_nodes" -gt 0 ] || [ "$native_nodes" -gt 0 ]; then
        success "✅ Nodes are available for job processing"
    else
        warning "⚠️  No nodes available (jobs may queue indefinitely)"
    fi
    
    success "🎯 Verification test completed!"
}

# Show access points and next steps
show_access_points() {
    echo ""
    echo -e "${GREEN}🚀 SynapseGrid is now running!${NC}"
    echo ""
    echo -e "${CYAN}📱 Access Points:${NC}"
    echo "  🌐 Gateway API:      $GATEWAY_URL"
    echo "  📊 Dashboard:        http://localhost:3000"
    echo "  📈 Grafana:          http://localhost:3001 (admin/admin123)"
    echo "  🔍 Prometheus:       http://localhost:9090"
    echo ""
    echo -e "${CYAN}🛠️  Quick Commands:${NC}"
    echo "  📊 Real-time monitor: make flow-monitor"
    echo "  🧪 Test job flow:     make job-test"
    echo "  📈 System status:     make status"
    echo "  🔧 All commands:      make help"
    echo ""
    
    if [ "$IS_MAC" = true ]; then
        echo -e "${PURPLE}🍎 Mac M2 Commands:${NC}"
        echo "  🚀 Start M2 node:     make mac-start"
        echo "  📊 M2 status:         make mac-status"
        echo "  🧪 Test M2:           make mac-test"
        echo ""
    fi
    
    echo -e "${YELLOW}💡 Quick Actions:${NC}"
    echo "  Test the system:      ./scripts/quick_test.sh"
    echo "  Monitor in real-time: ./scripts/real_time_monitor.sh"
    echo "  Submit a job:         make submit-job"
    echo ""
    echo -e "${BLUE}📚 Documentation:${NC}"
    echo "  Quick start guide:    cat QUICK_START.md"
    echo "  Script documentation: cat scripts/README.md"
    echo ""
}

# Interactive mode with menu
interactive_mode() {
    echo -e "${CYAN}🤖 SynapseGrid Interactive Setup${NC}"
    echo "=================================="
    echo ""
    echo "Current system status:"
    echo "  OS: $OS_NAME"
    echo "  Docker: $(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo 'Not available')"
    echo "  Services running: $([ "$SERVICES_RUNNING" = true ] && echo "Yes ($RUNNING_COUNT containers)" || echo "No")"
    echo "  Setup done: $([ "$SETUP_DONE" = true ] && echo "Yes" || echo "No")"
    if [ "$IS_MAC" = true ]; then
        echo "  Mac M2 ready: $([ "$MAC_SETUP_DONE" = true ] && echo "Yes" || echo "No")"
    fi
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "1) 🚀 Full auto-start (recommended)"
    echo "2) 🔧 Setup environment only"
    echo "3) ▶️  Start services only"
    echo "4) 🧪 Run verification test"
    echo "5) 📊 Show system status"
    echo "6) 🍎 Mac M2 setup (macOS only)"
    echo "7) 🛠️  Advanced options"
    echo "8) ❌ Exit"
    echo ""
    read -p "Choose an option (1-8): " choice
    
    case $choice in
        1)
            log "Running full auto-start..."
            smart_setup
            smart_start
            start_mac_node
            run_verification
            show_access_points
            ;;
        2)
            log "Running setup only..."
            smart_setup
            success "Setup complete. Run '$0' again to start services."
            ;;
        3)
            log "Starting services only..."
            smart_start
            show_access_points
            ;;
        4)
            log "Running verification test..."
            run_verification
            ;;
        5)
            log "Showing system status..."
            check_health
            ;;
        6)
            if [ "$IS_MAC" = true ]; then
                log "Mac M2 setup..."
                if command -v make >/dev/null 2>&1; then
                    make mac-setup || warning "Mac M2 setup failed"
                else
                    warning "Make not available for Mac M2 setup"
                fi
            else
                warning "Mac M2 setup only available on macOS"
            fi
            ;;
        7)
            advanced_options
            ;;
        8)
            log "Exiting..."
            exit 0
            ;;
        *)
            warning "Invalid choice. Running full auto-start..."
            smart_setup
            smart_start
            start_mac_node
            run_verification
            show_access_points
            ;;
    esac
}

# Advanced options menu
advanced_options() {
    echo ""
    echo -e "${PURPLE}🛠️  Advanced Options${NC}"
    echo "==================="
    echo ""
    echo "1) 🔄 Reset and restart everything"
    echo "2) 🧹 Clean logs and data"
    echo "3) 🔍 Debug system issues"
    echo "4) 📦 Export logs"
    echo "5) ⚙️  Configuration info"
    echo "6) 🔙 Back to main menu"
    echo ""
    read -p "Choose an option (1-6): " adv_choice
    
    case $adv_choice in
        1)
            log "Resetting system..."
            if command -v make >/dev/null 2>&1; then
                make clean-all || true
                make setup
                make start
            else
                $DOCKER_COMPOSE_CMD down -v --remove-orphans || true
                smart_setup
                smart_start
            fi
            ;;
        2)
            log "Cleaning logs and data..."
            rm -rf logs/*.log 2>/dev/null || true
            rm -rf native_node/logs/*.log 2>/dev/null || true
            success "Logs cleaned"
            ;;
        3)
            log "Running debug diagnostics..."
            if command -v make >/dev/null 2>&1; then
                make debug-full || true
            else
                echo "Basic debug info:"
                docker ps --filter "name=synapse"
                docker network ls | grep synapse || true
            fi
            ;;
        4)
            log "Exporting logs..."
            mkdir -p exports/logs_$(date +%Y%m%d_%H%M%S)
            cp logs/*.log exports/logs_$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
            success "Logs exported"
            ;;
        5)
            log "Configuration information:"
            echo "  Gateway URL: $GATEWAY_URL"
            echo "  Redis: $REDIS_HOST:$REDIS_PORT"
            echo "  Docker Compose: $DOCKER_COMPOSE_CMD"
            echo "  Script Version: $SCRIPT_VERSION"
            echo "  Working Directory: $(pwd)"
            ;;
        6)
            interactive_mode
            ;;
        *)
            warning "Invalid choice"
            ;;
    esac
}

# Error handling and cleanup
cleanup() {
    echo -e "\n${YELLOW}Auto-start interrupted.${NC}"
    echo "System may be in partial start state."
    echo "Run '$0 status' to check current state."
    exit 1
}

# Show help
show_help() {
    echo "SynapseGrid Auto-Start Script v$SCRIPT_VERSION"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  auto         Full automatic setup and start (default)"
    echo "  interactive  Interactive setup mode with menu"
    echo "  quick        Quick start services only"
    echo "  setup        Run setup only"
    echo "  start        Start services only"
    echo "  verify       Run verification test only"
    echo "  status       Show system status"
    echo "  stop         Stop all services"
    echo "  help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $0           # Full auto-start"
    echo "  $0 interactive   # Interactive mode"
    echo "  $0 quick         # Quick start"
    echo "  $0 verify        # Test only"
    echo ""
}

# Main execution function
main() {
    # Trap for cleanup
    trap cleanup INT TERM
    
    # Parse command line arguments
    case "${1:-auto}" in
        auto|"")
            show_banner
            log "Starting SynapseGrid auto-start sequence..."
            detect_system
            smart_setup
            smart_start
            start_mac_node
            run_verification
            show_access_points
            ;;
        interactive|i)
            show_banner
            detect_system
            interactive_mode
            ;;
        quick|q)
            show_banner
            log "Quick start mode..."
            detect_system
            smart_start
            show_access_points
            ;;
        setup)
            log "Setup mode..."
            detect_system
            smart_setup
            success "Setup complete"
            ;;
        start)
            log "Start mode..."
            detect_system
            smart_start
            show_access_points
            ;;
        verify|v)
            log "Verification mode..."
            detect_system
            run_verification
            ;;
        status|s)
            log "Status check mode..."
            detect_system
            check_health
            ;;
        stop)
            log "Stopping all services..."
            if command -v make >/dev/null 2>&1; then
                make stop
            else
                $DOCKER_COMPOSE_CMD down
            fi
            success "Services stopped"
            ;;
        help|h|-h|--help)
            show_help
            ;;
        *)
            warning "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
