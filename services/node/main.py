#!/usr/bin/env python3
"""
SynapseGrid Node Service
Simple node implementation
"""

import asyncio
import json
import logging
import time
import os
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def main():
    """Main node function"""
    node_id = os.getenv('NODE_ID', 'docker-node-001')
    region = os.getenv('REGION', 'eu-west-1')
    
    logger.info(f"🖥️ Starting SynapseGrid Node {node_id}")
    
    # Simple heartbeat loop
    while True:
        try:
            logger.info(f"Node {node_id} heartbeat - Status: active")
            await asyncio.sleep(30)
        except KeyboardInterrupt:
            logger.info(f"Node {node_id} shutting down")
            break
        except Exception as e:
            logger.error(f"Node {node_id} error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())
