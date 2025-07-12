#!/usr/bin/env bash

set -euo pipefail

# Configuration
TRACCAR_SERVICE="traccar.service"
TRACCAR_DIR="/opt/traccar"
SYSTEMD_PATH="/etc/systemd/system"
BACKUP_DIR="/root/backup"
MYSQL_USER="root"
MYSQL_PASS="root"
MYSQL_BACKUP_DIR="/root/mysql_backup"
DAYS_TO_KEEP=3
COMPRESS_DB=1  # 1= gzip, 0 = plain
LOG_FILE="/opt/traccar/logs/tracker-server.log"

LATEST_VERSION=""
LATEST_URL=""

# Prepare log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Colors for output
RED="\033[0;31m"; YELLOW="\033[0;33m"; BLUE="\033[0;36m"; NORMAL="\033[0m"

# Logging utility
log() {
    local msg="$1"
    local entry="$(date '+%Y-%m-%d %H:%M:%S') - $msg"
    # Append to log file
    echo -e "$entry" >> "$LOG_FILE"
    # Also output to stderr to separate from command output
    echo -e "$entry" >&2
}

# Yes/No prompt utility
prompt_confirm() {
    local msg="$1"
    while true; do
        read -rp "$msg [y/n]: " yn
        case "$yn" in
            [Yy]*) log "User confirmed: $msg"; return 0;;
            [Nn]*) log "User declined: $msg"; return 1;;
            *) log "Invalid confirm input: $yn"; echo "Please answer y or n.";;
        esac
    done
}

# Print interactive menu
print_menu() {
    echo -e "${BLUE}--- Traccar Tools Menu ---${NORMAL}"
    echo "1) Uninstall Traccar"
    echo "2) Install Traccar"
    echo "3) Upgrade Traccar"
    echo "4) Restart Traccar"
    echo "5) Show log"
    echo "6) Show status"
    echo "7) Check latest"
    echo "8) Backup MySQL"
    echo "9) Import MySQL"
    echo "10) Install MySQL server"
    echo -e "11) ${RED}Reset MySQL server (DANGER!)${NORMAL}"
    echo "x) Exit"
}

# Update traccar.xml with current MySQL credentials
update_traccar_config() {
    log "Updating Traccar config at $TRACCAR_DIR/conf/traccar.xml"
    cat > "$TRACCAR_DIR/conf/traccar.xml" <<EOF
<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE properties SYSTEM 'http://java.sun.com/dtd/properties.dtd'>
<properties>
    <entry key='config.default'>./conf/default.xml</entry>
    <!-- Database connection -->
    <entry key='database.driver'>com.mysql.cj.jdbc.Driver</entry>
    <entry key='database.url'>jdbc:mysql://127.0.0.1:3306/traccar?useSSL=false&characterEncoding=UTF-8</entry>
    <entry key='database.user'>${MYSQL_USER}</entry>
    <entry key='database.password'>${MYSQL_PASS}</entry>
</properties>
EOF
    log "Traccar config updated"
}

