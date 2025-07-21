# Minimal aggregator
import uvicorn
from fastapi import FastAPI

app = FastAPI(title="SynapseGrid Aggregator")

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "aggregator"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002)
