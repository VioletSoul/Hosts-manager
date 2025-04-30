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
    local cmds=("sudo" "cp" "tee" "killall" "awk" "df")
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
    (( available_mb >= required )) || die "Нужно ${required}MB в ${dir} (доступно ${available_mb}MB)"
}

# --- Backups ---
backup_hosts() {
    check_space "$BACKUP_DIR" "$MIN_FREE_MB"
    
    local backup_file="$BACKUP_DIR/hosts.backup.$(date +%Y%m%d%H%M%S)"
    log "${CYAN}Create a backup:${RESET} $backup_file"
    
    sudo cp "$HOSTS_FILE" "$backup_file" || die "Copy error"
    
    # Backup rotation
    local backups=($BACKUP_DIR/hosts.backup.*(N.Om))
    if (( ${#backups} > MAX_BACKUPS )); then
        log "${YELLOW}Delete old copies...${RESET}"
        for file in "${backups[@]:$MAX_BACKUPS}"; do
            sudo rm -f "$file" && log "Deleted: $file"
        done
    fi
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
        log "${YELLOW}Canceling an operation.${RESET}"
    fi
}

revoke_permissions() {
    print -P "%B${YELLOW}Take away write permissions? [y/N]: ${RESET}%b"
    read -q confirm
    print
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo /bin/chmod -a "user:$(whoami):allow write" "$HOSTS_FILE" && \
        log "${GREEN}Recording rights revoked!${RESET}"
    else
        log "${YELLOW}Canceling an operation.${RESET}"
    fi
}

# --- Basic Operations ---
reset_hosts() {
    check_space "$LOG_FILE" "$MIN_FREE_MB"

    print -P "%B${YELLOW}Reset hosts file? [y/N]: ${RESET}%b"
    read -q || return
    print

    backup_hosts

    log "${CYAN}Reset hosts file...${RESET}"
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

restore_hosts() {
    check_space "$LOG_FILE" "$MIN_FREE_MB"

    print -P "%B${YELLOW}Restore from backup? [y/N]: ${RESET}%b"
    read -q || return
    print

    local latest_backup=($BACKUP_DIR/hosts.backup.*(N.Om[1]))
    [[ -n "$latest_backup" ]] || die "No backups found"

    log "${CYAN}Restoring from:${RESET} $latest_backup"
    sudo cp "$latest_backup" "$HOSTS_FILE" || die "Restore Error"

    sudo killall -HUP mDNSResponder 2>/dev/null
    log "${GREEN}Successfully restored!${RESET}"
    show_hosts
}

show_hosts() {
    log "${CYAN}Current content:${RESET}"
    print "------------------------------"
    sudo cat "$HOSTS_FILE"
    print "------------------------------"
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
    print -P "%B${YELLOW}Select action:%b"
    print -P "  ${GREEN}1)${RESET} Reset to defaults"
    print -P "  ${GREEN}2)${RESET} Restore from backup"
    print -P "  ${GREEN}3)${RESET} Show current content"
    print -P "  ${GREEN}4)${RESET} Create a backup file"
    print -P "  ${CYAN}--- Rights management ---${RESET}"
    print -P "  ${GREEN}5)${RESET} Check permissions"
    print -P "  ${GREEN}6)${RESET} Allow editing"
    print -P "  ${GREEN}7)${RESET} Disable editing"
    print -P "  ${CYAN}--------------------------${RESET}"
    print -P "  ${GREEN}8)${RESET} Exit the program"
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
            5) check_permissions ;;
            6) grant_permissions ;;
            7) revoke_permissions ;;
            8) break ;;
            *) print -P "${RED}Incorrect choice!${RESET}"; sleep 1 ;;
        esac

        print -P "\n${CYAN}Press Enter to continue...${RESET}"
        read -r
    done

    log "${GREEN}Work completed.${RESET}"
}

# --- Entry point ---
main "$@"
