#!/bin/bash
set -e

# Load environment variables
source .env

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="./backups"
DB_BACKUP_DIR="$BACKUP_DIR/moodle_db"
MOODLE_BACKUP_DIR="$BACKUP_DIR/moodle_data"

# Create backup directories
mkdir -p "$DB_BACKUP_DIR" "$MOODLE_BACKUP_DIR"

echo "🔄 Starting backup process at $(date)"

# Backup database
echo "📊 Backing up database..."
docker exec moodle_db mysqldump \
  -u root \
  -p"$DB_ROOT_PASSWORD" \
  --single-transaction \
  --routines \
  --triggers \
  --add-drop-database \
  --databases "$DB_NAME" > "$DB_BACKUP_DIR/moodle_db_$TIMESTAMP.sql"

# Compress database backup
gzip "$DB_BACKUP_DIR/moodle_db_$TIMESTAMP.sql"

# Backup Moodle data (excluding cache and temp files)
echo "📁 Backing up Moodle data..."
docker run --rm \
  -v learning_scorecard_environment_moodle_data:/source:ro \
  -v "$(pwd)/$MOODLE_BACKUP_DIR":/backup \
  alpine:latest \
  sh -c "cd /source && tar czf /backup/moodle_data_$TIMESTAMP.tar.gz \
    --exclude='cache/*' \
    --exclude='localcache/*' \
    --exclude='temp/*' \
    --exclude='trashdir/*' \
    ."

# Backup Moodle config
echo "⚙️ Backing up Moodle configuration..."
docker run --rm \
  -v learning_scorecard_environment_moodle_config:/source:ro \
  -v "$(pwd)/$MOODLE_BACKUP_DIR":/backup \
  alpine:latest \
  sh -c "cd /source && tar czf /backup/moodle_config_$TIMESTAMP.tar.gz ."

# Create backup manifest
echo "📋 Creating backup manifest..."
cat > "$BACKUP_DIR/backup_manifest_$TIMESTAMP.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "date": "$(date -Iseconds)",
  "database_backup": "database/moodle_db_$TIMESTAMP.sql.gz",
  "moodle_data_backup": "moodle-data/moodle_data_$TIMESTAMP.tar.gz",
  "moodle_config_backup": "moodle-data/moodle_config_$TIMESTAMP.tar.gz",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "docker_images": {
    "moodle": "$(docker inspect --format='{{.Config.Image}}' moodle_web 2>/dev/null || echo 'unknown')",
    "mariadb": "$(docker inspect --format='{{.Config.Image}}' moodle_db 2>/dev/null || echo 'unknown')"
  }
}
EOF

# Cleanup old backups
echo "🧹 Cleaning up old backups..."
find "$DB_BACKUP_DIR" -name "*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS:-30} -delete
find "$MOODLE_BACKUP_DIR" -name "*.tar.gz" -mtime +${BACKUP_RETENTION_DAYS:-30} -delete
find "$BACKUP_DIR" -name "backup_manifest_*.json" -mtime +${BACKUP_RETENTION_DAYS:-30} -delete

echo "✅ Backup completed successfully at $(date)"
echo "📁 Backup files:"
echo "   - Database: $DB_BACKUP_DIR/moodle_db_$TIMESTAMP.sql.gz"
echo "   - Moodle Data: $MOODLE_BACKUP_DIR/moodle_data_$TIMESTAMP.tar.gz"
echo "   - Configuration: $MOODLE_BACKUP_DIR/moodle_config_$TIMESTAMP.tar.gz"
echo "   - Manifest: $BACKUP_DIR/backup_manifest_$TIMESTAMP.json"