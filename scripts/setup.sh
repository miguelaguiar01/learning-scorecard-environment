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

# Spinner function
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Task runner
run_task() {
    local task_name=$1
    local task_command=$2
    
    printf "%-40s" "$task_name"
    
    eval "$task_command" > /tmp/moodle_setup_$$.log 2>&1 &
    local pid=$!
    
    spinner $pid
    wait $pid
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}Error: Check /tmp/moodle_setup_$$.log for details${NC}"
        exit 1
    fi
}

# Safe task runner (warns instead of exits)
run_task_safe() {
    local task_name=$1
    local task_command=$2
    
    printf "%-40s" "$task_name"
    
    eval "$task_command" > /tmp/moodle_setup_$$.log 2>&1 &
    local pid=$!
    
    spinner $pid
    wait $pid
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}⚠${NC}"
        return 1
    fi
    return 0
}

echo -e "${BOLD}${BLUE}Learning Scorecard - Moodle 4.4.1 Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}\n"

# Prerequisites check
echo -e "${BOLD}Checking prerequisites${NC}"
run_task "Docker" "docker info"
run_task "Docker Compose" "command -v docker-compose"

# Check plugin exists
echo -e "\n${BOLD}Checking your plugin${NC}"
printf "%-40s" "Plugin directory"
if [ ! -d "./plugins/learning-scorecard-moodle" ]; then
    echo -e "${RED}✗${NC}"
    echo -e "${RED}ERROR: Plugin directory not found!${NC}"
    echo -e "${YELLOW}Expected location: ./plugins/learning-scorecard-moodle/${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC}"

# Environment setup
echo -e "\n${BOLD}Environment configuration${NC}"
printf "%-40s" "Environment file"
if [ ! -f .env ]; then
    echo -e "${YELLOW}Not found${NC}"
    echo -e "\n${YELLOW}No .env file found. Creating .env.example${NC}"
    cat > .env.example << 'ENVFILE'
# Copy this file to .env and adjust values as needed
# DO NOT commit .env to git!

# Database Configuration
DB_ROOT_PASSWORD=root
DB_NAME=moodle
DB_USER=moodle
DB_PASSWORD=moodle
DB_PORT=3306

# Moodle Configuration
MOODLE_PORT=8080
MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASSWORD=Admin123!
MOODLE_ADMIN_EMAIL=admin@example.com
MOODLE_SITE_NAME=Learning Scorecard Development
ENVFILE
    
    echo -e "${CYAN}Please create .env file:${NC}"
    echo -e "${CYAN}  cp .env.example .env${NC}"
    echo -e "${CYAN}  # Edit .env with your values${NC}"
    echo -e "${CYAN}  # Then run this script again${NC}"
    exit 1
else
    echo -e "${GREEN}✓${NC}"
fi

source .env 2>/dev/null || true

# Create scripts directory
run_task "Creating scripts directory" "mkdir -p scripts"

# Add .gitignore if needed
if [ ! -f .gitignore ] || ! grep -q "^.env$" .gitignore 2>/dev/null; then
    echo -e "\n${BOLD}Security configuration${NC}"
    run_task "Adding .env to .gitignore" "echo -e '\n# Environment files\n.env\nmoodle-config/' >> .gitignore"
fi

# Cleanup
echo -e "\n${BOLD}Cleaning Docker environment${NC}"
echo -e "${YELLOW}Note: This will only clean Docker volumes, not your files${NC}"
run_task "Stopping containers" "docker-compose down -v --remove-orphans"
run_task "Cleanup" "docker system prune -f"

# Start containers
echo -e "\n${BOLD}Starting services${NC}"
run_task "Database" "docker-compose up -d moodle_db"
run_task "Web server" "docker-compose up -d moodle_web"

# Wait for database
echo -e "\n${BOLD}Waiting for database${NC}"
printf "%-40s" "Database startup"
timeout=30
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker exec moodle_db mysqladmin ping -u root -p"${DB_ROOT_PASSWORD}" --silent 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        break
    fi
    sleep 1
    elapsed=$((elapsed+1))
done

if [ $elapsed -ge $timeout ]; then
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Install components
echo -e "\n${BOLD}Installing components${NC}"
run_task "System packages" "
    docker exec moodle_web apt-get update -qq &&
    docker exec moodle_web apt-get install -y -qq \
        libpng-dev libjpeg-dev libfreetype6-dev \
        libzip-dev libicu-dev libxml2-dev \
        libcurl4-openssl-dev libssl-dev \
        libldap2-dev unzip wget curl
"

run_task "PHP extensions" "
    docker exec moodle_web bash -c '
        docker-php-ext-configure gd --with-freetype --with-jpeg >/dev/null 2>&1 &&
        docker-php-ext-install -j\$(nproc) \
            gd zip intl mysqli pdo_mysql \
            curl xml soap opcache exif >/dev/null 2>&1
    '