# Fetch latest GitHub release JSON, extract URL & version
gen_latest_url() {
    local json url name
    json=$(curl -s https://api.github.com/repos/traccar/traccar/releases/latest) \
        || { log "Failed to fetch GitHub API"; return 1; }
    url=$(echo "$json" \
      | grep '"browser_download_url"' \
      | grep 'traccar-linux-64.*\.zip' \
      | head -n1 \
      | cut -d '"' -f4)
    if [[ -z "$url" ]]; then
        log "Failed to find download URL"
        return 1
    fi
    name=$(basename "$url")                     # e.g. traccar-linux-64-6.7.1.zip
    name=${name%.zip}                           # strip “.zip”
    LATEST_VERSION=${name#traccar-linux-64-}    # strip prefix
    LATEST_URL="$url"
    log "Latest Traccar version: $LATEST_VERSION"
    return 0
}

# Download latest Traccar with error checking
download_traccar() {
    # Populate $LATEST_VERSION and $LATEST_URL
    if ! gen_latest_url; then
        log "Nie udało się pobrać URL z GitHub"
        return 1
    fi
    if prompt_confirm "Download version $LATEST_VERSION?"; then
        wget -q "$LATEST_URL" -O traccar.zip \
            || { log "Pobieranie nie powiodło się"; return 1; }
        log "Downloaded traccar.zip"
        return 0
    else
        log "Download skipped"
        return 1
    fi
}

# Fresh install of Traccar
install_traccar() {
    if download_traccar; then
        unzip -q traccar.zip
        chmod +x traccar.run
        sudo ./traccar.run
        systemctl start "$TRACCAR_SERVICE"
        log "Installed Traccar $LATEST_VERSION"
        # record version
        echo "$LATEST_VERSION" > "$TRACCAR_DIR/version.txt"
        log "Wrote version to $TRACCAR_DIR/version.txt"
        rm -f traccar.zip traccar.run README.txt
    fi
}

upgrade_traccar() {
    if download_traccar; then
        mkdir -p "$BACKUP_DIR" "$BACKUP_DIR/conf"
        systemctl stop "$TRACCAR_SERVICE"
        [[ -f "$SYSTEMD_PATH/$TRACCAR_SERVICE" ]] && cp "$SYSTEMD_PATH/$TRACCAR_SERVICE" "$BACKUP_DIR/"
        compgen -G "$TRACCAR_DIR/conf/*.xml" > /dev/null && cp "$TRACCAR_DIR/conf"/*.xml "$BACKUP_DIR/conf/"
        compgen -G "$TRACCAR_DIR/data/*.db"    > /dev/null && cp "$TRACCAR_DIR/data"/*.db "$BACKUP_DIR/"
        systemctl disable "$TRACCAR_SERVICE"
        rm -f "$SYSTEMD_PATH/$TRACCAR_SERVICE"
        systemctl daemon-reload
        rm -rf "$TRACCAR_DIR"
        unzip -q traccar.zip
        chmod +x traccar.run
        sudo ./traccar.run
        [[ -f "$BACKUP_DIR/$TRACCAR_SERVICE" ]] && cp "$BACKUP_DIR/$TRACCAR_SERVICE" "$SYSTEMD_PATH/"
        compgen -G "$BACKUP_DIR/conf/*.xml" > /dev/null && cp "$BACKUP_DIR/conf"/*.xml "$TRACCAR_DIR/conf/"
        mkdir -p "$TRACCAR_DIR/data"
        compgen -G "$BACKUP_DIR/*.db" > /dev/null && cp "$BACKUP_DIR"/*.db "$TRACCAR_DIR/data/"
        systemctl daemon-reload
        systemctl start "$TRACCAR_SERVICE"
        log "Upgraded Traccar to $LATEST_VERSION"
        echo "$LATEST_VERSION" > "$TRACCAR_DIR/version.txt"
        log "Wrote version to $TRACCAR_DIR/version.txt"
        rm -f traccar.zip traccar.run README.txt
    fi
}

# Backup MySQL
backup_mysql() {
    log "Starting MySQL backup to $MYSQL_BACKUP_DIR"
    mkdir -p "$MYSQL_BACKUP_DIR"
    systemctl stop "$TRACCAR_SERVICE"
    local date_str dbs
    date_str=$(date +%Y-%m-%d)
    dbs=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" | tail -n +2)
    for db in $dbs; do
        case "$db" in information_schema|performance_schema|mysql|sys) continue;; esac
        if [ "$COMPRESS_DB" -eq 1 ]; then
            mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db" | gzip -c > "$MYSQL_BACKUP_DIR/${date_str}-${db}.gz"
        else
            mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db" > "$MYSQL_BACKUP_DIR/${date_str}-${db}.sql"
        fi
        log "Backed up $db"
    done
    find "$MYSQL_BACKUP_DIR" -mtime +$DAYS_TO_KEEP -delete
    systemctl start "$TRACCAR_SERVICE"
    log "MySQL backup completed"
}

# Import chosen Traccar DB backup
import_mysql() {
    if prompt_confirm "Import a Traccar MySQL backup?"; then
        systemctl stop "$TRACCAR_SERVICE"
        mapfile -t backups < <(ls -1t "$MYSQL_BACKUP_DIR"/*traccar.* 2>/dev/null)
        if [ ${#backups[@]} -eq 0 ]; then
            log "No backups found"
            echo "No backup files found in $MYSQL_BACKUP_DIR"
            systemctl start "$TRACCAR_SERVICE"
            return 1
        fi
        for i in "${!backups[@]}"; do printf "%3d) %s\n" $((i+1)) "${backups[i]}"; done
        read -rp "Select backup: " sel
        [[ ! "$sel" =~ ^[0-9]+$ || "$sel" -lt 1 || "$sel" -gt ${#backups[@]} ]] && { echo "Invalid"; systemctl start "$TRACCAR_SERVICE"; return 1; }
        file="${backups[$((sel-1))]}"
        log "Importing $file"
        if [[ "$file" == *.gz ]]; then gunzip -c "$file" | mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" traccar; else mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" traccar < "$file"; fi
        systemctl start "$TRACCAR_SERVICE"
        log "Import completed"
    fi
}

uninstall_traccar() {
    # Confirm before uninstall
    if prompt_confirm "Are you sure you want to uninstall Traccar and delete all data?"; then
        log "Uninstalling Traccar ..."
        systemctl stop "$TRACCAR_SERVICE"
        systemctl disable "$TRACCAR_SERVICE"
        rm -f "$SYSTEMD_PATH/$TRACCAR_SERVICE"
        systemctl daemon-reload
        rm -rf "$TRACCAR_DIR"
        log "Traccar uninstalled"
    else
        log "Uninstallation of Traccar cancelled by user"
        echo "Uninstallation cancelled."
        return 1
    fi
}

# Install MySQL server and configure for Traccar
install_mysql_server() {
    if prompt_confirm "Install MySQL server and configure for Traccar?"; then
        log "Installing MySQL server"
        systemctl stop "$TRACCAR_SERVICE"
        apt-get -y update && apt-get -y install mysql-server
        mysql -u root --execute="ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASS}'; GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES; CREATE DATABASE IF NOT EXISTS traccar;"
        update_traccar_config
        systemctl start "$TRACCAR_SERVICE"
        log "MySQL installed and configured"
    fi
}


# Reset MySQL server completely
reset_mysql_server() {
    if prompt_confirm "Reset MySQL server (remove and reinstall)? All databases will be lost."; then
        log "Resetting MySQL server"
        systemctl stop "$TRACCAR_SERVICE"; systemctl stop mysql || true
        apt-get -y purge mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-*
        apt-get -y autoremove && apt-get -y autoclean
        apt-get -y update && apt-get -y install mysql-server
        mysql -u root --execute="ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASS}'; GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES; CREATE DATABASE IF NOT EXISTS traccar;"
        update_traccar_config
        systemctl start "$TRACCAR_SERVICE"
        log "MySQL reset and configured"
    fi
}


# Stub definitions
check_latest() { gen_latest_url > /dev/null; }
restart_traccar() { systemctl restart "$TRACCAR_SERVICE"; }
show_log() { tail -n50 "$LOG_FILE"; }
show_status() { systemctl status "$TRACCAR_SERVICE" --no-pager; }

# Main loop
main() {
    log "Starting traccar_tools script"
    while true; do
        print_menu
        read -rp "Choose option: " opt
        case "$opt" in
            1) uninstall_traccar      ;;
            2) install_traccar        ;;
            3) upgrade_traccar        ;;
            4) restart_traccar        ;;
            5) show_log               ;;
            6) show_status            ;;
            7) check_latest           ;;
            8) backup_mysql           ;;
            9) import_mysql           ;;
            10) install_mysql_server  ;;
            11) reset_mysql_server    ;;
            x) log "Exiting script"; echo "Goodbye!"; exit 0 ;;
            *) log "Invalid option: $opt"; echo -e "${RED}Invalid option${NORMAL}" ;;
        esac
    done
}

main
