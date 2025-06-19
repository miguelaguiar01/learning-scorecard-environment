#!/bin/bash
set -e

# Load environment variables
source .env

# Function to show usage
usage() {
    echo "Usage: $0 <backup_timestamp>"
    echo "Example: $0 20251219_143022"
    echo ""
    echo "Available backups:"
    ls -la backups/backup_manifest_*.json 2>/dev/null | awk '{print $9}' | sed 's/.*backup_manifest_\(.*\)\.json/\1/' || echo "No backups found"
    exit 1
}

# Check if timestamp provided
if [ -z "$1" ]; then
    usage
fi

TIMESTAMP="$1"
BACKUP_DIR="./backups"

# Verify backup files exist
DB_BACKUP="$BACKUP_DIR/database/moodle_db_$TIMESTAMP.sql.gz"
MOODLE_DATA_BACKUP="$BACKUP_DIR/moodle-data/moodle_data_$TIMESTAMP.tar.gz"
MOODLE_CONFIG_BACKUP="$BACKUP_DIR/moodle-data/moodle_config_$TIMESTAMP.tar.gz"
MANIFEST="$BACKUP_DIR/backup_manifest_$TIMESTAMP.json"

for file in "$DB_BACKUP" "$MOODLE_DATA_BACKUP" "$MOODLE_CONFIG_BACKUP" "$MANIFEST"; do
    if [ ! -f "$file" ]; then
        echo "❌ Backup file not found: $file"
        exit 1
    fi
done

echo "🔄 Starting restore process for backup: $TIMESTAMP"

# Stop containers
echo "⏹️ Stopping containers..."
docker-compose down

# Remove existing volumes
echo "🗑️ Removing existing volumes..."
docker volume rm -f learning_scorecard_environment_moodle_data learning_scorecard_environment_moodle_config learning_scorecard_environment_db_data 2>/dev/null || true

# Start database container only
echo "🏃 Starting database container..."
docker-compose up -d moodle_db

# Wait for database to be ready
echo "⏳ Waiting for database to initialize..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker exec moodle_db mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "❌ Database failed to start within 60 seconds"
    exit 1
fi

# Restore database
echo "📊 Restoring database..."
gunzip -c "$DB_BACKUP" | docker exec -i moodle_db mysql -u root -p"$DB_ROOT_PASSWORD"

# Restore Moodle data
echo "📁 Restoring Moodle data..."
docker run --rm \
  -v learning_scorecard_environment_moodle_data:/target \
  -v "$(pwd)/$BACKUP_DIR/moodle-data":/backup:ro \
  alpine:latest \
  sh -c "cd /target && tar xzf /backup/moodle_data_$TIMESTAMP.tar.gz"

# Restore Moodle config
echo "⚙️ Restoring Moodle configuration..."
docker run --rm \
  -v learning_scorecard_environment_moodle_config:/target \
  -v "$(pwd)/$BACKUP_DIR/moodle-data":/backup:ro \
  alpine:latest \
  sh -c "cd /target && tar xzf /backup/moodle_config_$TIMESTAMP.tar.gz"

# Start all containers
echo "🚀 Starting all containers..."
docker-compose up -d

# Wait for Moodle to be ready
echo "⏳ Waiting for Moodle to be ready..."
timeout=120
while [ $timeout -gt 0 ]; do
    if curl -f http://localhost:${MOODLE_PORT:-8080}/login/index.php >/dev/null 2>&1; then
        break
    fi
    sleep 5
    timeout=$((timeout-5))
done

if [ $timeout -le 0 ]; then
    echo "⚠️ Moodle may not be fully ready yet, but restore completed"
else
    echo "✅ Moodle is ready!"
fi

echo "✅ Restore completed successfully!"
echo "🌐 Access Moodle at: http://localhost:${MOODLE_PORT:-8080}"
echo "👤 Admin user: $MOODLE_ADMIN_USER"
echo "📋 Backup manifest: $MANIFEST"