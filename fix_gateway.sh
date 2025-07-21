#!/bin/bash

echo "🔧 Correction rapide du Gateway pour les endpoints Mac"
echo "===================================================="

# Sauvegarder le fichier actuel
cp services/gateway/main.py services/gateway/main.py.backup.$(date +%s)
echo "✅ Backup créé"

# Ajouter les endpoints manquants au Gateway
cat >> services/gateway/main.py << 'EOF'

# === ENDPOINTS MANQUANTS POUR LE NODE MAC ===

@app.post("/nodes/register")
async def register_node(node_data: dict):
    """Register a node with the gateway"""
    node_id = node_data.get("node_id")
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Store node info in Redis
        node_key = f"node:{node_id}:info"
        node_info = {
            "node_id": node_id,
            "node_type": node_data.get("node_type", "unknown"),
            "status": "active",
            "performance_score": str(node_data.get("performance_score", 0)),
            "cpu_usage": str(node_data.get("cpu_usage", 0)),
            "memory_usage": str(node_data.get("memory_usage", 0)),
            "registered_at": datetime.utcnow().isoformat(),
            "last_seen": datetime.utcnow().isoformat()
        }
        
        # Use deprecated hset for compatibility
        for key, value in node_info.items():
            await redis_client.hset(node_key, key, value)
        
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
        
        # Update node metrics individually for compatibility
        updates = {
            "status": node_data.get("status", "active"),
            "performance_score": str(node_data.get("performance_score", 0)),
            "cpu_usage": str(node_data.get("cpu_usage", 0)),
            "memory_usage": str(node_data.get("memory_usage", 0)),
            "jobs_completed": str(node_data.get("jobs_completed", 0)),
            "uptime": str(node_data.get("uptime", 0)),
            "last_seen": datetime.utcnow().isoformat()
        }
        
        for key, value in updates.items():
            await redis_client.hset(node_key, key, value)
        
        # Refresh expiration
        await redis_client.expire(node_key, 300)
        
        # Ensure in active set
        await redis_client.sadd("nodes:active", node_id)
        
        logger.info(f"💓 Heartbeat received from {node_id}")
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

EOF

echo "✅ Endpoints ajoutés au Gateway"

# Redémarrer le gateway
echo "🔄 Redémarrage du Gateway..."
docker compose restart gateway

# Attendre le redémarrage
echo "⏳ Attente du redémarrage (10 secondes)..."
sleep 10

# Tester les endpoints
echo "🧪 Test des nouveaux endpoints..."

# Test health
if curl -s http://localhost:8080/health >/dev/null 2>&1; then
    echo "✅ Health endpoint OK"
else
    echo "❌ Health endpoint KO"
fi

# Test nodes
if curl -s http://localhost:8080/nodes >/dev/null 2>&1; then
    echo "✅ Nodes endpoint OK"
else
    echo "❌ Nodes endpoint KO"
fi

echo ""
echo "🎯 Correction appliquée!"
echo "======================="
echo "✅ Endpoints ajoutés:"
echo "   - POST /nodes/register"
echo "   - POST /nodes/heartbeat" 
echo "   - GET /nodes"
echo "   - GET /nodes/{node_id}"
echo ""
echo "🔄 Redémarrez maintenant le nœud Mac:"
echo "   make mac-stop"
echo "   make mac-start"
echo "   make mac-logs"
echo ""
echo "Les erreurs 404 devraient disparaître! 🚀"
