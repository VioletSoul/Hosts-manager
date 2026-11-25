#!/usr/bin/env zsh
# Hosts Manager for macOS — English / Русский
emulate -R zsh
setopt PIPE_FAIL
umask 077
HOSTS_FILE=/etc/hosts
BACKUP_DIR=/etc/hosts.backups
LOG_FILE="$HOME/.hosts_manager.log"
MAX_BACKUPS=5
typeset -A M
typeset -a backups
typeset WORK=''

# --- Colors ---
C_RESET=$'\e[0m'
C_BOLD=$'\e[1m'
C_RED=$'\e[31m'
C_GREEN=$'\e[32m'
C_YELLOW=$'\e[33m'
C_CYAN=$'\e[36m'

cleanup() { [[ -n "$WORK" ]] && /bin/rm -rf -- "$WORK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say()  { printf '%s\n' "$*"; }
info() { printf '%s%s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
bad()  { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET"; }

# log <color> <message>: colored on screen, plain text in the log file
log() {
    local color="$1"; shift
    local ts="[$(/bin/date '+%Y-%m-%d %H:%M:%S')]"
    printf '%s%s %s%s\n' "$color" "$ts" "$*" "$C_RESET"
    printf '%s %s\n' "$ts" "$*" >> "$LOG_FILE"
}

ask() {
    printf '%s%s%s%s' "$C_BOLD" "$C_YELLOW" "$1" "$C_RESET"
    IFS= read -r REPLY
}

choose_language() {
    local answer
    while true; do
        /usr/bin/clear
        printf '\n%s%sSelect language / Выберите язык:%s\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
        printf '  %s1)%s English\n  %s2)%s Русский\n  %s0)%s Exit / Выход\n' \
            "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET"
        printf '%s> %s' "$C_BOLD" "$C_RESET"
        read -r answer || return 1
        case "$answer" in
            1) UI_LANG=en; break ;;
            2) UI_LANG=ru; break ;;
            0) return 1 ;;
            *) bad 'Choose 0, 1 or 2 / Выберите 0, 1 или 2.'; sleep 1 ;;
        esac
    done
    if [[ "$UI_LANG" == en ]]; then
        M=(title 'Hosts Manager for macOS' select 'Select action:' sect 'Rights management'
        reset 'Reset to defaults' restore 'Restore from backup' show 'Show current contents'
        backup 'Create a backup' add 'Add entry' remove 'Remove matching lines'
        validate 'Check basic syntax' duplicates 'Find duplicate pairs' export 'Export to file'
        import 'Import from file' rights 'Inspect permissions' grant 'Grant write ACL'
        revoke 'Remove write ACL' exit 'Exit' choice 'Your choice: '
        invalid 'Invalid input.' pause 'Press Enter to continue...' cancel 'Cancelled.'
        confirm 'Continue? [y/N]: ' ip 'IP address: ' host 'Hostname: ' target 'Exact IP or hostname: '
        path 'File path: ' number 'Backup number (Enter to cancel): '
        done 'Completed.' fail 'Operation failed.' nobackups 'No backups found.'
        root 'Run as your regular user, not root.' platform 'This script requires macOS.'
        missing 'Required command unavailable:' sudo 'Unable to obtain sudo privileges.'
        logfail 'Cannot open log file.' nomatch 'No removable matches. Localhost lines are protected.'
        preview 'Entire lines to remove:' overwrite 'Destination exists; overwrite it?'
        warning 'This changes the hosts file. A backup will be created first.'
        aclwarn 'This changes only your explicit write ACL, not other permissions.'
        badfile 'File is missing, unreadable, empty, or invalid.'
        syntaxok 'Basic syntax check passed (not full IPv6/hostname validation).'
        syntaxbad 'Invalid address or missing hostname on line(s):'
        duptitle 'Repeated IP-hostname pairs (count, IP, hostname):' none 'None found.'
        newbackup 'Backup created:' restored 'Restore source:' dnserror 'File saved; DNS refresh reported an error.'
        locked 'Another instance is running, or a stale lock exists:'
        space 'Less than 50 MB available, or free space could not be determined.'
        exists 'This mapping already exists.'
        )
    else
        M=(title 'Менеджер файла hosts для macOS' select 'Выберите действие:' sect 'Управление правами'
        reset 'Сбросить к значениям по умолчанию' restore 'Восстановить из резервной копии'
        show 'Показать текущее содержимое' backup 'Создать бэкап' add 'Добавить запись'
        remove 'Удалить совпадающие строки' validate 'Проверить базовый синтаксис'
        duplicates 'Найти дубликаты пар' export 'Экспорт в файл' import 'Импорт из файла'
        rights 'Посмотреть права доступа' grant 'Добавить ACL на запись'
        revoke 'Убрать ACL на запись' exit 'Выход' choice 'Ваш выбор: '
        invalid 'Некорректный ввод.' pause 'Нажмите Enter для продолжения...' cancel 'Отменено.'
        confirm 'Продолжить? [y/д/N]: ' ip 'IP-адрес: ' host 'Имя хоста: '
        target 'Точный IP или имя хоста: ' path 'Путь к файлу: '
        number 'Номер копии (Enter — отмена): ' done 'Готово.' fail 'Операция не выполнена.'
        nobackups 'Резервные копии не найдены.' root 'Запустите от обычного пользователя, не от root.'
        platform 'Скрипт предназначен для macOS.' missing 'Недоступна необходимая команда:'
        sudo 'Не удалось получить права sudo.' logfail 'Не удалось открыть журнал.'
        nomatch 'Нет совпадений для удаления. Строки с localhost защищены.'
        preview 'Будут удалены строки целиком:' overwrite 'Файл назначения существует. Перезаписать?'
        warning 'Файл hosts будет изменён. Сначала будет создан бэкап.'
        aclwarn 'Меняется только ваша явная ACL на запись, а не остальные права.'
        badfile 'Файл отсутствует, недоступен, пуст или некорректен.'
        syntaxok 'Базовая проверка пройдена (не полная проверка IPv6 и имён).'
        syntaxbad 'Некорректный адрес или отсутствующее имя в строках:'
        duptitle 'Повторяющиеся пары IP–хост (число, IP, имя):' none 'Не найдено.'
        newbackup 'Создан бэкап:' restored 'Источник восстановления:'
        dnserror 'Файл сохранён; при обновлении DNS возникла ошибка.'
        locked 'Другой экземпляр уже работает или осталась старая блокировка:'
        space 'Доступно менее 50 МБ или не удалось определить свободное место.'
        exists 'Такая запись уже есть.'
        )
    fi
}

