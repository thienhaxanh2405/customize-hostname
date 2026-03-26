# Hostname Manager for macOS

A bash script to manage `/etc/hosts` entries for SSH and server access through an interactive menu-driven interface. Provides a simple alternative to setting up a full DNS server for local hostname-to-IP mappings.

## Features

- **Interactive Menu System** - 7 user-friendly menu options
- **CRUD Operations** - Add, search, edit, and delete hostname entries
- **CSV Bulk Import** - Import multiple hostnames from CSV files
- **Input Validation** - RFC 1123 compliant hostname and IPv4 address validation
- **Safety First** - Timestamped backups before modifications
- **Automatic DNS Flush** - macOS DNS cache cleared after changes
- **Isolated Block Management** - All entries stored in dedicated markers

## Requirements

- macOS (tested on macOS 10.14+) or Linux
- Bash 3.2+ (compatible with macOS default bash)
- sudo/root privileges

## Installation

1. Clone or download this repository:
   ```bash
   cd ~/Downloads
   git clone <repository-url> customize-hostname
   ```

2. Make the script executable:
   ```bash
   chmod +x customize-hostname/manage-hosts.sh
   ```

3. (Optional) Create your custom CSV file from the sample:
   ```bash
   cp customize-hostname/custom-hostnames.csv.sample customize-hostname/custom-hostnames.csv
   # Edit with your hostnames
   nano customize-hostname/custom-hostnames.csv
   ```

## Usage

### Running the Script

The script **must** be run with sudo privileges:

```bash
sudo ./customize-hostname/manage-hosts.sh
```

### Menu Options

#### 1. Add Hostname

Add a new hostname-to-IP mapping:

```
Enter hostname: dev-server.local
Enter IP address: 192.168.1.100
Create backup before adding? (y/n): y
```

**Validation:**
- Hostname must be RFC 1123 compliant
- IP must be valid IPv4 format (0-255 per octet)
- Reserved names (localhost, broadcasthost) are rejected
- Duplicate hostnames prompt for overwrite confirmation

#### 2. Search Hostname

Find an existing hostname and display its IP:

```
Enter hostname to search: dev-server.local
✓ Found: dev-server.local -> 192.168.1.100
```

#### 3. Edit Hostname

Update the IP address for an existing hostname:

```
Enter hostname to edit: dev-server.local
Current IP: 192.168.1.100
Enter new IP address: 192.168.1.101
Create backup before editing? (y/n): y
✓ Updated: dev-server.local -> 192.168.1.101 (was 192.168.1.100)
```

#### 4. Delete Hostname

Remove a hostname entry:

```
Enter hostname to delete: dev-server.local
⚠ Will delete: dev-server.local -> 192.168.1.101
Are you sure? (y/n): y
Create backup before deleting? (y/n): y
✓ Deleted: dev-server.local (was pointing to 192.168.1.101)
```

#### 5. Import from CSV

Bulk import hostnames from a CSV file.

**Quick Start with Sample File:**

1. Create your CSV file from the provided sample:
   ```bash
   cp custom-hostnames.csv.sample custom-hostnames.csv
   ```

2. Edit `custom-hostnames.csv` with your hostnames:
   ```bash
   nano custom-hostnames.csv
   ```

3. Import using menu option 5:
   ```bash
   sudo ./manage-hosts.sh
   # Select option 5
   # Enter: custom-hostnames.csv
   ```

**CSV Format:**
```csv
hostname,ip
dev-server.local,192.168.1.100
staging-api.local,192.168.1.101
test-db.local,192.168.1.102
```

**Notes:**
- First line must be the header: `hostname,ip`
- One hostname per line
- No spaces around commas
- Use `.csv` file extension
- The repository includes `custom-hostnames.csv.sample` as a template
- `custom-hostnames.csv` is gitignored to keep your private IPs secure

**Import Process:**
```
Enter CSV file path: custom-hostnames.csv
Create backup before importing? (y/n): y
✓ Added: dev-server.local -> 192.168.1.100
✓ Added: staging-api.local -> 192.168.1.101
⚠ Duplicate found: test-db.local already exists
Choose action: [O]verwrite / [S]kip / Skip [A]ll remaining? (o/s/a): o
✓ Overwritten: test-db.local -> 192.168.1.102

✓ Import complete!
  Added: 2
  Overwritten: 1
  Skipped: 0
```

**Duplicate Handling:**
- **[O]verwrite** - Replace existing entry with new IP
- **[S]kip** - Keep existing entry, skip this import
- **Skip [A]ll** - Skip this and all remaining duplicates

#### 6. Clear All Customize Entries

Remove all entries from the customize block:

```
Current entries (5 total):
  192.168.1.100    dev-server.local
  192.168.1.101    staging-api.local
  ...

⚠ This will remove ALL 5 entries from the customize block!
Are you sure? (y/n): y
Create backup before clearing? (y/n): y
✓ Cleared all 5 entries from customize block
```

#### 7. Exit

Exit the script.

## How It Works

### Block Markers

All hostname entries are stored within dedicated block markers in `/etc/hosts`:

```
#### Customize Hostname by thienhaxanh2405 ####
192.168.1.100    dev-server.local
192.168.1.101    staging-api.local
#### End Customize Hostname by thienhaxanh2405 ####
```

This ensures:
- Safe isolation from system entries
- Easy identification of managed entries
- Clean removal when needed

### Backup System

Before each write operation (add, edit, delete, import, clear), the script prompts for backup confirmation. Backups are timestamped:

```
/etc/hosts.backup.20260326-113045
```

**Restore from backup:**
```bash
sudo cp /etc/hosts.backup.20260326-113045 /etc/hosts
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Atomic Writes

All modifications use atomic writes to prevent corruption:

1. Changes written to `/tmp/hosts.tmp.$$`
2. Atomic move to `/etc/hosts`
3. Automatic DNS cache flush

If the process is interrupted (Ctrl+C), `/etc/hosts` remains intact.

## Validation Rules

### Hostname Validation (RFC 1123)

✅ **Valid:**
- `server.local`
- `api-v2.example.com`
- `db01.internal`
- `192-168-1-1.local` (digits allowed)

❌ **Invalid:**
- `-server.local` (leading hyphen)
- `server-.local` (trailing hyphen)
- `server..local` (double dots)
- `a.very.long.hostname.that.exceeds.the.maximum.length.of.253.characters...` (too long)
- `localhost` (reserved)

### IP Validation (IPv4)

✅ **Valid:**
- `192.168.1.100`
- `10.0.0.1`
- `172.16.0.1`
- `0.0.0.0`
- `255.255.255.255`

❌ **Invalid:**
- `999.999.999.999` (octets > 255)
- `192.168.1` (incomplete)
- `192.168.1.1.1` (too many octets)
- `192.168.1.a` (non-numeric)

## Testing DNS Resolution

After adding a hostname, test resolution:

```bash
# Test ping
ping -c 1 dev-server.local

# Test SSH
ssh user@dev-server.local

# Check /etc/hosts
grep -A 10 "Customize Hostname" /etc/hosts
```

## Troubleshooting

### DNS not resolving after adding hostname

**Solution:**
```bash
# Manually flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Verify entry exists in /etc/hosts
grep "your-hostname" /etc/hosts
```

### Permission denied error

**Solution:**
```bash
# Run with sudo
sudo ./manage-hosts.sh
```

### Script won't execute

**Solution:**
```bash
# Make executable
chmod +x manage-hosts.sh

# Verify permissions
ls -la manage-hosts.sh
```

### Backup creation fails

**Cause:** Insufficient permissions or disk space

**Solution:**
```bash
# Check disk space
df -h

# Check permissions
ls -la /etc/hosts

# Run with sudo
sudo ./manage-hosts.sh
```

## CSV Import Examples

### Using the Sample File

The repository includes a sample CSV file to get you started:

```bash
# 1. Copy the sample file
cp custom-hostnames.csv.sample custom-hostnames.csv

# 2. Edit with your servers
nano custom-hostnames.csv

# 3. Import via the script
sudo ./manage-hosts.sh
# Select option 5
# Enter file path: custom-hostnames.csv
```

**Sample file structure (`custom-hostnames.csv.sample`):**
```csv
hostname,ip
db.dataplatform.private,172.16.165.243
api.staging.local,192.168.1.100
web.dev.local,192.168.1.101
```

### Basic Import File

Create `my-hosts.csv`:
```csv
hostname,ip
dev.local,192.168.1.10
stage.local,192.168.1.20
prod.local,192.168.1.30
```

Import:
```bash
sudo ./manage-hosts.sh
# Select option 5
# Enter: my-hosts.csv
```

### Large Import with Comments

For documentation, add a README but keep CSV clean:

**servers.csv:**
```csv
hostname,ip
jenkins.local,10.0.1.50
gitlab.local,10.0.1.51
nexus.local,10.0.1.52
sonarqube.local,10.0.1.53
```

**servers-README.txt:**
```
jenkins.local - CI/CD server
gitlab.local - Git repository
nexus.local - Artifact repository
sonarqube.local - Code quality
```

## Safety Features

1. **Root Privilege Check** - Script exits if not run with sudo
2. **Backup Prompts** - Optional backups before each modification
3. **Atomic Writes** - Temp file + rename prevents corruption
4. **Input Validation** - Strict RFC 1123 and IPv4 checks
5. **Reserved Name Protection** - Prevents overwriting system entries
6. **Duplicate Detection** - Prompts before overwriting existing entries
7. **Confirmation Prompts** - Double-check for destructive operations

## Limitations

- **IPv4 Only** - IPv6 addresses not supported
- **macOS Only** - DNS flush commands are macOS-specific
- **Single IP per Hostname** - One hostname maps to one IP
- **No Wildcard Support** - Each hostname must be explicitly defined

## Uninstallation

To remove all customize entries:

1. Run the script:
   ```bash
   sudo ./manage-hosts.sh
   ```

2. Select option 6 (Clear all customize entries)

3. Or manually edit `/etc/hosts`:
   ```bash
   sudo nano /etc/hosts
   # Delete the customize block (between markers)
   ```

4. Flush DNS:
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```

## License

MIT License - feel free to modify and distribute.

## Author

Created by thienhaxanh2405

## Contributing

Contributions welcome! Please test thoroughly before submitting pull requests.

## Changelog

### Version 1.0.1 (2026-03-26)
- Fixed Bash 3.2 compatibility for macOS default bash
- Added `custom-hostnames.csv.sample` template file
- Added `.gitignore` to protect private IP addresses
- Cross-platform support (macOS and Linux)

### Version 1.0.0 (2026-03-26)
- Initial release
- Interactive menu system
- Add/Search/Edit/Delete operations
- CSV bulk import
- Backup system
- Input validation
- Automatic DNS flush