"

# Save plugin folders
echo -e "\n${BOLD}Moving Plugin Folder${NC}"
run_task "Moving Plugin: learning-scorecard" "
    docker exec moodle_web bash -c '
        cd /var/www/html/ &&
        mv local //tmp
    '
"

# Download Moodle
echo -e "\n${BOLD}Downloading Moodle 4.4.1${NC}"
run_task "Downloading Moodle" "
    docker exec moodle_web bash -c '
        cd /var/www/html &&
        rm -rf * .[^.]* 2>/dev/null || true &&
        wget -q https://github.com/moodle/moodle/archive/v4.4.1.tar.gz &&
        tar -xzf v4.4.1.tar.gz --strip-components=1 &&
        rm v4.4.1.tar.gz &&
        mkdir -p /var/www/moodledata &&
        chown -R www-data:www-data /var/www/html /var/www/moodledata &&
        chmod -R 777 /var/www/moodledata
    '
"

run_task "PHP configuration" "
    docker exec moodle_web bash -c '
        cat > /usr/local/etc/php/conf.d/moodle.ini << EOF
        memory_limit = 512M
        max_execution_time = 300
        max_input_vars = 5000
        upload_max_filesize = 100M
        post_max_size = 100M
        EOF
    '
"

# Apache configuration - more robust handling
echo -e "\n${BOLD}Configuring Apache${NC}"
printf "%-40s" "Apache modules"

# Enable required modules
docker exec moodle_web bash -c '
    a2enmod rewrite headers expires >/dev/null 2>&1
' 

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Create proper Apache config
printf "%-40s" "Apache configuration"
docker exec moodle_web bash -c '
cat > /etc/apache2/sites-available/000-default.conf << "EOF"
<VirtualHost *:80>
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
'

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Restart Apache using docker-compose (more reliable)
printf "%-40s" "Restarting web server"
docker-compose restart moodle_web >/dev/null 2>&1 &
RESTART_PID=$!

# Show spinner while restarting
spinner $RESTART_PID
wait $RESTART_PID

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Wait for web server to be ready
echo -e "\n${BOLD}Waiting for web server${NC}"
printf "%-40s" "Web server startup"
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if curl -f -s --max-time 2 "http://localhost:${MOODLE_PORT:-8080}" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        break
    fi
    sleep 2
    elapsed=$((elapsed+2))
done

if [ $elapsed -ge $timeout ]; then
    echo -e "${YELLOW}⚠ Slow startup${NC}"
fi



# Verify plugin mount
echo -e "\n${BOLD}Verifying plugin mount${NC}"
printf "%-40s" "Plugin mount"
if docker exec moodle_web test -d //var/www/html/local/learning_scorecard; then
    echo -e "${GREEN}✓${NC}"
    
    FILE_COUNT=$(docker exec moodle_web find //var/www/html/local/learning_scorecard -type f 2>/dev/null | wc -l)
    echo -e "${GREEN}   Plugin files: $FILE_COUNT files mounted${NC}"
else
    echo -e "${YELLOW}⚠ Mount pending${NC}"
fi

# Final verification
echo -e "\n${BOLD}Final verification${NC}"
run_task_safe "Moodle files" "docker exec moodle_web test -f //var/www/html/version.php"
run_task_safe "Web accessibility" "curl -f -s --max-time 5 http://localhost:${MOODLE_PORT:-8080}"

# Get Moodle version if possible
MOODLE_VERSION=$(docker exec moodle_web php -r "
    if(file_exists('//var/www/html/version.php')) {
        require_once('//var/www/html/version.php');
        echo \$version;
    }
" 2>/dev/null || echo "Unknown")

# Summary
echo -e "\n${GREEN}${BOLD}✓ Setup Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BOLD}Moodle URL:${NC}     http://localhost:${MOODLE_PORT:-8080}"
echo -e "${BOLD}Version:${NC}        $MOODLE_VERSION"
echo -e "${BOLD}Your Plugin:${NC}    ./plugins/learning-scorecard-moodle/"
echo -e "${BOLD}Container Path:${NC} /var/www/html/local/learning_scorecard/"
echo -e "${BLUE}═══════════════════════════════════════${NC}"

echo -e "\n${CYAN}Next steps:${NC}"
echo -e "${CYAN}1. Visit http://localhost:${MOODLE_PORT:-8080} to install Moodle${NC}"
echo -e "${CYAN}2. Or run: ./scripts/auto-install-moodle.sh${NC}"

echo -e "\n${YELLOW}⚠ Important:${NC}"
echo -e "${YELLOW}• Your plugin is safe at: ./plugins/learning-scorecard-moodle/${NC}"
echo -e "${YELLOW}• Never commit .env to git${NC}"

# Cleanup
rm -f /tmp/moodle_setup_$$.log 2>/dev/null