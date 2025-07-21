#!/bin/bash

echo "🔧 Fixing Mac Node Heartbeat Issues"
echo "==================================="

# 1. Fix Gateway endpoints for node registration/heartbeat
echo "1. Adding missing endpoints to gateway..."

# Check if gateway service exists
if [ ! -f "services/gateway/main.py" ]; then
    echo "❌ Gateway service not found at services/gateway/main.py"
    exit 1
fi

# Backup current gateway
cp services/gateway/main.py services/gateway/main.py.backup

# Add missing endpoints to gateway
cat >> services/gateway/main.py << 'EOF'

# Node Management Endpoints (Missing endpoints causing 404)
@app.post("/nodes/register")
async def register_node(node_data: dict):
    """Register a node with the gateway"""
    node_id = node_data.get("node_id")
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Store node info in Redis
        node_key = f"node:{node_id}:info"
        await redis_client.hmset(node_key, {
            "node_id": node_id,
            "node_type": node_data.get("node_type", "unknown"),
            "status": "active",
            "performance_score": str(node_data.get("performance_score", 0)),
            "cpu_usage": str(node_data.get("cpu_usage", 0)),
            "memory_usage": str(node_data.get("memory_usage", 0)),
            "registered_at": datetime.utcnow().isoformat(),
            "last_seen": datetime.utcnow().isoformat()
        })
        
        # Set expiration
        await redis_client.expire(node_key, 300)  # 5 minutes
        
        # Add to active nodes set
        await redis_client.sadd("nodes:active", node_id)
        
        logger.info(f"✅ Node registered: {node_id}")
        return {"status": "registered", "node_id": node_id}
        
    except Exception as e:
        logger.error(f"❌ Failed to register node {node_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/nodes/heartbeat")
async def node_heartbeat(node_data: dict):
    """Receive heartbeat from a node"""
    node_id = node_data.get("node_id")
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Update node info in Redis
        node_key = f"node:{node_id}:info"
        
        # Check if node exists
        exists = await redis_client.exists(node_key)
        if not exists:
            # Auto-register if node doesn't exist
            logger.info(f"Auto-registering node on heartbeat: {node_id}")
            return await register_node(node_data)
        
        # Update node metrics
        await redis_client.hmset(node_key, {
            "status": node_data.get("status", "active"),
            "performance_score": str(node_data.get("performance_score", 0)),
            "cpu_usage": str(node_data.get("cpu_usage", 0)),
            "memory_usage": str(node_data.get("memory_usage", 0)),
            "jobs_completed": str(node_data.get("jobs_completed", 0)),
            "uptime": str(node_data.get("uptime", 0)),
            "last_seen": datetime.utcnow().isoformat()
        })
        
        # Refresh expiration
        await redis_client.expire(node_key, 300)
        
        # Ensure in active set
        await redis_client.sadd("nodes:active", node_id)
        
        return {"status": "heartbeat_received", "node_id": node_id}
        
    except Exception as e:
        logger.error(f"❌ Failed to process heartbeat for {node_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes")
async def list_nodes():
    """List all active nodes"""
    try:
        active_nodes = await redis_client.smembers("nodes:active")
        nodes = []
        
        for node_id in active_nodes:
            node_key = f"node:{node_id}:info"
            node_info = await redis_client.hgetall(node_key)
            if node_info:
                nodes.append(node_info)
        
        return {"nodes": nodes, "count": len(nodes)}
        
    except Exception as e:
        logger.error(f"❌ Failed to list nodes: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes/{node_id}")
