#!/bin/bash

BACKUP_DIR="./backups"
MAX_AGE_DAYS=7

# Check if recent backup exists
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup_manifest_*.json 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backups found"
    exit 1
fi

# Check backup age
BACKUP_TIME=$(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || stat -f %m "$LATEST_BACKUP")
CURRENT_TIME=$(date +%s)
AGE_DAYS=$(( (CURRENT_TIME - BACKUP_TIME) / 86400 ))

if [ $AGE_DAYS -gt $MAX_AGE_DAYS ]; then
    echo "⚠️ Latest backup is $AGE_DAYS days old (max: $MAX_AGE_DAYS)"
    echo "📁 Latest backup: $(basename "$LATEST_BACKUP")"
    exit 1
else
    echo "✅ Backup is current ($AGE_DAYS days old)"
    echo "📁 Latest backup: $(basename "$LATEST_BACKUP")"
fi

# Check backup integrity
MANIFEST_TIMESTAMP=$(basename "$LATEST_BACKUP" .json | sed 's/backup_manifest_//')
DB_BACKUP="$BACKUP_DIR/database/moodle_db_${MANIFEST_TIMESTAMP}.sql.gz"
DATA_BACKUP="$BACKUP_DIR/moodle-data/moodle_data_${MANIFEST_TIMESTAMP}.tar.gz"

for file in "$DB_BACKUP" "$DATA_BACKUP"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing backup file: $(basename "$file")"
        exit 1
    fi
    
    # Test file integrity
    if [[ "$file" == *.gz ]]; then
        if ! gunzip -t "$file" 2>/dev/null; then
            echo "❌ Corrupted backup file: $(basename "$file")"
            exit 1
        fi
    fi
done

echo "✅ All backup files are intact"