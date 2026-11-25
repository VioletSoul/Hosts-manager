#!/usr/bin/env zsh
# Менеджер файла hosts для macOS (final)

# --- Настройки ---
: ${HOSTS_FILE:=/etc/hosts}
: ${BACKUP_DIR:=/etc/hosts.backups}
: ${LOG_FILE:=$HOME/.hosts_manager.log}
: ${MAX_BACKUPS:=5}
: ${MIN_FREE_MB:=50}

# --- Цвета ---
autoload -U colors && colors
RED="$fg[red]"
GREEN="$fg[green]"
YELLOW="$fg[yellow]"
CYAN="$fg[cyan]"
RESET="$reset_color"

typeset -ga backups

# --- Логирование ---
log() {
    local line
    line="$(print -P "[%D{%Y-%m-%d %H:%M:%S}] $1")"
    print -r -- "$line"
    print -r -- "$line" | sed $'s/\x1b\\[[0-9;]*m//g' >> "$LOG_FILE" 2>/dev/null
}

err() { log "${RED}Ошибка:${RESET} $1"; }

die() {
    err "$1"
    exit 1
}

# Экранирует % в пользовательском вводе перед передачей в print -P / log
esc() { print -r -- "${1//\%/%%}"; }

confirm() {
    print -nP "%B${YELLOW}$1 [y/N]: ${RESET}%b"
    local ans
    read -rk 1 ans
    print
    [[ "$ans" == [yYдД] ]]
}

# --- Проверки ---
check_requirements() {
    (( EUID != 0 )) || die "Не запускайте скрипт от root: он сам использует sudo там, где нужно"
    local cmd
    for cmd in sudo cp awk df sed mktemp date tail ls chmod killall dscacheutil id; do
        command -v "$cmd" >/dev/null || die "Не найдена команда: $cmd"
    done
    touch "$LOG_FILE" 2>/dev/null || die "Нельзя писать в лог: $LOG_FILE"
    sudo -v || die "Нет прав sudo"
}

check_space() {
    local dir="$1" required="$2" available_mb
    available_mb=$(df -m "$dir" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ "$available_mb" != <-> ]]; then
        err "Не удалось определить свободное место в $(esc "$dir")"
        return 1
    fi
    if (( available_mb < required )); then
        err "Нужно минимум ${required} МБ в $(esc "$dir") (доступно ${available_mb} МБ)"
        return 1
    fi
}