confirm() {
    local REPLY
    ask "${M[confirm]}" || return 1
    [[ "$REPLY" == [yY] || "$REPLY" == [дД] ]]
}

# Basic parser: full IPv4 bounds; deliberately permissive IPv6 syntax.
validate_file() {
    /usr/bin/awk '
    function ip(s, a,n,i) {
        if(s ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
            n=split(s,a,"."); for(i=1;i<=n;i++) if(length(a[i])>3 || a[i]+0>255) return 0
            return 1
        }
        return s ~ /:/ && s ~ /^[0-9a-fA-F:]+$/
    }
    { t=$0; sub(/#.*/,"",t); n=split(t,f," "); if(!n) next
      if(n<2 || !ip(f[1])) { print NR; bad=1 } }
    END {exit bad}
    ' "$1"
}

get_backups() { backups=("$BACKUP_DIR"/hosts.backup.*(N.om)); }

backup_hosts() {
    local free stamp dest f
    free=$(/bin/df -Pm "$BACKUP_DIR" | /usr/bin/awk 'NR==2 {print $4}')
    [[ "$free" == <-> ]] && (( free >= 50 )) || { bad "${M[space]}"; return 1; }
    stamp=$(/bin/date '+%Y%m%d%H%M%S')
    # mktemp creates a unique filename even within the same second.
    dest=$(/usr/bin/sudo /usr/bin/mktemp "$BACKUP_DIR/hosts.backup.$stamp.XXXXXXXX") || return 1
    if ! /usr/bin/sudo /bin/cp -p "$HOSTS_FILE" "$dest"; then
        /usr/bin/sudo /bin/rm -f "$dest"; return 1
    fi
    log "$C_CYAN" "${M[newbackup]} $dest"
    get_backups
    for f in "${backups[@]:$MAX_BACKUPS}"; do
        /usr/bin/sudo /bin/rm -f "$f" || return 1
    done
}

apply_file() {
    local source="$1" result
    if ! result=$(validate_file "$source"); then
        bad "${M[syntaxbad]}"; say "$result"; return 1
    fi
    [[ -s "$source" ]] || { bad "${M[badfile]}"; return 1; }
    backup_hosts || return 1
    # In-place update preserves the existing destination inode and its ACL.
    # Not atomic: do not interrupt the copy. A backup is made first.
    /usr/bin/sudo /bin/cp "$source" "$HOSTS_FILE" || return 1
    log "$C_GREEN" "${M[done]}"
    if ! /usr/bin/sudo /usr/bin/dscacheutil -flushcache ||
       ! /usr/bin/sudo /usr/bin/killall -HUP mDNSResponder; then
        warn "${M[dnserror]}"
    fi
}

filter_hosts() {
    /usr/bin/awk -v mode="$1" -v target="$2" '
    {t=$0; sub(/#.*/,"",t); n=split(t,f," "); hit=0; protect=0
     for(i=1;i<=n;i++) {
       if(f[i]==target) hit=1
       if(i>1 && (f[i]=="localhost" || f[i]=="broadcasthost")) protect=1
     }
     if(hit && !protect) {if(mode=="list") print NR ": " $0}
     else if(mode=="filter") print
    }' "$HOSTS_FILE"
}

reset_hosts() {
    warn "${M[warning]}"; confirm || { warn "${M[cancel]}"; return 0; }
    /bin/cat > "$WORK/new" <<'EOF'
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
    apply_file "$WORK/new"
}

restore_hosts() {
    get_backups
    (( ${#backups} )) || { warn "${M[nobackups]}"; return 0; }
    local i=1 b REPLY selected
    for b in "${backups[@]}"; do
        printf '  %s%d)%s %s\n' "$C_GREEN" "$i" "$C_RESET" "${b:t}"
        ((i++))
    done
    ask "${M[number]}" || return 1
    [[ -n "$REPLY" ]] || { warn "${M[cancel]}"; return 0; }
    [[ "$REPLY" == <-> && ${#REPLY} -le 6 ]] || { bad "${M[invalid]}"; return 1; }
    i=$((10#$REPLY))
    ((i>=1 && i<=${#backups})) || { bad "${M[invalid]}"; return 1; }
    selected="${backups[$i]}"
    log "$C_CYAN" "${M[restored]} $selected"
    warn "${M[warning]}"; confirm || { warn "${M[cancel]}"; return 0; }
    # Stage before rotation, using a user-owned private temporary file.
    /usr/bin/sudo /bin/cat "$selected" > "$WORK/new" || return 1
    apply_file "$WORK/new"
}

add_entry() {
    local REPLY ip host
    ask "${M[ip]}" || return 1; ip="$REPLY"
    ask "${M[host]}" || return 1; host="$REPLY"
    [[ "$host" =~ '^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$' ]] || { bad "${M[invalid]}"; return 1; }
    printf '%s %s\n' "$ip" "$host" > "$WORK/check"
    validate_file "$WORK/check" >/dev/null || { bad "${M[invalid]}"; return 1; }
    if /usr/bin/awk -v ip="$ip" -v h="$host" '
      {sub(/#.*/,""); for(i=2;i<=NF;i++) if($1==ip && $i==h) found=1}
      END{exit !found}' "$HOSTS_FILE"; then
        warn "${M[exists]}"; return 0
    fi
    /bin/cat "$HOSTS_FILE" > "$WORK/new" || return 1
    # A blank separator also handles a missing final newline.
    printf '\n%s    %s\n' "$ip" "$host" >> "$WORK/new"
    apply_file "$WORK/new"
}

remove_entry() {
    local REPLY target found
    ask "${M[target]}" || return 1; target="$REPLY"
    [[ -n "$target" ]] || return 1
    found=$(filter_hosts list "$target") || return 1
    [[ -n "$found" ]] || { warn "${M[nomatch]}"; return 0; }
    info "${M[preview]}"; say "$found"
    confirm || { warn "${M[cancel]}"; return 0; }
    filter_hosts filter "$target" > "$WORK/new" || return 1
    apply_file "$WORK/new"
}

check_syntax() {
    local report
    if report=$(validate_file "$HOSTS_FILE"); then ok "${M[syntaxok]}"
    else bad "${M[syntaxbad]}"; say "$report"; return 1; fi
}

duplicates() {
    local report
    report=$(/usr/bin/awk '
      {sub(/#.*/,""); for(i=2;i<=NF;i++) c[$1 " " $i]++}
      END{for(k in c) if(c[k]>1) print c[k],k}' "$HOSTS_FILE") || return 1
    if [[ -n "$report" ]]; then warn "${M[duptitle]}"; say "$report"
    else ok "${M[none]}"; fi
}

file_operation() {
    local mode="$1" REPLY p
    ask "${M[path]}" || return 1; p="$REPLY"
    [[ -n "$p" ]] || return 1
    [[ "$p" == '~' ]] && p="$HOME"
    [[ "$p" == '~/'* ]] && p="$HOME/${p#\~/}"
    p="${p:a}"
    if [[ "$mode" == import ]]; then
        [[ -f "$p" && -r "$p" && -s "$p" ]] || { bad "${M[badfile]}"; return 1; }
        /bin/cat "$p" > "$WORK/new" || return 1
        warn "${M[warning]}"; confirm || { warn "${M[cancel]}"; return 0; }
        apply_file "$WORK/new"
    else
        [[ ! -d "$p" && ! -L "$p" && "$p" != "${HOSTS_FILE:A}" && "$p" != "${HOSTS_FILE:a}" ]] || return 1
        if [[ -e "$p" ]]; then warn "${M[overwrite]}"; confirm || return 0; fi
        /bin/cp "$HOSTS_FILE" "$p" || return 1
        log "$C_GREEN" "${M[done]} $p"
    fi
}

acl_operation() {
    warn "${M[aclwarn]}"; confirm || { warn "${M[cancel]}"; return 0; }
    /usr/bin/sudo /bin/chmod "$1" "user:$(/usr/bin/id -un):allow write" "$HOSTS_FILE" || return 1
    log "$C_GREEN" "${M[done]}"
}

print_menu() {
    local -a keys=(reset restore show backup add remove validate duplicates export import rights grant revoke)
    local i=1 key
    /usr/bin/clear
    printf '\n%s%s==============================================\n%s\n==============================================%s\n\n' \
        "$C_BOLD" "$C_CYAN" "${M[title]}" "$C_RESET"
    printf '%s%s%s%s\n' "$C_BOLD" "$C_YELLOW" "${M[select]}" "$C_RESET"
    for key in "${keys[@]}"; do
        if (( i == 11 )); then
            printf '  %s--- %s ---%s\n' "$C_CYAN" "${M[sect]}" "$C_RESET"
        fi
        printf '  %s%2d)%s %s\n' "$C_GREEN" "$i" "$C_RESET" "${M[$key]}"
        ((i++))
    done
    printf '  %s--------------------------%s\n' "$C_CYAN" "$C_RESET"
    printf '  %s%2d)%s %s\n' "$C_GREEN" 0 "$C_RESET" "${M[exit]}"
}

main() {
    choose_language || return 0
    [[ "$OSTYPE" == darwin* ]] || { bad "${M[platform]}"; return 1; }
    (( EUID != 0 )) || { bad "${M[root]}"; return 1; }
    [[ -t 0 && -t 1 ]] || return 1
    local cmd REPLY action
    for cmd in sudo cp cat rm mkdir mktemp date df awk chmod ls id dscacheutil killall clear; do
        command -v "$cmd" >/dev/null || { bad "${M[missing]} $cmd"; return 1; }
    done
    # Private work directory; no eval or execution of external configuration.
    WORK=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/hosts-manager.XXXXXXXX") || return 1
    [[ ! -L "$LOG_FILE" ]] || { bad "${M[logfail]}"; return 1; }
    : >> "$LOG_FILE" || { bad "${M[logfail]}"; return 1; }
    /usr/bin/sudo -v || { bad "${M[sudo]}"; return 1; }
    /usr/bin/sudo /bin/mkdir -p "$BACKUP_DIR" || return 1
    /usr/bin/sudo /usr/sbin/chown root:wheel "$BACKUP_DIR" || return 1
    /usr/bin/sudo /bin/chmod 755 "$BACKUP_DIR" || return 1
    # Root-owned lock serializes this script, not third-party hosts editors.
    if ! /usr/bin/sudo /bin/mkdir /var/run/hosts-manager.lock 2>/dev/null; then
        bad "${M[locked]} /var/run/hosts-manager.lock"; return 1
    fi
    trap 'cleanup; /usr/bin/sudo -n /bin/rmdir /var/run/hosts-manager.lock 2>/dev/null' EXIT

    while true; do
        print_menu
        ask "${M[choice]}" || break
        action="$REPLY"
        case "$action" in
            0) break ;;
            1) reset_hosts ;;
            2) restore_hosts ;;
            3) /bin/cat "$HOSTS_FILE" ;;
            4) backup_hosts ;;
            5) add_entry ;;
            6) remove_entry ;;
            7) check_syntax ;;
            8) duplicates ;;
            9) file_operation export ;;
            10) file_operation import ;;
            11) /bin/ls -leO "$HOSTS_FILE" ;;
            12) acl_operation +a ;;
            13) acl_operation -a ;;
            *) bad "${M[invalid]}" ;;
        esac
        if (( $? != 0 )); then log "$C_RED" "${M[fail]}"; fi
        printf '\n%s%s%s' "$C_CYAN" "${M[pause]}" "$C_RESET"
        read -r || break
    done
    log "$C_GREEN" "${M[done]}"
}
main "$@"
