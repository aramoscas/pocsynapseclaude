#!/bin/bash
# build_services.sh - Build des services avec gestion d'erreurs

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔨 Build des services SynapseGrid${NC}"
echo ""

# Activer BuildKit pour de meilleures performances
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Build chaque service individuellement pour mieux gérer les erreurs
for service in gateway dispatcher aggregator node; do
    echo -e "${YELLOW}Building $service...${NC}"
    
    if docker-compose -f docker-compose.yml -f docker-compose.build.yml build --no-cache $service; then
        echo -e "${GREEN}✅ $service built successfully${NC}"
    else
        echo -e "${RED}❌ Failed to build $service${NC}"
        echo "Trying alternative build method..."
        
        # Méthode alternative avec docker build direct
        docker build --no-cache -t synapsegrid/$service:latest ./services/$service/
    fi
    echo ""
done

# Vérifier les images
echo -e "${YELLOW}📋 Images créées:${NC}"
docker images | grep synapsegrid

echo ""
echo -e "${GREEN}✅ Build terminé!${NC}"
