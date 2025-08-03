# Mastodon Maintenance Script

A comprehensive, production-ready maintenance and cleanup script for Mastodon instances. This script provides safe, automated maintenance operations that can run while your Mastodon instance is online.

## 🚀 Features

### **Safe Online Operations**
- ✅ All operations work while your Mastodon instance is running
- ✅ No downtime required for any maintenance tasks
- ✅ Comprehensive error handling and logging
- ✅ Dry-run mode for testing

### **Comprehensive Maintenance**
- **Account Management**: Clean up inactive accounts, cull non-existent accounts
- **Media Cleanup**: Remove old media files, orphaned media, profile media
- **Domain Management**: Export, purge, and audit domain blocks
- **System Health**: Monitor system stats, queue status, and cache management
- **Feed Maintenance**: Rebuild feeds for optimal performance

### **Modern Bash Standards**
- ✅ Modern bash scripting with proper error handling
- ✅ Comprehensive logging with timestamps
- ✅ Color-coded output for better readability
- ✅ Timeout protection for long-running operations
- ✅ Proper argument parsing and validation

## 📋 Prerequisites

- **Mastodon Instance**: Running Mastodon installation
- **Bash**: Version 4.0 or higher
- **Required Commands**: `rails`, `tootctl`, `stdbuf`, and `timeout`
- **Permissions**: Run from your Mastodon installation directory

## 🛠️ Installation

1. **Download the script**:
   ```bash
   wget https://raw.githubusercontent.com/johndotpub/mastodon-maintenance/main/clean.sh
   ```

2. **Make it executable**:
   ```bash
   chmod +x clean.sh
   ```

3. **Run from your Mastodon directory**:
   ```bash
   cd /path/to/your/mastodon/installation
   ./clean.sh --help
   ```

## 📖 Usage

### **Basic Operations**

```bash
# Full cleanup in dry-run mode (recommended first run)
./clean.sh --dry-run

# Domain operations
./clean.sh --domains

# Account cleanup
./clean.sh --accounts

# Media cleanup
./clean.sh --media

# Remove orphaned media
./clean.sh --orphaned-media
```

### **Combined Operations**

```bash
# Standard maintenance (recommended for regular use)
./clean.sh --maintenance

# All media operations
./clean.sh --all-media

# Complete cleanup (all operations)
./clean.sh --full
```

### **Enhanced Operations**

```bash
# Enhanced account cleanup (includes inactive accounts)
./clean.sh --account-cleanup

# Complete media audit
./clean.sh --media-audit

# Domain audit and cleanup
./clean.sh --domain-audit

# System health check
./clean.sh --system-health

# Complete cleanup with cache clearing
./clean.sh --deep-cleanup
```

### **Advanced Options**

```bash
# Custom concurrency level
./clean.sh --concurrency 8 --domains

# Custom retention periods
./clean.sh --media-days 60 --profile-media-days 60 --maintenance
./clean.sh --preview-cards-days 15 --statuses-days 15 --maintenance

# Verbose output
./clean.sh --verbose --maintenance

# Log to file
./clean.sh --log-file --system-health

# Include subdomains in domain operations
./clean.sh --include-subdomains --domains
```

## 🔧 Available Operations

### **Basic Operations**
- `--domains` - Export and purge blocked domains
- `--accounts` - Clean up accounts (cull + prune)
- `--media` - Remove old media files (configurable, default: 90 days)
- `--profile-media` - Remove old profile media (configurable, default: 90 days)
- `--preview-cards` - Remove old preview cards (configurable, default: 30 days)
- `--remote-statuses` - Remove old remote statuses (configurable, default: 30 days)
- `--orphaned-media` - Remove orphaned media
- `--feeds` - Build all feeds

### **Combined Operations**
- `--all-media` - All media operations
- `--maintenance` - Standard maintenance operations
- `--full` - Complete cleanup (all operations)

### **Enhanced Operations**
- `--account-cleanup` - Enhanced account cleanup (inactive + cull + prune)
- `--media-audit` - Media audit (stats + orphaned + cleanup)
- `--domain-audit` - Domain audit (list + check + purge)
- `--system-health` - System health check (info + stats + cache)
- `--deep-cleanup` - Complete cleanup with cache clearing

## ⚙️ Configuration

### **Default Settings**
- **Concurrency**: 16 (configurable with `--concurrency`)
- **Media retention**: 90 days (configurable with `--media-days`)
- **Profile media retention**: 90 days (configurable with `--profile-media-days`)
- **Preview cards retention**: 30 days (configurable with `--preview-cards-days`)
- **Remote statuses retention**: 30 days (configurable with `--statuses-days`)

### **Configuration Options**

