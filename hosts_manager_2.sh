#!/usr/bin/env zsh

# --- Settings ---
HOSTS_FILE="/etc/hosts"
BACKUP_DIR="/etc"
LOG_FILE="$HOME/.hosts_manager.log"
MAX_BACKUPS=5
MIN_FREE_MB=50

# --- Color codes ---
autoload -U colors && colors

RED="$fg[red]"
GREEN="$fg[green]"
YELLOW="$fg[yellow]"
CYAN="$fg[cyan]"
BOLD="$bold_color"
RESET="$reset_color"

# --- Logging ---
log() {
    local msg="$1"
    print -P "[%D{%Y-%m-%d %H:%M:%S}] $msg" | tee -a "$LOG_FILE"
}

die() {
    log "${RED}CRITICAL ERROR:${RESET} $1"
    exit 1
}

# --- Checks ---
check_requirements() {
    local cmds=("sudo" "cp" "tee" "killall" "awk" "df" "sed" "ls" "head")
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null || die "Command not found: $cmd"
    done
    sudo -v || die "No sudo rights"
}

# --- Working with disk ---
check_space() {
    local dir=$(dirname "$1")
    local required=$2
    local available_mb=$(df -m "$dir" | awk 'NR==2 {print $4}')
    (( available_mb >= required )) || die "Need at least ${required}MB free in ${dir} (available ${available_mb}MB)"
}

