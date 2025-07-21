.PHONY: build start stop logs clean test

# Use the M2 compose file
COMPOSE_FILE = docker-compose.m2.yml

build:
	docker-compose -f $(COMPOSE_FILE) build --no-cache

start:
	docker-compose -f $(COMPOSE_FILE) up -d

stop:
	docker-compose -f $(COMPOSE_FILE) down

logs:
	docker-compose -f $(COMPOSE_FILE) logs -f

clean:
	docker-compose -f $(COMPOSE_FILE) down -v
	docker system prune -af

test:
	@echo "Testing API health..."
	@curl -s http://localhost:8080/health | jq . || echo "API not ready"

status:
	docker-compose -f $(COMPOSE_FILE) ps
