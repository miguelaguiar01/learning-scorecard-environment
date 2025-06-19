# Learning Scorecard Environment

Professional, reproducible Moodle development environment for the Learning Scorecard.

## 🎯 Features

- **Infrastructure as Code**: Entire environment defined in version control
- **Automated Backup/Restore**: Reliable data preservation and migration
- **Cross-Platform**: Works on Windows, macOS, and Linux
- **Production-Ready**: Professional configuration suitable for research
- **Plugin Development**: Integrated plugin development workflow

## 📁 Project Structure

```
moodle-thesis-environment/
├── docker-compose.yml      # Main orchestration
├── .env                    # Environment configuration
├── scripts/                # Automation scripts
├── backups/                # Backup storage
├── config/                 # Service configurations
├── plugins/                # Your plugins
└── docs/                   # Documentation
```

## 🔒 Security Notes

- Change default passwords in .env
- Use strong passwords for production
- Keep .env file secure and never commit it
- Regular backups are automatically cleaned up

## 🚀 Quick Start

### First Time Setup

```bash
git clone https://github.com/miguelaguiar01/learning-scorecard-environment.git
cd learning-scorecard-environment
cp .env.example .env  # Edit with your settings
./scripts/setup.sh
```

### Restore from Backup

```bash
./scripts/setup.sh restore 20251219_143022
```

## 🆘 Troubleshooting

### Common Issues

- Port conflicts: Change ports in .env
- Permission issues: Ensure Docker has proper permissions
- Out of space: Clean old backups with docker system prune

### Getting Help

- Check logs: docker-compose logs
- Verify services: docker-compose ps
- Test connectivity: curl localhost:8080