# --- Backups ---
backup_hosts() {
    check_space "$BACKUP_DIR" "$MIN_FREE_MB"

    local backup_file="$BACKUP_DIR/hosts.backup.$(date +%Y%m%d%H%M%S)"
    log "${CYAN}Creating backup:${RESET} $backup_file"

    sudo cp "$HOSTS_FILE" "$backup_file" || die "Copy error"

    # Backup rotation
    local backups=($BACKUP_DIR/hosts.backup.*(N.Om))
    if (( ${#backups} > MAX_BACKUPS )); then
        log "${YELLOW}Deleting old backups...${RESET}"
        for file in "${backups[@]:$MAX_BACKUPS}"; do
            sudo rm -f "$file" && log "Deleted: $file"
        done
    fi
}

list_backups() {
    local backups=($BACKUP_DIR/hosts.backup.*(N.Om))
    if (( ${#backups} == 0 )); then
        print "${YELLOW}No backups found.${RESET}"
        return 1
    fi
    print "${CYAN}Available backups:${RESET}"
    local i=1
    for bkp in $backups; do
        print "  $i) $(basename $bkp)"
        ((i++))
    done
    return 0
}

restore_hosts() {
    check_space "$LOG_FILE" "$MIN_FREE_MB"

    if ! list_backups; then
        return
    fi

    print -P "%B${YELLOW}Enter backup number to restore (or press Enter to cancel): ${RESET}%b"
    read choice
    if [[ -z "$choice" ]]; then
        log "${YELLOW}Restore cancelled.${RESET}"
        return
    fi

    local backups=($BACKUP_DIR/hosts.backup.*(N.Om))
    if (( choice < 1 || choice > ${#backups} )); then
        print "${RED}Invalid choice.${RESET}"
        return
    fi

    local selected_backup=${backups[$choice]}
    log "${CYAN}Restoring from:${RESET} $selected_backup"
    sudo cp "$selected_backup" "$HOSTS_FILE" || die "Restore error"

    sudo killall -HUP mDNSResponder 2>/dev/null
    log "${GREEN}Successfully restored!${RESET}"
    show_hosts
}

# --- Hosts entries management ---

add_host_entry() {
    print -P "%B${YELLOW}Enter IP address to add:${RESET}%b"
    read ip
    print -P "%B${YELLOW}Enter hostname:${RESET}%b"
    read host
    if [[ -z "$ip" || -z "$host" ]]; then
        log "${RED}IP or hostname cannot be empty.${RESET}"
        return
    fi

    # Simple IP validation (IPv4)
    if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        log "${RED}Invalid IP format.${RESET}"
        return
    fi

    backup_hosts
    echo "$ip    $host" | sudo tee -a "$HOSTS_FILE" >/dev/null
    log "${GREEN}Added entry: $ip $host${RESET}"
    sudo killall -HUP mDNSResponder 2>/dev/null
}

remove_host_entry() {
    print -P "%B${YELLOW}Enter hostname or IP to remove:${RESET}%b"
    read target
    if [[ -z "$target" ]]; then
        log "${RED}Input cannot be empty.${RESET}"
        return
    fi

    backup_hosts
    # sed -i not portable on macOS, use backup file and move
    sudo sed "/$target/d" "$HOSTS_FILE" | sudo tee "$HOSTS_FILE.tmp" >/dev/null
    sudo mv "$HOSTS_FILE.tmp" "$HOSTS_FILE"
    log "${GREEN}Removed entries matching: $target${RESET}"
    sudo killall -HUP mDNSResponder 2>/dev/null
}

# --- Basic Operations ---
reset_hosts() {
    check_space "$LOG_FILE" "$MIN_FREE_MB"

    print -P "%B${YELLOW}Reset hosts file? [y/N]: ${RESET}%b"
    read -q || return
    print

    backup_hosts

    log "${CYAN}Resetting hosts file...${RESET}"
    sudo tee "$HOSTS_FILE" >/dev/null <<'EOF'
##
# Host Database
#
# localhost is used to configure the loopback interface
# when the system is booting.  Do not change this entry.
##
127.0.0.1       localhost
255.255.255.255 broadcasthost
::1             localhost
EOF

    sudo killall -HUP mDNSResponder 2>/dev/null
    log "${GREEN}Successfully reset!${RESET}"
    show_hosts
}

show_hosts() {
    log "${CYAN}Current content:${RESET}"
    print "------------------------------"
    sudo cat "$HOSTS_FILE"
    print "------------------------------"
}

# --- Operations with rights ---
check_permissions() {
    log "${CYAN}Current access rights:${RESET}"
    print "------------------------------"
    ls -le "$HOSTS_FILE" | sudo tee -a "$LOG_FILE"
    print "------------------------------"
}

grant_permissions() {
    print -P "%B${YELLOW}Give write permissions to the hosts file? [y/N]: ${RESET}%b"
    read -q confirm
    print
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo /bin/chmod +a "user:$(whoami):allow write" "$HOSTS_FILE" && \
        log "${GREEN}Write permissions added!${RESET}"
    else
        log "${YELLOW}Operation cancelled.${RESET}"
    fi
}

revoke_permissions() {
    print -P "%B${YELLOW}Remove write permissions? [y/N]: ${RESET}%b"
    read -q confirm
    print
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo /bin/chmod -a "user:$(whoami):allow write" "$HOSTS_FILE" && \
        log "${GREEN}Write permissions revoked!${RESET}"
    else
        log "${YELLOW}Operation cancelled.${RESET}"
    fi
}

# --- Interface ---
print_header() {
    clear
    print -P "%B${CYAN}==============================================%b"
    print -P "%B${CYAN}        Hosts file manager on MacBook        %b"
    print -P "%B${CYAN}==============================================%b"
    print
}

print_menu() {
    print -P "%B${YELLOW}Select action:${RESET}%b"
    print -P "  ${GREEN}1)${RESET} Reset to defaults"
    print -P "  ${GREEN}2)${RESET} Restore from backup"
    print -P "  ${GREEN}3)${RESET} Show current content"
    print -P "  ${GREEN}4)${RESET} Create a backup file"
    print -P "  ${GREEN}5)${RESET} Add host entry"
    print -P "  ${GREEN}6)${RESET} Remove host entry"
    print -P "  ${CYAN}--- Rights management ---${RESET}"
    print -P "  ${GREEN}7)${RESET} Check permissions"
    print -P "  ${GREEN}8)${RESET} Allow editing"
    print -P "  ${GREEN}9)${RESET} Disable editing"
    print -P "  ${CYAN}--------------------------${RESET}"
    print -P "  ${GREEN}0)${RESET} Exit the program"
}

# --- Main loop ---
main() {
    check_requirements

    while true; do
        print_header
        print_menu
        print -P "%B${YELLOW}Your choice: ${RESET}%b"
        read -r choice

        case "$choice" in
            1) reset_hosts ;;
            2) restore_hosts ;;
            3) show_hosts ;;
            4) backup_hosts ;;
            5) add_host_entry ;;
            6) remove_host_entry ;;
            7) check_permissions ;;
            8) grant_permissions ;;
            9) revoke_permissions ;;
            0) break ;;
            *) print -P "${RED}Incorrect choice!${RESET}"; sleep 1 ;;
        esac

        print -P "\n${CYAN}Press Enter to continue...${RESET}"
        read -r
    done

    log "${GREEN}Work completed.${RESET}"
}

# --- Entry point ---
main "$@"