# --- Валидация ---
is_valid_ip() {
    local ip="$1" o
    if [[ "$ip" =~ '^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$' ]]; then
        for o in "${match[@]}"; do
            (( 10#$o <= 255 )) || return 1
        done
        return 0
    fi
    [[ "$ip" == *:* && "$ip" =~ '^[0-9a-fA-F:.]+$' ]]
}

is_valid_host() {
    [[ "$1" =~ '^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$' ]]
}

# Проверка синтаксиса файла. Печатает ошибки, возвращает 1 если они есть.
validate_file() {
    awk '
    function valid_ip(s,   n, a, i) {
        if (s ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
            n = split(s, a, ".")
            for (i = 1; i <= 4; i++) if (a[i] + 0 > 255) return 0
            return 1
        }
        if (s ~ /:/ && s ~ /^[0-9a-fA-F:.]+(%[A-Za-z0-9]+)?$/) return 1
        return 0
    }
    {
        line = $0
        sub(/#.*/, "", line)
        n = split(line, f, " ")
        if (n == 0) next
        if (!valid_ip(f[1])) {
            printf "Строка %d: неверный IP: %s\n", NR, $0
            err++
            next
        }
        if (n < 2) {
            printf "Строка %d: нет имён хостов: %s\n", NR, $0
            err++
        }
    }
    END { if (err > 0) exit 1 }
    ' "$1"
}

# --- Бэкапы ---
get_backups() {
    backups=($BACKUP_DIR/hosts.backup.*(N.om))   # от новых к старым
}

backup_hosts() {
    sudo mkdir -p "$BACKUP_DIR" || { err "Не удалось создать $BACKUP_DIR"; return 1 }
    check_space "$BACKUP_DIR" "$MIN_FREE_MB" || return 1

    local backup_file="$BACKUP_DIR/hosts.backup.$(date +%Y%m%d%H%M%S)"
    log "${CYAN}Создаём бэкап:${RESET} $backup_file"
    sudo cp -p "$HOSTS_FILE" "$backup_file" || { err "Не удалось создать бэкап"; return 1 }

    get_backups
    if (( ${#backups} > MAX_BACKUPS )); then
        log "${YELLOW}Удаляем старые копии...${RESET}"
        local old
        for old in "${backups[$((MAX_BACKUPS + 1)),-1]}"; do
            sudo rm -f "$old" && log "Удалено: $old"
        done
    fi
}

list_backups() {
    print -P "${CYAN}Доступные копии (1 = самая свежая):${RESET}"
    local i=1 b ts
    for b in "${backups[@]}"; do
        ts="${b##*.}"
        print -P "  ${GREEN}${i})${RESET} ${ts[1,4]}-${ts[5,6]}-${ts[7,8]} ${ts[9,10]}:${ts[11,12]}:${ts[13,14]}"
        (( i++ ))
    done
}

# --- Применение нового содержимого hosts ---
flush_dns() {
    sudo dscacheutil -flushcache 2>/dev/null
    sudo killall -HUP mDNSResponder 2>/dev/null
}

# apply_hosts_file <файл> [novalidate]
# Проверяет файл, делает бэкап текущего hosts, записывает новый, сбрасывает DNS-кэш.
# Запись выполняется на месте (cp), поэтому владелец, права и ACL файла сохраняются.
apply_hosts_file() {
    local src="$1" mode="$2" out
    if [[ "$mode" != novalidate ]]; then
        if ! out="$(validate_file "$src")"; then
            print -r -- "$out"
            err "В файле есть синтаксические ошибки, применение отменено"
            return 1
        fi
    fi
    backup_hosts || return 1
    sudo cp "$src" "$HOSTS_FILE" || { err "Не удалось записать $HOSTS_FILE (возможно, файл защищён флагом)"; return 1 }
    flush_dns
}

# --- Основные операции ---
show_hosts() {
    log "${CYAN}Текущее содержимое:${RESET}"
    print "------------------------------"
    cat "$HOSTS_FILE"
    print "------------------------------"
}

reset_hosts() {
    confirm "Сбросить файл hosts к значениям по умолчанию?" || { log "${YELLOW}Отмена.${RESET}"; return }
    local tmp; tmp=$(mktemp) || { err "mktemp не сработал"; return 1 }
    cat > "$tmp" <<'EOF'
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
    log "${CYAN}Сброс файла hosts...${RESET}"
    if apply_hosts_file "$tmp" novalidate; then
        log "${GREEN}Успешно сброшено!${RESET}"
        show_hosts
    fi
    rm -f "$tmp"
}

restore_hosts() {
    get_backups
    if (( ${#backups} == 0 )); then
        print -P "${YELLOW}Резервные копии не найдены.${RESET}"
        return 1
    fi
    list_backups
    local choice
    print -nP "%B${YELLOW}Номер копии (Enter - отмена): ${RESET}%b"
    read -r choice
    if [[ -z "$choice" ]]; then
        log "${YELLOW}Восстановление отменено.${RESET}"
        return
    fi
    if [[ "$choice" != <-> ]] || (( 10#$choice < 1 || 10#$choice > ${#backups} )); then
        err "Неверный номер"
        return 1
    fi

    local sel="${backups[$((10#$choice))]}" tmp
    confirm "Восстановить из ${sel:t}? Текущий файл будет сохранён в бэкап" || { log "${YELLOW}Отмена.${RESET}"; return }

    # Копируем выбранную копию заранее: ротация при новом бэкапе может её удалить
    tmp=$(mktemp) || { err "mktemp не сработал"; return 1 }
    sudo cp "$sel" "$tmp" && sudo chmod 644 "$tmp" || { err "Не удалось прочитать копию"; rm -f "$tmp"; return 1 }

    log "${CYAN}Восстанавливаем из:${RESET} $sel"
    if apply_hosts_file "$tmp" novalidate; then
        log "${GREEN}Успешно восстановлено!${RESET}"
        show_hosts
    fi
    rm -f "$tmp"
}

# --- Записи hosts ---
add_host_entry() {
    local ip host
    print -nP "%B${YELLOW}IP-адрес: ${RESET}%b"; read -r ip
    print -nP "%B${YELLOW}Имя хоста: ${RESET}%b"; read -r host

    if [[ -z "$ip" || -z "$host" ]]; then
        err "IP и имя хоста не могут быть пустыми"; return 1
    fi
    is_valid_ip "$ip" || { err "Неверный формат IP (поддерживаются IPv4 и IPv6)"; return 1 }
    is_valid_host "$host" || { err "Неверное имя хоста"; return 1 }

    if awk -v ip="$ip" -v h="$host" '
        { sub(/#.*/, ""); for (i = 2; i <= NF; i++) if ($1 == ip && $i == h) f = 1 }
        END { exit (f ? 0 : 1) }' "$HOSTS_FILE"; then
        err "Такая запись уже есть"; return 1
    fi

    local tmp; tmp=$(mktemp) || { err "mktemp не сработал"; return 1 }
    cat "$HOSTS_FILE" > "$tmp"
    [[ -n "$(tail -c1 "$tmp")" ]] && print >> "$tmp"
    print -r -- "$ip    $host" >> "$tmp"

    if apply_hosts_file "$tmp"; then
        log "${GREEN}Добавлена запись: $(esc "$ip") $(esc "$host")${RESET}"
    fi
    rm -f "$tmp"
}

# hosts_filter <list|filter> <цель> <файл>
# Совпадение - точное равенство IP или имени хоста. Строки с localhost и broadcasthost защищены.
hosts_filter() {
    awk -v mode="$1" -v t="$2" '
    {
        line = $0
        sub(/#.*/, "", line)
        n = split(line, f, " ")
        if (n == 0) { if (mode == "filter") print; next }
        prot = 0; hit = 0
        for (i = 1; i <= n; i++) {
            if (i >= 2 && (f[i] == "localhost" || f[i] == "broadcasthost")) prot = 1
            if (f[i] == t) hit = 1
        }
        if (hit && !prot) {
            if (mode == "list") printf "  строка %d: %s\n", NR, $0
        } else if (mode == "filter") print
    }' "$3"
}

remove_host_entry() {
    local target
    print -nP "%B${YELLOW}Имя хоста или IP для удаления: ${RESET}%b"
    read -r target
    [[ -n "$target" ]] || { err "Ввод не может быть пустым"; return 1 }

    local found; found="$(hosts_filter list "$target" "$HOSTS_FILE")"
    if [[ -z "$found" ]]; then
        print -P "${YELLOW}Подходящих записей нет (записи с localhost/broadcasthost защищены, используйте сброс).${RESET}"
        return 1
    fi
    print -P "${CYAN}Будут удалены:${RESET}"
    print -r -- "$found"
    confirm "Удалить эти записи?" || { log "${YELLOW}Отмена.${RESET}"; return }

    local tmp; tmp=$(mktemp) || { err "mktemp не сработал"; return 1 }
    if hosts_filter filter "$target" "$HOSTS_FILE" > "$tmp" && apply_hosts_file "$tmp"; then
        log "${GREEN}Удалены записи для: $(esc "$target")${RESET}"
    fi
    rm -f "$tmp"
}

validate_hosts() {
    print -P "${CYAN}Проверка синтаксиса hosts...${RESET}"
    local out
    if out="$(validate_file "$HOSTS_FILE")"; then
        print -P "${GREEN}Ошибок не найдено.${RESET}"
    else
        print -r -- "$out"
        print -P "${RED}Найдено ошибок: $(print -r -- "$out" | wc -l | tr -d ' ')${RESET}"
    fi
}

check_duplicates() {
    print -P "${CYAN}Поиск дубликатов IP-хост...${RESET}"
    local report
    report="$(awk '
    {
        line = $0
        sub(/#.*/, "", line)
        n = split(line, f, " ")
        if (n < 2) next
        for (i = 2; i <= n; i++) {
            k = f[1] " " f[i]
            c[k]++
            ln[k] = ln[k] (ln[k] == "" ? "" : ", ") NR
        }
    }
    END { for (k in c) if (c[k] > 1) printf "Дубликат: %s (строки: %s)\n", k, ln[k] }
    ' "$HOSTS_FILE")"
    if [[ -z "$report" ]]; then
        print -P "${GREEN}Дубликатов нет.${RESET}"
    else
        print -P "${YELLOW}Найдены дубликаты:${RESET}"
        print -r -- "$report"
    fi
}

# --- Экспорт / импорт ---
export_hosts() {
    local p
    print -nP "%B${YELLOW}Путь для экспорта: ${RESET}%b"
    read -r p
    [[ -n "$p" ]] || { err "Путь не может быть пустым"; return 1 }
    p="${p/#\~/$HOME}"
    if [[ -e "$p" ]]; then
        confirm "Файл $(esc "$p") существует. Перезаписать?" || { log "${YELLOW}Отмена.${RESET}"; return }
    fi
    cp "$HOSTS_FILE" "$p" && log "${GREEN}Экспортировано в $(esc "$p")${RESET}" || err "Не удалось экспортировать"
}

import_hosts() {
    local p
    print -nP "%B${YELLOW}Путь к файлу для импорта: ${RESET}%b"
    read -r p
    [[ -n "$p" ]] || { err "Путь не может быть пустым"; return 1 }
    p="${p/#\~/$HOME}"
    [[ -f "$p" ]] || { err "Файл не найден: $(esc "$p")"; return 1 }

    confirm "Заменить hosts содержимым $(esc "$p")? Текущий файл будет сохранён в бэкап" || { log "${YELLOW}Отмена.${RESET}"; return }
    if apply_hosts_file "$p"; then
        log "${GREEN}Импортировано из $(esc "$p")${RESET}"
        show_hosts
    fi
}

# --- Права ---
check_permissions() {
    log "${CYAN}Текущие права доступа:${RESET}"
    print "------------------------------"
    ls -leO "$HOSTS_FILE"
    print "------------------------------"
}

grant_permissions() {
    if confirm "Дать вашему пользователю право записи в hosts?"; then
        sudo /bin/chmod +a "user:$(id -un):allow write" "$HOSTS_FILE" && \
            log "${GREEN}Права на запись добавлены!${RESET}" || err "Не удалось изменить права"
    else
        log "${YELLOW}Отмена.${RESET}"
    fi
}

revoke_permissions() {
    if confirm "Забрать право записи?"; then
        sudo /bin/chmod -a "user:$(id -un):allow write" "$HOSTS_FILE" && \
            log "${GREEN}Права на запись отозваны!${RESET}" || err "Не удалось изменить права (возможно, ACL не было)"
    else
        log "${YELLOW}Отмена.${RESET}"
    fi
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
    print -P "  ${GREEN}1)${RESET} Сбросить к значениям по умолчанию"
    print -P "  ${GREEN}2)${RESET} Восстановить из резервной копии"
    print -P "  ${GREEN}3)${RESET} Показать текущее содержимое"
    print -P "  ${GREEN}4)${RESET} Создать бэкап файла"
    print -P "  ${GREEN}5)${RESET} Добавить запись"
    print -P "  ${GREEN}6)${RESET} Удалить запись"
    print -P "  ${GREEN}7)${RESET} Проверить синтаксис"
    print -P "  ${GREEN}8)${RESET} Найти дубликаты"
    print -P "  ${GREEN}9)${RESET} Экспорт в файл"
    print -P "  ${GREEN}10)${RESET} Импорт из файла"
    print -P "  ${CYAN}--- Управление правами ---${RESET}"
    print -P "  ${GREEN}11)${RESET} Проверить права доступа"
    print -P "  ${GREEN}12)${RESET} Разрешить редактирование"
    print -P "  ${GREEN}13)${RESET} Запретить редактирование"
    print -P "  ${CYAN}--------------------------${RESET}"
    print -P "  ${GREEN}0)${RESET} Выйти из программы"
}

main() {
    check_requirements

    local choice
    while true; do
        print_header
        print_menu
        print -nP "%B${YELLOW}Ваш выбор: ${RESET}%b"
        read -r choice

        case "$choice" in
            1) reset_hosts ;;
            2) restore_hosts ;;
            3) show_hosts ;;
            4) backup_hosts ;;
            5) add_host_entry ;;
            6) remove_host_entry ;;
            7) validate_hosts ;;
            8) check_duplicates ;;
            9) export_hosts ;;
            10) import_hosts ;;
            11) check_permissions ;;
            12) grant_permissions ;;
            13) revoke_permissions ;;
            0) break ;;
            *) print -P "${RED}Некорректный выбор!${RESET}"; sleep 1 ;;
        esac

        print -P "\n${CYAN}Нажмите Enter для продолжения...${RESET}"
        read -r
    done

    log "${GREEN}Работа завершена.${RESET}"
}

[[ -n "$HOSTS_MANAGER_NO_MAIN" ]] || main "$@"
