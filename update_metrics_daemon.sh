#!/bin/bash
# Lancer l'updater de métriques en arrière-plan
nohup docker exec synapse_redis redis-cli --eval - << 'SCRIPT' > /tmp/metrics_updater.log 2>&1 &
while true do
  redis.call('SET', 'metrics:last_update', os.time())
  redis.call('EXPIRE', 'metrics:last_update', 60)
end
SCRIPT
echo "Metrics updater lancé en arrière-plan (PID: $!)"
