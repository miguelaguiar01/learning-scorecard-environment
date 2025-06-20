#!/bin/bash
# scripts/build-and-push.sh
set -e

# Configuration
export GITHUB_USERNAME=miguelaguiar01
REGISTRY="ghcr.io"
USERNAME="${GITHUB_USERNAME:-$(git config user.name)}"
REPO_NAME="learning-scorecard-environment"
IMAGE_NAME="${USERNAME}/${REPO_NAME}"
TAG="${1:-latest}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}${BLUE}Building and Pushing Learning Scorecard Environment${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}\n"

# Check prerequisites
echo -e "${BOLD}Prerequisites${NC}"
printf "%-40s" "Docker"
if command -v docker >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Docker not installed${NC}"
    exit 1
fi

printf "%-40s" "Git repository"
if git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Must be run from git repository${NC}"
    exit 1
fi

printf "%-40s" "Plugin directory"
if [ -d "./plugins/learning-scorecard-moodle" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Plugin directory not found: ./plugins/learning-scorecard-moodle${NC}"
    exit 1
fi

printf "%-40s" "Dockerfile"
if [ -f "./Dockerfile" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Dockerfile not found in root directory${NC}"
    exit 1
fi

printf "%-40s" "Config files"
if [ -f "./configs/php.ini" ] && [ -f "./configs/apache-default.conf" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Config files not found in ./configs/${NC}"
    exit 1
fi

# Get plugin version
PLUGIN_VERSION="unknown"
if [ -f "./plugins/learning-scorecard-moodle/version.php" ]; then
    PLUGIN_VERSION=$(grep '$plugin->version' ./plugins/learning-scorecard-moodle/version.php | grep -o '[0-9]*' | head -1)
fi

# Set build metadata
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
VCS_REF=$(git rev-parse --short HEAD)

echo -e "\n${BOLD}Build Information${NC}"
echo -e "Registry:        $REGISTRY"
echo -e "Image:           $IMAGE_NAME:$TAG"
echo -e "Plugin version:  $PLUGIN_VERSION"
echo -e "Git commit:      $VCS_REF"
echo -e "Build date:      $BUILD_DATE"

# Check GHCR authentication
echo -e "\n${BOLD}Authentication${NC}"
printf "%-40s" "GHCR login status"
if docker system info 2>/dev/null | grep -q "Username:" || grep -q "ghcr.io" ~/.docker/config.json 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "\n${YELLOW}Please login to GHCR first:${NC}"
    echo -e "${CYAN}echo \$GITHUB_TOKEN | docker login ghcr.io -u $USERNAME --password-stdin${NC}"
    echo -e "\n${YELLOW}Or set GITHUB_TOKEN environment variable and run:${NC}"
    echo -e "${CYAN}docker login ghcr.io -u $USERNAME --password-stdin <<< \$GITHUB_TOKEN${NC}"
    exit 1
fi

# Build the image
echo -e "\n${BOLD}Building Image${NC}"
printf "%-40s" "Building Docker image"

PROCESS_ID=$$
docker build \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VCS_REF="$VCS_REF" \
    --build-arg PLUGIN_VERSION="$PLUGIN_VERSION" \
    -t $REGISTRY/$IMAGE_NAME:$TAG \
    . > /tmp/docker_build_${PROCESS_ID}.log 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Build failed. Check log: /tmp/docker_build_${PROCESS_ID}.log${NC}"
    tail -20 /tmp/docker_build_${PROCESS_ID}.log
    exit 1
fi

# Tag as latest if not already
if [ "$TAG" != "latest" ]; then
    printf "%-40s" "Tagging as latest"
    docker tag $REGISTRY/$IMAGE_NAME:$TAG $REGISTRY/$IMAGE_NAME:latest
    echo -e "${GREEN}✓${NC}"
fi

# Push to registry
echo -e "\n${BOLD}Pushing to Registry${NC}"
printf "%-40s" "Pushing $TAG"
docker push $REGISTRY/$IMAGE_NAME:$TAG > /tmp/docker_push_${PROCESS_ID}.log 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Push failed. Check log: /tmp/docker_push_${PROCESS_ID}.log${NC}"
    tail -20 /tmp/docker_push_${PROCESS_ID}.log
    exit 1
fi

if [ "$TAG" != "latest" ]; then
    printf "%-40s" "Pushing latest"
    docker push $REGISTRY/$IMAGE_NAME:latest > /tmp/docker_push_latest_${PROCESS_ID}.log 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}Push latest failed. Check log: /tmp/docker_push_latest_${PROCESS_ID}.log${NC}"
    fi
fi

# Success summary
echo -e "\n${GREEN}${BOLD}✓ Build and Push Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}Image:${NC}           $REGISTRY/$IMAGE_NAME:$TAG"
echo -e "${BOLD}Plugin:${NC}          learning-scorecard-moodle v$PLUGIN_VERSION"
echo -e "${BOLD}Size:${NC}            $(docker images --format "{{.Size}}" $REGISTRY/$IMAGE_NAME:$TAG)"
echo -e "${BOLD}Layers:${NC}          $(docker history --quiet $REGISTRY/$IMAGE_NAME:$TAG | wc -l) layers"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

echo -e "\n${CYAN}Usage:${NC}"
echo -e "${CYAN}docker pull $REGISTRY/$IMAGE_NAME:$TAG${NC}"
echo -e "${CYAN}docker run -p 8080:80 $REGISTRY/$IMAGE_NAME:$TAG${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "${YELLOW}• Update docker-compose.yml to use the new image${NC}"
echo -e "${YELLOW}• Create production deployment configuration${NC}"
echo -e "${YELLOW}• Set up automated builds with GitHub Actions${NC}"

# Cleanup
rm -f /tmp/docker_build_${PROCESS_ID}.log /tmp/docker_push_${PROCESS_ID}.log /tmp/docker_push_latest_${PROCESS_ID}.log 2>/dev/null