# Learning Scorecard Environment - Backup & Restore Guide

Comprehensive guide for backing up and restoring your Learning Scorecard Environment across different machines and scenarios.

# 🎯 Overview

This backup system provides:

- **Complete Environment Backup**: Database, files, configurations
- **Cross-Platform Compatibility**: Works on Windows, macOS, Linux
- **Automated Scheduling**: Set-and-forget backup automation
- **Version Control Integration**: Track backup history with Git
- **Disaster Recovery**: Full environment restoration capabilities

# 📦 What Gets Backed Up

## Database Backup

- **Complete Moodle database**: All courses, users, grades, activities
- **System configuration**: Site settings, plugin configurations
- **User data**: Profiles, preferences, custom fields
- **Format**: Compressed SQL dump (`.sql.gz`)

## File Backup

- **Moodle data directory**: Uploaded files, course content
- **Configuration files**: Custom PHP, Apache settings
- **Plugin files**: Custom plugins and modifications
- **Format**: Compressed tar archive (`.tar.gz`)

## Metadata Backup

- **Backup manifest**: JSON file with backup details
- **Git commit hash**: Links backup to code version
- **Docker image versions**: Ensures reproducible environment
- **Timestamp**: Precise backup creation time

# 🔄 Creating Backups

## Manual Backup

#### Quick Backup

```bash
# Create immediate backup
./scripts/backup.sh
```

#### Backup with Custom Name

```bash
# Create timestamped backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "Creating backup: thesis_milestone_$TIMESTAMP"
./scripts/backup.sh
```

## Automated Backup

### Linux/macOS (Crontab)

```bash
# Edit crontab
crontab -e

# Add backup schedules
# Daily backup at 2 AM
0 2 * * * cd /path/to/moodle-thesis-environment && ./scripts/backup.sh

# Weekly backup on Sundays at 3 AM
0 3 * * 0 cd /path/to/moodle-thesis-environment && ./scripts/backup.sh

# Before important work sessions
0 9 * * 1-5 cd /path/to/moodle-thesis-environment && ./scripts/backup.sh
```

### Windows (Task Scheduler)

1. Open Task Scheduler
2. Create Basic Task
3. Set trigger (daily, weekly, etc.)
4. Set action: Start a program
5. Program: C:\path\to\your\project\scripts\backup.bat

Create scripts/backup.bat:

```bat
@echo off
cd /d "C:\path\to\learning-scorecard-environment"
bash scripts/backup.sh
```

### Backup Before Important Events

#### Milestones / Major Plugin Changes

```bash
# Before milestones
./scripts/backup.sh
git tag -a "badge-implementation-backup" -m "Backup before badge implementation"

# Before major plugin changes
./scripts/backup.sh
git add . && git commit -m "Backup before major plugin refactoring"
```

# 📂 Backup Storage Structure

```
backups/
├── database/
│   ├── moodle_db_20251219_143022.sql.gz
│   ├── moodle_db_20251220_020000.sql.gz
│   └── ...
├── moodle-data/
│   ├── moodle_data_20251219_143022.tar.gz
│   ├── moodle_config_20251219_143022.tar.gz
│   ├── moodle_data_20251220_020000.tar.gz
│   └── ...
├── backup_manifest_20251219_143022.json
├── backup_manifest_20251220_020000.json
└── ...
```

### Backup Manifest Example

```json
{
  "timestamp": "20251219_143022",
  "date": "2024-12-19T14:30:22+00:00",
  "database_backup": "database/moodle_db_20251219_143022.sql.gz",
  "moodle_data_backup": "moodle-data/moodle_data_20251219_143022.tar.gz",
  "moodle_config_backup": "moodle-data/moodle_config_20251219_143022.tar.gz",
  "git_commit": "a1b2c3d4e5f6789012345678901234567890abcd",
  "docker_images": {
    "moodle": "bitnami/moodle:4.1",
    "mariadb": "mariadb:10.6"
  },
  "backup_size": {
    "database": "45.2MB",
    "moodle_data": "1.2GB",
    "total": "1.25GB"
  }
}
```

# 🔄 Restoring Backups

### List Available Backups

```bash
# Show all available backups
ls -la backups/backup_manifest_*.json

# Show backup details
cat backups/backup_manifest_20251219_143022.json
```

## Basic Restore

```bash
# Restore from specific backup
./scripts/restore.sh 20251219_143022
```

## Advanced Restore Options

### Restore on a Fresh Machine

```bash
# Clone repository
git clone https://github.com/miguelaguiar01/learning-scorecard-environment.git
cd learning-scorecard-environment

# Copy backup files to backups directory
# Then restore
./scripts/setup.sh restore 20251219_143022
```

### Selective Restore

