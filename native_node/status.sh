#!/bin/bash
if pgrep -f "mac_m2_node.py" > /dev/null; then
    echo "✅ Mac M2 node is running (PID: $(pgrep -f mac_m2_node.py))"
else
    echo "❌ Mac M2 node is not running"
fi