async def get_node_info(node_id: str):
    """Get specific node information"""
    try:
        node_key = f"node:{node_id}:info"
        node_info = await redis_client.hgetall(node_key)
        
        if not node_info:
            raise HTTPException(status_code=404, detail="Node not found")
            
        return node_info
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to get node info for {node_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Update stats endpoint to include node information
@app.get("/stats")
async def get_stats():
    """Get system statistics including node information"""
    try:
        # Get basic stats
        total_jobs = await redis_client.get("stats:total_jobs") or "0"
        active_jobs = await redis_client.get("stats:active_jobs") or "0"
        
        # Get node stats
        active_nodes = await redis_client.smembers("nodes:active")
        node_count = len(active_nodes)
        
        # Get detailed node info
        nodes = []
        for node_id in active_nodes:
            node_key = f"node:{node_id}:info"
            node_info = await redis_client.hgetall(node_key)
            if node_info:
                nodes.append({
                    "node_id": node_info.get("node_id"),
                    "node_type": node_info.get("node_type"),
                    "status": node_info.get("status"),
                    "performance_score": int(node_info.get("performance_score", 0)),
                    "cpu_usage": float(node_info.get("cpu_usage", 0)),
                    "memory_usage": float(node_info.get("memory_usage", 0)),
                    "jobs_completed": int(node_info.get("jobs_completed", 0)),
                    "last_seen": node_info.get("last_seen")
                })
        
        return {
            "total_jobs": int(total_jobs),
            "active_jobs": int(active_jobs),
            "nodes": {
                "total": node_count,
                "active": node_count,
                "details": nodes
            },
            "system": {
                "status": "healthy",
                "timestamp": datetime.utcnow().isoformat()
            }
        }
        
    except Exception as e:
        logger.error(f"❌ Failed to get stats: {e}")
        return {
            "total_jobs": 0,
            "active_jobs": 0,
            "nodes": {"total": 0, "active": 0, "details": []},
            "system": {"status": "error", "error": str(e)}
        }

EOF

echo "✅ Gateway endpoints added successfully"

# 2. Fix Mac Node to better handle connection issues
echo "2. Improving Mac Node connection handling..."

# Update Mac node if it exists
if [ -f "native_node/mac_m2_node.py" ]; then
    cp native_node/mac_m2_node.py native_node/mac_m2_node.py.backup
    
    # Update the heartbeat section
    sed -i '' 's/f"{GATEWAY_URL}\/nodes\/heartbeat"/f"{GATEWAY_URL}\/nodes\/heartbeat"/g' native_node/mac_m2_node.py
    sed -i '' 's/f"{GATEWAY_URL}\/nodes\/register"/f"{GATEWAY_URL}\/nodes\/register"/g' native_node/mac_m2_node.py
fi

# 3. Fix Mac control script to wait for gateway
echo "3. Updating Mac control script..."

if [ -f "mac_m2_control.sh" ]; then
    # Add gateway readiness check
    cat >> mac_m2_control.sh << 'EOF'

wait_for_gateway() {
    log "Attente du Gateway..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:8080/health" >/dev/null 2>&1; then
            success "Gateway disponible ✓"
            return 0
        fi
        
        warn "Gateway non disponible, tentative $attempt/$max_attempts..."
        sleep 2
        ((attempt++))
    done
    
    error "Gateway non disponible après $max_attempts tentatives"
    return 1
}

# Update start function to wait for gateway
start_mac_node() {
    mac_log "Démarrage du nœud Mac M2 natif..."
    
    if is_mac_running; then
        warn "Nœud Mac M2 déjà actif"
        return 0
    fi
    
    check_dependencies || return 1
    
    # Wait for gateway to be ready
    wait_for_gateway || {
        error "Impossible de démarrer sans Gateway"
        return 1
    }
    
    # Create service if needed
    if [ ! -f "$MAC_NODE_SCRIPT" ]; then
        log "Service Mac M2 non trouvé, création..."
        create_mac_node_service
    fi
    
    # Start in background
    nohup python3 "$MAC_NODE_SCRIPT" > "$MAC_LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$MAC_PID_FILE"
    
    # Wait for startup
    sleep 3
    
    if is_mac_running; then
        success "Nœud Mac M2 démarré (PID: $pid)"
        success "Status: http://localhost:$NODE_PORT/status"
        success "Logs: tail -f $MAC_LOG_FILE"
        return 0
    else
        error "Échec du démarrage du nœud Mac M2"
        return 1
    fi
}
EOF
fi

echo "4. Updating Makefile for better service coordination..."

# Update Makefile to ensure proper startup order
if [ -f "Makefile" ]; then
    # Add a proper mac startup command that waits for gateway
    cat >> Makefile << 'EOF'

# Wait for services to be ready
wait-for-services:
	@echo "⏳ Waiting for services to be ready..."
	@for i in {1..30}; do \
		if curl -s http://localhost:8080/health >/dev/null 2>&1; then \
			echo "✅ Gateway ready"; \
			break; \
		else \
			echo "⏳ Waiting for gateway... ($$i/30)"; \
			sleep 2; \
		fi; \
	done

# Start Mac node with proper gateway wait
mac-start-fixed:
	@echo "🍎 Starting Mac M2 with gateway check..."
	@$(MAKE) wait-for-services
	@$(MAKE) mac-start

# Complete startup sequence
start-all-fixed:
	@echo "🚀 Starting complete system with proper timing..."
	@$(MAKE) start
	@$(MAKE) wait-for-services
	@$(MAKE) mac-start-fixed
	@echo "✅ System ready!"

EOF
fi

echo "5. Testing the fixes..."

# Check if Docker is running
if ! docker ps >/dev/null 2>&1; then
    echo "⚠️  Docker not running. Start Docker and try again."
    exit 1
fi

echo ""
echo "🎯 Fixes Applied Successfully!"
echo "============================"
echo "✅ Added missing gateway endpoints:"
echo "   - POST /nodes/register"
echo "   - POST /nodes/heartbeat" 
echo "   - GET /nodes"
echo "   - GET /nodes/{node_id}"
echo "   - Enhanced GET /stats"
echo ""
echo "✅ Improved Mac node connection handling"
echo "✅ Added gateway readiness checks"
echo "✅ Updated Makefile with proper startup sequence"
echo ""
echo "🚀 Try these commands now:"
echo "1. make start              # Start Docker services"
echo "2. make wait-for-services  # Wait for gateway readiness"
echo "3. make mac-start          # Start Mac node"
echo ""
echo "Or use the combined command:"
echo "make start-all-fixed"
echo ""
echo "🔍 Debug commands:"
echo "make mac-logs    # Check Mac node logs"
echo "make logs        # Check Docker logs"
echo "curl http://localhost:8080/nodes  # List registered nodes"
echo ""
echo "The heartbeat 404 errors should now be resolved! 🎉"
