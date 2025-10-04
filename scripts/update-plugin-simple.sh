#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}${BLUE}Learning Scorecard Plugin Update${NC}"
echo -e "${BLUE}═══════════════════════════════${NC}\n"

# Check if we're in the project root
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ Error: Not in project root directory${NC}"
    echo -e "${YELLOW}Please run this script from the learning-scorecard-environment directory${NC}"
    exit 1
fi

# Check if plugin exists
if [ ! -f "plugins/learning-scorecard-moodle/version.php" ]; then
    echo -e "${RED}❌ Error: Plugin not found${NC}"
    echo -e "${YELLOW}Expected location: plugins/learning-scorecard-moodle/version.php${NC}"
    exit 1
fi

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ No .env file found!${NC}"
    echo -e "${YELLOW}Please create .env file first:${NC}"
    echo -e "${CYAN}  cp .env.example .env${NC}"
    exit 1
fi

# Load environment variables
source .env

# Check if containers are running
echo -e "${BOLD}Checking environment...${NC}"
if ! docker exec moodle_web echo 'ok' >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Starting containers...${NC}"
    docker-compose up -d
    echo -e "${GREEN}✓ Containers started${NC}"
fi

# Run the main update script
echo -e "\n${BOLD}Running plugin update...${NC}"
cd plugins/learning-scorecard-moodle
../../scripts/update-plugin.sh

echo -e "\n${GREEN}${BOLD}✓ Plugin update completed!${NC}"
echo -e "${CYAN}You can now access your updated plugin at:${NC}"
echo -e "${CYAN}http://localhost:${MOODLE_PORT:-8080}/local/learning_scorecard/${NC}"
