#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}${BLUE}Moodle 4.4.1 Auto-Installation${NC}"
echo -e "${BLUE}══════════════════════════════${NC}\n"

# Check .env exists
if [ ! -f .env ]; then
    echo -e "${RED}❌ No .env file found!${NC}"
    echo -e "${YELLOW}Please create .env file first:${NC}"
    echo -e "${CYAN}  cp .env.example .env${NC}"
    echo -e "${CYAN}  # Edit with your values${NC}"
    exit 1
fi

# Load environment
source .env

# Required variables check
REQUIRED_VARS="DB_NAME DB_USER DB_PASSWORD DB_ROOT_PASSWORD MOODLE_PORT"
for var in $REQUIRED_VARS; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}❌ Missing required variable: $var${NC}"
        echo -e "${YELLOW}Please check your .env file${NC}"
        exit 1
    fi
done

# Set defaults for optional variables
ADMIN_USER=${MOODLE_ADMIN_USER:-admin}
ADMIN_PASS=${MOODLE_ADMIN_PASSWORD:-Admin123!}
ADMIN_EMAIL=${MOODLE_ADMIN_EMAIL:-admin@example.com}
SITE_NAME=${MOODLE_SITE_NAME:-Learning Scorecard Development}

echo -e "${BOLD}Configuration Summary${NC}"
echo -e "Database:    ${DB_NAME}"
echo -e "Admin user:  ${ADMIN_USER}"
echo -e "URL:         http://localhost:${MOODLE_PORT}"
echo ""

# Pre-flight checks
echo -e "${BOLD}Pre-flight checks${NC}"

# Check container
printf "%-30s" "Container running"
if docker exec moodle_web echo 'ok' >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Container not running. Run setup first.${NC}"
    exit 1
fi

# Check Moodle files
printf "%-30s" "Moodle files"
if docker exec moodle_web test -f //var/www/html/version.php 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Moodle not installed. Run setup first.${NC}"
    exit 1
fi

# Check if already installed
printf "%-30s" "Existing installation"
if docker exec moodle_web test -f //var/www/html/config.php 2>/dev/null; then
    echo -e "${YELLOW}Found${NC}"
    echo -e "\n${YELLOW}⚠ Moodle appears to be already installed${NC}"
    echo -n "Continue anyway? This may cause issues (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -e "${GREEN}None${NC}"
fi

# Create config.php
echo -e "\n${BOLD}Creating configuration${NC}"
printf "%-30s" "config.php"

docker exec moodle_web bash -c "
cat > //var/www/html/config.php << 'EOF'
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = 'moodle_db';
\$CFG->dbname    = '${DB_NAME}';
\$CFG->dbuser    = '${DB_USER}';
\$CFG->dbpass    = '${DB_PASSWORD}';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array (
  'dbpersist' => 0,
  'dbport' => 3306,
  'dbsocket' => '',
  'dbcollation' => 'utf8mb4_unicode_ci',
);

\$CFG->wwwroot   = 'http://localhost:${MOODLE_PORT}';
\$CFG->dataroot  = '/var/www/moodledata';
\$CFG->admin     = 'admin';
\$CFG->directorypermissions = 0777;

// Development settings
\$CFG->debug = 32767;
\$CFG->debugdisplay = 1;

require_once(__DIR__ . '/lib/setup.php');
EOF

chown www-data:www-data //var/www/html/config.php
" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Run installation
echo -e "\n${BOLD}Installing database${NC}"
echo -e "${CYAN}This will take 1-2 minutes...${NC}"

printf "%-30s" "Database installation"

# Run the installation
docker exec moodle_web su -s //bin/bash www-data -c "
cd //var/www/html &&
php admin/cli/install_database.php \
  --agree-license \
  --fullname='${SITE_NAME}' \
  --shortname='LS' \
  --summary='Learning Scorecard Development' \
  --adminuser='${ADMIN_USER}' \
  --adminpass='${ADMIN_PASS}' \
  --adminemail='${ADMIN_EMAIL}'
"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Installation failed. Check $INSTALL_LOG${NC}"
    tail -20 "$INSTALL_LOG"
    exit 1
fi

# Set permissions
printf "%-30s" "Setting permissions"
docker exec moodle_web bash -c "
    chown -R www-data:www-data /var/www/html /var/www/moodledata &&
    chmod -R 755 /var/www/html
" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Verify installation
echo -e "\n${BOLD}Verification${NC}"

printf "%-30s" "Database tables"
TABLE_COUNT=$(docker exec moodle_db mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name LIKE 'mdl_%';" \
    -s 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ ($TABLE_COUNT tables)${NC}"
else
    echo -e "${RED}✗${NC}"
fi

printf "%-30s" "Admin user"
if docker exec moodle_db mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME \
    -e "SELECT username FROM mdl_user WHERE username='$ADMIN_USER'" 2>/dev/null | grep -q $ADMIN_USER; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

printf "%-30s" "Web access"
if curl -f -s --max-time 5 "http://localhost:$MOODLE_PORT" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ (may need a moment)${NC}"
fi

# Plugin check
printf "%-30s" "Plugin mount"
if docker exec moodle_web test -d //var/www/html/local/learning_scorecard; then
    echo -e "${GREEN}✓${NC}"
    
    # Trigger plugin installation if version.php exists
    if docker exec moodle_web test -f //var/www/html/local/learning_scorecard/version.php; then
        printf "%-30s" "Plugin upgrade"
        docker exec moodle_web su -s //bin/bash www-data -c "
            cd /var/www/html &&
            php admin/cli/upgrade.php --non-interactive
        " >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}⚠${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Success!
echo -e "\n${GREEN}${BOLD}✓ Installation Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BOLD}URL:${NC}         http://localhost:$MOODLE_PORT"
echo -e "${BOLD}Username:${NC}    $ADMIN_USER"
echo -e "${BOLD}Password:${NC}    $ADMIN_PASS"
echo -e "${BLUE}═══════════════════════════════════════${NC}"

echo -e "\n${CYAN}Your plugin is at: ./plugins/learning-scorecard-moodle/${NC}"
echo -e "${CYAN}Clear cache after changes: Site admin → Development → Purge caches${NC}"

# Cleanup
rm -f "$INSTALL_LOG" 2>/dev/null