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

echo -e "${BOLD}${BLUE}Learning Scorecard Plugin Update & Database Upgrade${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}\n"

# Check if we're in the right directory
if [ ! -f "version.php" ]; then
    echo -e "${RED}❌ Error: version.php not found in current directory${NC}"
    echo -e "${YELLOW}Please run this script from the plugin directory:${NC}"
    echo -e "${CYAN}  cd plugins/learning-scorecard-moodle${NC}"
    echo -e "${CYAN}  ../../scripts/update-plugin.sh${NC}"
    exit 1
fi

# Check if .env exists in the parent directory
if [ ! -f "../../.env" ]; then
    echo -e "${RED}❌ No .env file found in project root!${NC}"
    echo -e "${YELLOW}Please ensure .env file exists in the project root${NC}"
    exit 1
fi

# Load environment variables
source ../../.env

# Required variables check
REQUIRED_VARS="DB_NAME DB_USER DB_PASSWORD MOODLE_PORT"
for var in $REQUIRED_VARS; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}❌ Missing required variable: $var${NC}"
        echo -e "${YELLOW}Please check your .env file${NC}"
        exit 1
    fi
done

echo -e "${BOLD}Configuration${NC}"
echo -e "Database:    ${DB_NAME}"
echo -e "URL:         http://localhost:${MOODLE_PORT}"
echo ""

# Pre-flight checks
echo -e "${BOLD}Pre-flight checks${NC}"

# Check if containers are running
printf "%-40s" "Moodle container"
if docker exec moodle_web echo 'ok' >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Moodle container not running. Please start the environment first:${NC}"
    echo -e "${CYAN}  cd ../../ && docker-compose up -d${NC}"
    exit 1
fi

printf "%-40s" "Database container"
if docker exec moodle_db echo 'ok' >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Database container not running. Please start the environment first:${NC}"
    echo -e "${CYAN}  cd ../../ && docker-compose up -d${NC}"
    exit 1
fi

# Check if Moodle is installed
printf "%-40s" "Moodle installation"
if docker exec moodle_web test -f /var/www/html/config.php 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Moodle not installed. Please install Moodle first:${NC}"
    echo -e "${CYAN}  cd ../../ && ./scripts/auto-install-moodle.sh${NC}"
    exit 1
fi

# Check plugin mount
printf "%-40s" "Plugin mount"
if docker exec moodle_web test -d /var/www/html/local/learning_scorecard 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Plugin not mounted. Please check docker-compose.yml${NC}"
    exit 1
fi

