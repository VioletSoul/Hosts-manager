#!/usr/bin/env zsh

# --- Настройки ---
HOSTS_FILE="/etc/hosts"
BACKUP_DIR="/etc"
LOG_FILE="$HOME/.hosts_manager.log"
MAX_BACKUPS=5
MIN_FREE_MB=50

# --- Цветовые коды ---
autoload -U colors && colors

RED="$fg[red]"
GREEN="$fg[green]"
YELLOW="$fg[yellow]"
CYAN="$fg[cyan]"
BOLD="$bold_color"
RESET="$reset_color"

# --- Логирование ---
log() {
    local msg="$1"
    print -P "[%D{%Y-%m-%d %H:%M:%S}] $msg" | tee -a "$LOG_FILE"
}

die() {
    log "${RED}КРИТИЧЕСКАЯ ОШИБКА:${RESET} $1"
    exit 1
}

# --- Проверки ---
check_requirements() {
    local cmds=("sudo" "cp" "tee" "killall" "awk" "df")
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null || die "Не найдена команда: $cmd"
    done
    sudo -v || die "Нет прав sudo"
}

# --- Работа с диском ---
check_space() {
    local dir=$(dirname "$1")
    local required=$2
    local available_mb=$(df -m "$dir" | awk 'NR==2 {print $4}')
    (( available_mb >= required )) || die "Нужно ${required}MB в ${dir} (доступно ${available_mb}MB)"
}

# --- Бэкапы ---
backup_hosts() {
    check_space "$BACKUP_DIR" "$MIN_FREE_MB"
    
    local backup_file="$BACKUP_DIR/hosts.backup.$(date +%Y%m%d%H%M%S)"
    log "${CYAN}Создаем бэкап:${RESET} $backup_file"
    
    sudo cp "$HOSTS_FILE" "$backup_file" || die "Ошибка копирования"
    
    # Ротация бэкапов
    local backups=($BACKUP_DIR/hosts.backup.*(N.Om))
    if (( ${#backups} > MAX_BACKUPS )); then
        log "${YELLOW}Удаляем старые копии...${RESET}"
        for file in "${backups[@]:$MAX_BACKUPS}"; do
            sudo rm -f "$file" && log "Удалено: $file"
        done
    fi
}

# --- Основные операции ---
reset_hosts() {
    check_space "$LOG_FILE" "$MIN_FREE_MB"
    
    print -P "%B${YELLOW}Сбросить файл hosts? [y/N]: ${RESET}%b"
    read -q || return
    print
    
    backup_hosts
    
    log "${CYAN}Сброс файла hosts...${RESET}"
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
    log "${GREEN}Успешно сброшено!${RESET}"
    show_hosts
}

restore_hosts() {
    check_space "$LOG_FILE" "$MIN_FREE_MB"
    
    print -P "%B${YELLOW}Восстановить из резервной копии? [y/N]: ${RESET}%b"
    read -q || return
    print
    
    local latest_backup=($BACKUP_DIR/hosts.backup.*(N.Om[1]))
    [[ -n "$latest_backup" ]] || die "Резервные копии не найдены"
    
    log "${CYAN}Восстанавливаем из:${RESET} $latest_backup"
    sudo cp "$latest_backup" "$HOSTS_FILE" || die "Ошибка восстановления"
    
    sudo killall -HUP mDNSResponder 2>/dev/null
    log "${GREEN}Успешно восстановлено!${RESET}"
    show_hosts
}

show_hosts() {
    log "${CYAN}Текущее содержимое:${RESET}"
    print "------------------------------"
    sudo cat "$HOSTS_FILE"
    print "------------------------------"
}

# --- Интерфейс ---
print_header() {
    clear
    print -P "%B${CYAN}==============================================%b"
    print -P "%B${CYAN}        Менеджер файла hosts на MacBook        %b"
    print -P "%B${CYAN}==============================================%b"
    print
}

print_menu() {
    print -P "%B${YELLOW}Выберите действие:%b"
    print -P "  ${GREEN}1)${RESET} Сбросить файл hosts к значениям по умолчанию"
    print -P "  ${GREEN}2)${RESET} Восстановить из резервной копии"
    print -P "  ${GREEN}3)${RESET} Показать текущее содержимое"
    print -P "  ${GREEN}4)${RESET} Выйти из программы"
}

# --- Главный цикл ---
main() {
    check_requirements
    
    while true; do
        print_header
        print_menu
        print -P "%B${YELLOW}Ваш выбор: ${RESET}%b"
        read -r choice
        
        case "$choice" in
            1) reset_hosts ;;
            2) restore_hosts ;;
            3) show_hosts ;;
            4) break ;;
            *) print -P "${RED}Некорректный выбор!${RESET}"; sleep 1 ;;
        esac
        
        print -P "\n${CYAN}Нажмите Enter для продолжения...${RESET}"
        read -r
    done
    
    log "${GREEN}Работа завершена.${RESET}"
}

# --- Точка входа ---
main "$@"

