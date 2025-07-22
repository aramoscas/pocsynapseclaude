#!/usr/bin/env python3
"""Patch pour ajouter les endpoints manquants au Gateway"""

import os

# Lire le fichier gateway actuel
gateway_file = "services/gateway/main.py"

# Trouver où insérer les nouveaux endpoints (avant le if __name__ == "__main__")
with open(gateway_file, 'r') as f:
    lines = f.readlines()

# Trouver la ligne avant main
insert_index = -1
for i, line in enumerate(lines):
    if 'if __name__ == "__main__"' in line:
        insert_index = i
        break

if insert_index == -1:
    print("❌ Impossible de trouver le point d'insertion")
    exit(1)

# Code des endpoints manquants
new_endpoints = '''
@app.post("/nodes/register")
async def register_node(node_data: dict):
    """Enregistrer un nouveau node"""
    node_id = node_data.get("node_id")
    node_type = node_data.get("node_type", "docker")
    region = node_data.get("region", "eu-west-1")
    
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Enregistrer dans Redis
        node_key = f"node:{node_id}:{region}:info"
        node_info = {
            "node_id": node_id,
            "node_type": node_type,
            "region": region,
            "status": "online",
            "last_seen": datetime.utcnow().isoformat(),
            "capabilities": json.dumps(node_data.get("capabilities", {})),
            "max_concurrent": str(node_data.get("max_concurrent", 1))
        }
        
        # Utiliser le wrapper async pour Redis
        for key, value in node_info.items():
            await redis_async(redis_client.hset, node_key, key, value)
        await redis_async(redis_client.expire, node_key, 60)
        
        # Enregistrer dans PostgreSQL
        try:
            with pg_conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO nodes (node_id, node_type, region, status)
                    VALUES (%s, %s, %s, 'online')
                    ON CONFLICT (node_id) DO UPDATE
                    SET status = 'online', last_seen = CURRENT_TIMESTAMP
                """, (node_id, node_type, region))
                pg_conn.commit()
        except Exception as e:
            logger.warning(f"Erreur DB lors de l'enregistrement du node: {e}")
        
        logger.info(f"✅ Node {node_id} enregistré ({node_type} dans {region})")
        return {"status": "registered", "node_id": node_id}
        
    except Exception as e:
        logger.error(f"❌ Erreur enregistrement node: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/metrics")
async def get_metrics():
    """Endpoint de métriques pour Prometheus"""
    try:
        # Récupérer les métriques depuis Redis et PostgreSQL
        metrics = []
        
        # Métrique: jobs en attente
        queue_length = await redis_async(redis_client.llen, "jobs:queue:eu-west-1")
        metrics.append(f"synapsegrid_jobs_queued{{region=\\"eu-west-1\\"}} {queue_length}")
        
        # Métrique: nodes actifs
        try:
            with pg_conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM nodes WHERE status = 'online'")
                active_nodes = cur.fetchone()['count']
                metrics.append(f"synapsegrid_nodes_active {active_nodes}")
                
                cur.execute("SELECT COUNT(*) FROM jobs WHERE status = 'completed' AND completed_at > NOW() - INTERVAL '1 minute'")
                jobs_per_minute = cur.fetchone()['count']
                metrics.append(f"synapsegrid_jobs_completed_per_minute {jobs_per_minute}")
        except:
            pass
        
        # Métrique: santé du service
        metrics.append("synapsegrid_gateway_up 1")
        
        return "\\n".join(metrics)
        
    except Exception as e:
        logger.error(f"Erreur metrics: {e}")
        return "synapsegrid_gateway_up 0"

@app.get("/nodes")
async def list_nodes():
    """Lister tous les nodes actifs"""
    try:
        nodes = []
        
        # Récupérer depuis Redis
        pattern = "node:*:*:info"
        keys = []
        cursor = 0
        while True:
            cursor, batch_keys = await redis_async(redis_client.scan, cursor, match=pattern, count=100)
            keys.extend(batch_keys)
            if cursor == 0:
                break
        
        for key in keys:
            node_info = await redis_async(redis_client.hgetall, key)
            if node_info:
                nodes.append({
                    "node_id": node_info.get("node_id"),
                    "node_type": node_info.get("node_type"),
                    "region": node_info.get("region"),
                    "status": node_info.get("status"),
                    "last_seen": node_info.get("last_seen")
                })
        
        return {"nodes": nodes, "count": len(nodes)}
        
    except Exception as e:
        logger.error(f"Erreur list nodes: {e}")
        return {"nodes": [], "count": 0}

'''

# Insérer les nouveaux endpoints
lines.insert(insert_index, new_endpoints)

# Écrire le fichier mis à jour
with open(gateway_file, 'w') as f:
    f.writelines(lines)

print("✅ Endpoints ajoutés au Gateway:")
print("   - POST /nodes/register")
print("   - GET /metrics")
print("   - GET /nodes")