# Get current plugin version
echo -e "\n${BOLD}Version Information${NC}"
CURRENT_VERSION=$(docker exec moodle_web php -r "
    if(file_exists('/var/www/html/local/learning_scorecard/version.php')) {
        require_once('/var/www/html/local/learning_scorecard/version.php');
        echo isset(\$plugin->version) ? \$plugin->version : 'unknown';
    } else {
        echo 'no-version-file';
    }
" 2>/dev/null || echo "error")

if [ "$CURRENT_VERSION" != "error" ] && [ "$CURRENT_VERSION" != "no-version-file" ]; then
    echo -e "Current plugin version: ${CYAN}$CURRENT_VERSION${NC}"
else
    echo -e "${YELLOW}⚠ Could not read current plugin version${NC}"
fi

# Check if plugin is installed in database
printf "%-40s" "Plugin DB status"
PLUGIN_INSTALLED=$(docker exec moodle_db mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME \
    -e "SELECT COUNT(*) FROM mdl_config_plugins WHERE plugin='local_learning_scorecard'" \
    -s 2>/dev/null || echo "0")

if [ "$PLUGIN_INSTALLED" -gt "0" ]; then
    DB_VERSION=$(docker exec moodle_db mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME \
        -e "SELECT value FROM mdl_config_plugins WHERE plugin='local_learning_scorecard' AND name='version'" \
        -s 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ (DB version: $DB_VERSION)${NC}"
else
    echo -e "${YELLOW}⚠ Not installed in database${NC}"
fi

# Update plugin files
echo -e "\n${BOLD}Updating plugin files${NC}"
printf "%-40s" "File permissions"
docker exec moodle_web bash -c "
    chown -R www-data:www-data /var/www/html/local/learning_scorecard &&
    chmod -R 755 /var/www/html/local/learning_scorecard
" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Clear Moodle caches
echo -e "\n${BOLD}Clearing caches${NC}"
printf "%-40s" "Purging all caches"
docker exec moodle_web su -s /bin/bash www-data -c "
    cd /var/www/html &&
    php admin/cli/purge_caches.php
" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Run database upgrade
echo -e "\n${BOLD}Running database upgrade${NC}"
printf "%-40s" "Database upgrade"

# Create temporary log file
UPGRADE_LOG="/tmp/moodle_upgrade_$$.log"

# Run the upgrade
docker exec moodle_web su -s /bin/bash www-data -c "
    cd /var/www/html &&
    php admin/cli/upgrade.php --non-interactive
" > "$UPGRADE_LOG" 2>&1

UPGRADE_STATUS=$?

if [ $UPGRADE_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
    
    # Check if there were any upgrades
    if grep -q "Upgrade completed successfully" "$UPGRADE_LOG"; then
        echo -e "${GREEN}   Plugin upgrade completed successfully${NC}"
    elif grep -q "Nothing to upgrade" "$UPGRADE_LOG"; then
        echo -e "${CYAN}   No upgrades needed${NC}"
    else
        echo -e "${CYAN}   Upgrade process completed${NC}"
    fi
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Upgrade failed. Check the log below:${NC}"
    tail -20 "$UPGRADE_LOG"
    rm -f "$UPGRADE_LOG"
    exit 1
fi

# Verify upgrade
echo -e "\n${BOLD}Verification${NC}"

# Check new plugin version in database
printf "%-40s" "Updated DB version"
NEW_DB_VERSION=$(docker exec moodle_db mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME \
    -e "SELECT value FROM mdl_config_plugins WHERE plugin='local_learning_scorecard' AND name='version'" \
    -s 2>/dev/null || echo "unknown")

if [ "$NEW_DB_VERSION" != "unknown" ] && [ "$NEW_DB_VERSION" != "" ]; then
    echo -e "${GREEN}✓ ($NEW_DB_VERSION)${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify${NC}"
fi

# Check plugin settings
printf "%-40s" "Plugin settings"
SETTINGS_COUNT=$(docker exec moodle_db mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME \
    -e "SELECT COUNT(*) FROM mdl_config_plugins WHERE plugin='local_learning_scorecard'" \
    -s 2>/dev/null || echo "0")

if [ "$SETTINGS_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ ($SETTINGS_COUNT settings)${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Test web access
printf "%-40s" "Web access"
if curl -f -s --max-time 5 "http://localhost:$MOODLE_PORT" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ (may need a moment)${NC}"
fi

# Check if plugin page is accessible
printf "%-40s" "Plugin page access"
if curl -f -s --max-time 5 "http://localhost:$MOODLE_PORT/local/learning_scorecard/" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ (check admin access)${NC}"
fi

# Final cache clear
echo -e "\n${BOLD}Final cleanup${NC}"
printf "%-40s" "Final cache clear"
docker exec moodle_web su -s /bin/bash www-data -c "
    cd /var/www/html &&
    php admin/cli/purge_caches.php
" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Success message
echo -e "\n${GREEN}${BOLD}✓ Plugin Update Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BOLD}Plugin URL:${NC}      http://localhost:$MOODLE_PORT/local/learning_scorecard/"
echo -e "${BOLD}Admin URL:${NC}       http://localhost:$MOODLE_PORT/admin/"
echo -e "${BOLD}Site URL:${NC}        http://localhost:$MOODLE_PORT/"

if [ "$CURRENT_VERSION" != "$NEW_DB_VERSION" ] && [ "$NEW_DB_VERSION" != "unknown" ]; then
    echo -e "${BOLD}Version:${NC}         $CURRENT_VERSION → $NEW_DB_VERSION"
fi

echo -e "${BLUE}═══════════════════════════════════════${NC}"

echo -e "\n${CYAN}Next steps:${NC}"
echo -e "${CYAN}• Visit the plugin page to verify functionality${NC}"
echo -e "${CYAN}• Check Site Administration → Plugins → Local plugins${NC}"
echo -e "${CYAN}• Test plugin features to ensure they work correctly${NC}"

echo -e "\n${YELLOW}Note:${NC}"
echo -e "${YELLOW}• Changes to your plugin files are immediately reflected${NC}"
echo -e "${YELLOW}• Database changes require running this script${NC}"
echo -e "${YELLOW}• Clear browser cache if you experience issues${NC}"

# Cleanup
rm -f "$UPGRADE_LOG" 2>/dev/null

echo -e "\n${GREEN}Plugin update completed successfully!${NC}"