The script provides several command-line options for customizing retention periods:

```bash
# Custom retention periods
--media-days N           # Set media retention days (default: 90)
--profile-media-days N   # Set profile media retention days (default: 90)
--preview-cards-days N   # Set preview cards retention days (default: 30)
--statuses-days N        # Set remote statuses retention days (default: 30)

# Examples
./clean.sh --media-days 60 --profile-media-days 60 --maintenance
./clean.sh --preview-cards-days 15 --statuses-days 15 --maintenance
```

### **Environment Variables**
The script uses sensible defaults, but you can modify the script to use environment variables if needed.

## 📊 Logging and Output

### **Console Output**
- **Color-coded messages**: Blue (info), Green (success), Yellow (warning), Red (error)
- **Timestamps**: All messages include timestamps
- **Progress tracking**: Clear indication of operation progress

### **File Logging**
```bash
# Enable file logging
./clean.sh --log-file --maintenance
```
Logs are saved to `cleanup_YYYYMMDD_HHMMSS.log` in the current directory.

### **Verbose Mode**
```bash
# Enable verbose output
./clean.sh --verbose --system-health
```
Shows detailed command execution and output.

## 🛡️ Safety Features

### **Dry-Run Mode**
```bash
# Test operations without making changes
./clean.sh --dry-run --full
```
Shows what would be executed without actually running the commands.

### **Debugging and Troubleshooting**
```bash
# Enable verbose output for debugging
./clean.sh --verbose --maintenance

# Check script configuration
./clean.sh --maintenance
```
The script provides detailed output showing:
- Selected operations and their count
- Configuration summary with retention periods
- Operation execution progress
- Skipped operations (for clarity)

### **Error Handling**
- **Timeout protection**: Operations timeout after 5 minutes (configurable)
- **Graceful failures**: Failed operations don't stop the entire script
- **Comprehensive reporting**: Summary of successful and failed operations

### **Validation**
- **Prerequisite checking**: Verifies required commands are available
- **Rails environment**: Ensures script is run from Mastodon directory
- **Argument validation**: Validates all command-line arguments

## 📈 Performance

### **Concurrency Control**
- **Default**: 16 concurrent operations
- **Configurable**: Use `--concurrency` to adjust based on your server capacity
- **Smart defaults**: Operations that support concurrency use it automatically

### **Resource Management**
- **Memory efficient**: Minimal memory footprint
- **CPU friendly**: Respects system resources
- **I/O optimized**: Uses `stdbuf` for real-time output

## 🔍 Monitoring and Health

### **System Health Check**
```bash
./clean.sh --system-health
```
Provides:
- System information
- Instance statistics
- Queue status
- Cache status

### **Media Audit**
```bash
./clean.sh --media-audit
```
Shows:
- Media storage statistics
- Orphaned media files
- Cleanup operations

### **Domain Audit**
```bash
./clean.sh --domain-audit
```
Provides:
- Current domain blocks
- Domain health status
- Cleanup operations

## 🚨 Important Notes

### **Backup Recommendations**
- **Always backup your database** before running maintenance operations
- **Test in dry-run mode** first to understand what will be executed
- **Monitor your instance** during maintenance operations

### **Timing Considerations**
- **Low-traffic periods**: Run during off-peak hours for best performance
- **Regular maintenance**: Weekly or monthly depending on instance size
- **Monitoring**: Check logs and system performance after operations

### **Instance Size Considerations**
- **Small instances** (< 1000 users): Run `--maintenance` weekly
- **Medium instances** (1000-10000 users): Run `--maintenance` 2-3 times per week
- **Large instances** (> 10000 users): Run `--maintenance` daily, consider custom scheduling

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### **Development Setup**
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### **Testing**
- Test with `--dry-run` mode
- Test on a staging environment first
- Verify all operations work as expected

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Mastodon Team**: For the excellent `tootctl` command-line tools
- **Bash Community**: For modern bash scripting best practices
- **Open Source Community**: For inspiration and feedback

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/johndotpub/mastodon-maintenance/issues)
- **Discussions**: [GitHub Discussions](https://github.com/johndotpub/mastodon-maintenance/discussions)
- **Mastodon**: [@johndotpub@rewt.link](https://rewt.link/@johndotpub)

## 🔄 Version History

- **v1.0.1** - Added configurable retention periods (`--media-days`, `--profile-media-days`, `--preview-cards-days`, `--statuses-days`), improved error handling, and enhanced debugging output
- **v1.0.0** - Initial release with comprehensive maintenance operations

---

**Made with ❤️ for the Mastodon community**

*This script is designed to make Mastodon instance maintenance easier, safer, and more efficient. Use it responsibly and always test in dry-run mode first.*
