# SynapseGrid POC - "Uber of AI Compute"

🚀 **Decentralized AI Infrastructure Network**

## Quick Start

```bash
# 1. Setup
make setup

# 2. Generate protobuf files (optional)
make proto

# 3. Start services
make start

# 4. Test API
make test

# 5. Submit a job
make submit-job
```

## Services & Ports

- **Gateway**: http://localhost:8080 (API)
- **Dashboard**: http://localhost:3000
- **Grafana**: http://localhost:3001 (admin/admin123)
- **Prometheus**: http://localhost:9090

## Architecture

```
Gateway (8080) ←→ Dispatcher ←→ Nodes
    ↓                ↓           ↓
PostgreSQL     Redis Cache   Aggregator
```

## Commands

- `make start` - Start all services
- `make stop` - Stop services  
- `make logs` - View logs
- `make test` - Run API tests
- `make clean` - Clean up

## API Example

```bash
curl -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-Client-ID: my-client" \
  -d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}}'
```

## Development

Each service can be developed independently:

```bash
cd services/gateway
python main.py
```

---
**SynapseGrid - Democratizing AI Infrastructure** 🧠⚡