```bash
# Stop containers
docker-compose down

# Start only database
docker-compose up -d moodle_db

# Restore database manually
gunzip -c backups/database/moodle_db_20251219_143022.sql.gz | \
  docker exec -i moodle_db mysql -u root -p"$DB_ROOT_PASSWORD"

# Start all containers
docker-compose up -d
```

### Files Only

```bash
# Restore Moodle data without touching database
docker run --rm \
  -v learning_scorecard_environment_moodle_data:/target \
  -v "$(pwd)/backups/moodle-data":/backup:ro \
  alpine:latest \
  sh -c "cd /target && tar xzf /backup/moodle_data_20251219_143022.tar.gz"

# Restart Moodle to recognize changes
docker-compose restart moodle_web
```

# 🌐 Cross-Machine Backup Strategies

## Google Drive (using rclone)

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure Google Drive
rclone config

# Add to backup script
echo "rclone copy ./backups/ gdrive:learning-scorecard-backups/" >> scripts/backup.sh
```

# 🔒 Backup Security & Best Practices

## Encryption

### Encrypt Sensitive Backups

```bash
# Create encrypted backup
./scripts/backup.sh
TIMESTAMP=$(ls -t backups/backup_manifest_*.json | head -1 | sed 's/.*_\(.*\)\.json/\1/')

# Encrypt database backup
gpg --cipher-algo AES256 --compress-algo 1 --s2k-mode 3 \
    --s2k-digest-algo SHA512 --s2k-count 65536 --symmetric \
    --output "backups/database/moodle_db_${TIMESTAMP}.sql.gz.gpg" \
    "backups/database/moodle_db_${TIMESTAMP}.sql.gz"

# Remove unencrypted version
rm "backups/database/moodle_db_${TIMESTAMP}.sql.gz"
```

### Decrypt for Restore

```bash
# Decrypt before restore
gpg --decrypt "backups/database/moodle_db_${TIMESTAMP}.sql.gz.gpg" > \
    "backups/database/moodle_db_${TIMESTAMP}.sql.gz"
```

## Access Control

### Secure Backup Directory

```bash
# Restrict access to backup directory
chmod 700 backups/
chmod 600 backups/*
```

### Environment Variables Security

```bash
# Never commit .env file with real passwords
echo ".env" >> .gitignore

# Use .env.example for templates
cp .env .env.example
# Edit .env.example to remove sensitive values
```

# 📊 Backup Monitoring

Run the `scripts/backup-health.sh`in order to check if the backup is current and when was the last backup.

```bash
# Check for backup age and integrity
./scripts/backup-health.sh
```

# 🔧 Backup Customization

## Selective Backup

### Exclude Large Files

Edit scripts/backup.sh to exclude unnecessary files:

```bash
# Modified Moodle data backup command
docker run --rm \
  -v learning_scorecard_environment_moodle_data:/source:ro \
  -v "$(pwd)/$MOODLE_BACKUP_DIR":/backup \
  alpine:latest \
  sh -c "cd /source && tar czf /backup/moodle_data_$TIMESTAMP.tar.gz \
    --exclude='cache/*' \
    --exclude='localcache/*' \
    --exclude='temp/*' \
    --exclude='trashdir/*' \
    --exclude='sessions/*' \
    --exclude='*.log' \
    ."
```

### Database Exclusion

```bash
# Exclude log tables for smaller backups
docker exec moodle_db mysqldump \
  -u root -p"$DB_ROOT_PASSWORD" \
  --single-transaction \
  --routines \
  --triggers \
  --ignore-table="$DB_NAME.mdl_logstore_standard_log" \
  --ignore-table="$DB_NAME.mdl_sessions" \
  "$DB_NAME" > "$DB_BACKUP_DIR/moodle_db_minimal_$TIMESTAMP.sql"
```

# 🚨 Disaster Recovery

## Complete System Recovery

### Scenario: Hard Drive Failure

- Setup new system with Docker and Git
- Clone repository: git clone https://github.com/miguelaguiar01/learning-scorecard-environment.git
- Download latest backup from cloud storage
- Restore environment: `./scripts/setup.sh restore 20251219_143022` (example)
- Verify integrity: Access Moodle and check critical data

### Scenario: Corrupted Database

- Stop Moodle: `docker-compose stop moodle_web`
- Restore database only: Use selective restore method
- Start Moodle: `docker-compose start moodle_web`
- Verify data integrity: Check courses, users, grades

### Scenario: Plugin Development Mistake

- Stop containers: `docker-compose down`
- Restore from before changes: `./scripts/restore.sh 20251219_143022` (**pre-change timestamp!**)
- Restart development: Continue from known good state

---

Last updated: June 2025
Tested with: Docker 24.0+, Moodle 4.1, MariaDB 10.6
