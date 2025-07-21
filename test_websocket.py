#!/usr/bin/env python3
"""Test WebSocket connection to the gateway"""

import asyncio
import json
import websockets

async def test_websocket():
    uri = "ws://localhost:8080/ws"
    
    try:
        async with websockets.connect(uri) as websocket:
            print("✅ Connected to WebSocket")
            
            # Subscribe to channels
            await websocket.send(json.dumps({
                "type": "subscribe",
                "channels": ["nodes", "jobs", "metrics"]
            }))
            
            # Listen for messages
            print("Listening for messages...")
            async for message in websocket:
                data = json.loads(message)
                print(f"Received: {data['type']}")
                
                if data['type'] == 'metrics_update':
                    print(f"Metrics: {data['payload']}")
                    
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_websocket())
