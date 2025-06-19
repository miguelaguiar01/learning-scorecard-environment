# Learning Scorecard Environment - Setup Guide

This guide provides detailed instructions for setting up the Learning Scorecard Environment on any machine.

# 📋 Prerequisites

### System Requirements

- **OS**: Windows 10/11, macOS 10.15+, or Linux (Ubuntu 18.04+)
- **RAM**: Minimum 4GB, Recommended 8GB+
- **Storage**: Minimum 10GB free space
- **Network**: Internet connection for initial setup

### Required Software

1. **Docker Desktop** (Windows/macOS) or **Docker Engine** (Linux)

   - Windows: [Download Docker Desktop](https://www.docker.com/products/docker-desktop)
   - macOS: [Download Docker Desktop](https://www.docker.com/products/docker-desktop)
   - Linux: Follow [official installation guide](https://docs.docker.com/engine/install/)

2. **Docker Compose** (usually included with Docker Desktop)

   - Verify installation: `docker-compose --version`

3. **Git**

   - Download from [git-scm.com](https://git-scm.com/)

4. **Text Editor** (optional but recommended)
   - VS Code, Sublime Text, or similar

# 🚀 Quick Setup (New Installation)

### Step 1: Clone the Repository

```bash
git clone https://github.com/miguelaguiar01/learning-scorecard-environment.git
cd learning-scorecard-environment
```

### Step 2: Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit the configuration (see Configuration section below)
nano .env  # or use your preferred editor
```

### Step 3: Run Setup

```bash
# Make scripts executable (Linux/macOS)
chmod +x scripts/*.sh

# Run the setup script
./scripts/setup.sh
```

### Step 4: Access Moodle

- Open browser and navigate to: http://localhost:8080
- Login with credentials from your .env file
- Default: admin / SecureAdminPass123!

# ⚙️ Configuration

### Environment Variables (.env)

Edit the .env file to customize your installation:

```bash
# Database Configuration
DB_ROOT_PASSWORD=secureRootPassword123
DB_NAME=moodle_ls
DB_USER=moodle_user
DB_PASSWORD=securePassword123
DB_PORT=3306

# Moodle Configuration
MOODLE_PORT=8080
MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASSWORD=SecureAdminPass123!
MOODLE_ADMIN_EMAIL=your.email@university.edu
MOODLE_SITE_NAME=LS Moodle Environment

# Development
DEBUG=true

# Backup Configuration
BACKUP_RETENTION_DAYS=30
BACKUP_SCHEDULE=daily
```

### Port Conflicts

If port 8080 is already in use:

- Change MOODLE_PORT=8080 to another port (e.g., 8081)
- Restart: docker-compose down && docker-compose up -d
- Access at new URL: http://localhost:8081

### Custom Configuration Files

#### PHP Configuration

```ini
; Custom PHP settings
memory_limit = 512M
max_execution_time = 300
upload_max_filesize = 100M
post_max_size = 100M
```

#### Apache Configuration

Create config/apache/moodle.conf:

```apache
<VirtualHost *:8080>
    ServerName localhost
    DocumentRoot /bitnami/moodle

    # Custom headers
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-Content-Type-Options nosniff
</VirtualHost>
```

# 🔄 Setup from Existing Backup

If you have an existing backup from another machine:

### Step 1: Prepare Backup Files

```bash
# Create the project directory
git clone https://github.com/miguelaguiar01/learning-scorecard-environment.git
cd learning-scorecard-environment

# Copy your backup files to the backups directory
# Structure should be:
# backups/
# ├── database/moodle_db_TIMESTAMP.sql.gz
# ├── moodle-data/moodle_data_TIMESTAMP.tar.gz
# ├── moodle-data/moodle_config_TIMESTAMP.tar.gz
# └── backup_manifest_TIMESTAMP.json
```

### Step 2: Restore from Backup

```bash
# List available backups
ls backups/backup_manifest_*.json

# Restore from specific backup (use timestamp from filename)
./scripts/setup.sh restore 20251219_143022
```

# 🐛 Troubleshooting

## Docker Issues

### Docker Not Running

### Error: `Cannot connect to the Docker daemon` Solution:

- Windows/macOS: Start Docker Desktop
- Linux: `sudo systemctl start docker`

### Permission Denied

### Error: `Permission denied while trying to connect to Docker` Solution:

- Windows: Run terminal as Administrator
- Linux: Add user to docker group: `sudo usermod -aG docker $USER` (logout/login required)

### Port Already in Use

### Error: `Port 8080 is already allocated` Solution:

- Change MOODLE_PORT in .env
- Restart containers: `docker-compose down && docker-compose up -d`

## Moodle Issues

### Moodle Won't Start

### Symptoms: Container starts but Moodle shows errors

### Solutions:

- Check logs: `docker-compose logs moodle_web`
- Verify database connection: `docker-compose logs moodle_db`
- Clear volumes and restart fresh:

  ```bash
  docker-compose down -v
  docker volume prune
  ./scripts/setup.sh
  ```

### Database Connection Failed

### Error: `Database connection failed` Solutions:

- Verify database is running: `docker-compose ps`
- Check database logs: `docker-compose logs moodle_db`
- Verify credentials in .env file
- Wait longer for database to initialize (can take 2-3 minutes)

## Plugin Directory Issues

### Error: `Plugin files not appearing` Solutions:

- Verify plugin directory exists: `ls -la plugins/learning-scorecard/`
- Check volume mount in logs: `docker-compose logs moodle_web | grep volume`
- Restart containers: `docker-compose restart moodle_web`

## Performance Issues

### Slow Startup

### Cause: `Large database or insufficient resources` Solutions:

- Increase Docker memory allocation (Docker Desktop → Settings → Resources)
- Use SSD storage if available
- Close other resource-intensive applications

### Out of Disk Space

### Error: `No space left on device` Solutions:

- Clean Docker: docker system prune -a
- Remove old backups: find backups/ -mtime +30 -delete
- Move backups to external storage

# 🔧 Advanced Setup

## Developer Mode Setup

### For active plugin development:

```bash
# Add development-specific environment variables
echo "BITNAMI_DEBUG=true" >> .env
echo "MOODLE_DEVELOPER_MODE=true" >> .env

# Mount plugin as read-write
# Edit docker-compose.yml volumes section:
volumes:
  - ./plugins/learning-scorecard:/bitnami/moodle/local/learning_scorecard:rw
```

## Network Configuration

### For external access (e.g., testing on mobile devices):

```bash
# In docker-compose.yml, change:
ports:
  - "0.0.0.0:8080:8080"  # Allows external access
```

**Security Warning**: Only use external access on trusted networks!

# 📚 Next Steps

### After successful setup:

- Create Initial Backup: ./scripts/backup.sh
- Configure Moodle: Access admin panel to configure courses, users, etc.
- Install Plugins: Copy plugins to plugins/ directory
- Read BACKUP.md: Understand backup and restore procedures
- Version Control: Commit your configuration changes

# 🆘 Getting Help

## Log Analysis

```bash
# View all logs
docker-compose logs

# View specific service logs
docker-compose logs moodle_web
docker-compose logs moodle_db

# Follow logs in real-time
docker-compose logs -f
```

## Health Checks

```bash
# Check container status
docker-compose ps

# Test Moodle accessibility
curl -I http://localhost:8080

# Test database connectivity
docker exec moodle_db mysql -u root -p -e "SHOW DATABASES;"
```

## Reset Everything

```bash
# Nuclear option - removes all data and starts fresh
docker-compose down -v
docker volume prune
docker system prune
./scripts/setup.sh
```

# 📞 Support

### If you encounter issues not covered here:

- Check the main README.md
- Review Docker documentation
- Check Bitnami Moodle documentation
- Create an issue in the project repository

---

Last updated: June 2025
Compatible with: Docker 20.10+, Docker Compose 2.0+
