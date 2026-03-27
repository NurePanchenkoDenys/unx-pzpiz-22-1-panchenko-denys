#!/bin/bash

# =============================================================================
# Лабораторна робота №2 — Операційні системи Unix
# Тема: Збір та обробка інформації про платформу у середовищі Unix/Linux
# Автор: Панченко Денис, гр. ПЗПІз-22-1
# =============================================================================

# --- Файл за замовчуванням ---
DEFAULT_FILE="$HOME/log/task2.out"
MAX_FILES=""
OUTPUT_FILE=""

# =============================================================================
# Функція: визначення мови повідомлень
# =============================================================================
is_ukrainian() {
    local lang="${LC_MESSAGES:-$LANG}"
    [[ "$lang" == uk_UA* ]]
}

# =============================================================================
# Функція: повідомлення про помилку у stderr
# =============================================================================
error_msg() {
    if is_ukrainian; then
        echo "Помилка: $1" >&2
    else
        echo "Error: $1" >&2
    fi
}

# =============================================================================
# Функція: інформаційне повідомлення
# =============================================================================
info_msg() {
    if is_ukrainian; then
        echo "$1"
    else
        echo "$2"
    fi
}

# =============================================================================
# Функція: довідка
# =============================================================================
show_help() {
    if is_ukrainian; then
        cat <<EOF
Використання: $0 [-h|--help] [-n кількість] [файл]

Опис:
  Скрипт збирає інформацію про апаратне забезпечення, операційну систему
  та мережеві інтерфейси і виводить у стандартизованому форматі.

Параметри:
  -h, --help     Вивести довідку
  -n кількість   Максимальна кількість архівних файлів
  файл           Шлях до файлу (за замовчуванням: ~/log/task2.out)
EOF
    else
        cat <<EOF
Usage: $0 [-h|--help] [-n count] [file]

Description:
  Script collects hardware, system and network information
  and outputs it in a standardized format.

Options:
  -h, --help   Show help
  -n count     Maximum number of archived files
  file         Output file (default: ~/log/task2.out)
EOF
    fi
}

# =============================================================================
# Функція: обробка параметрів командного рядка
# =============================================================================
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n)
                shift
                if [ -z "$1" ]; then
                    error_msg "$(is_ukrainian && echo "параметр -n потребує значення" || echo "option -n requires a value")"
                    exit 1
                fi
                if ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
                    error_msg "$(is_ukrainian && echo "значення -n повинно бути цілим числом >= 1" || echo "-n value must be an integer >= 1")"
                    exit 1
                fi
                MAX_FILES="$1"
                ;;
            -*)
                error_msg "$(is_ukrainian && echo "невідомий параметр: $1" || echo "unknown option: $1")"
                exit 1
                ;;
            *)
                if [ -n "$OUTPUT_FILE" ]; then
                    error_msg "$(is_ukrainian && echo "зайвий аргумент: $1" || echo "extra argument: $1")"
                    exit 1
                fi
                OUTPUT_FILE="$1"
                ;;
        esac
        shift
    done

    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="$DEFAULT_FILE"
    fi
}

# =============================================================================
# Функція: створення каталогу
# =============================================================================
ensure_directory() {
    local dir
    dir="$(dirname "$OUTPUT_FILE")"
    if [ ! -d "$dir" ]; then
        if ! mkdir -p "$dir" 2>/dev/null; then
            error_msg "$(is_ukrainian && echo "неможливо створити каталог: $dir" || echo "cannot create directory: $dir")"
            exit 1
        fi
    fi
}

# =============================================================================
# Функція: ротація файлу
# =============================================================================
rotate_file() {
    if [ ! -f "$OUTPUT_FILE" ]; then
        return
    fi

    local base dir today max_num next_num new_name
    base="$(basename "$OUTPUT_FILE")"
    dir="$(dirname "$OUTPUT_FILE")"
    today="$(date +%Y%m%d)"
    max_num=-1

    for existing in "$dir"/${base}-${today}-*; do
        if [ -f "$existing" ]; then
            local num_part
            num_part="$(basename "$existing" | sed "s/^${base}-${today}-//")"
            if [[ "$num_part" =~ ^[0-9]+$ ]]; then
                local decimal_num=$((10#$num_part))
                if [ "$decimal_num" -gt "$max_num" ]; then
                    max_num="$decimal_num"
                fi
            fi
        fi
    done

    next_num=$((max_num + 1))
    new_name=$(printf "%s/%s-%s-%04d" "$dir" "$base" "$today" "$next_num")

    if ! mv "$OUTPUT_FILE" "$new_name" 2>/dev/null; then
        error_msg "$(is_ukrainian && echo "неможливо перейменувати файл" || echo "cannot rename file")"
        exit 1
    fi
}

# =============================================================================
# Функція: очищення старих архівів
# =============================================================================
cleanup_archives() {
    if [ -z "$MAX_FILES" ]; then
        return
    fi

    local base dir
    base="$(basename "$OUTPUT_FILE")"
    dir="$(dirname "$OUTPUT_FILE")"

    local archives=()
    while IFS= read -r f; do
        archives+=("$f")
    done < <(find "$dir" -maxdepth 1 -name "${base}-[0-9]*-[0-9]*" -type f | sort)

    local count=${#archives[@]}
    local to_delete=$((count - MAX_FILES))

    if [ "$to_delete" -gt 0 ]; then
        for ((i = 0; i < to_delete; i++)); do
            rm -f "${archives[$i]}"
        done
    fi
}

# =============================================================================
# Функція: отримання інформації про CPU
# =============================================================================
get_cpu() {
    if command -v lscpu &>/dev/null; then
        lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}'
    elif [ -f /proc/cpuinfo ]; then
        awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo
    elif command -v sysctl &>/dev/null; then
        sysctl -n machdep.cpu.brand_string 2>/dev/null
    else
        echo "Unknown"
    fi
}

# =============================================================================
# Функція: отримання інформації про RAM (у МБ)
# =============================================================================
get_ram() {
    if [ -f /proc/meminfo ]; then
        awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo
    elif command -v sysctl &>/dev/null; then
        local bytes
        bytes=$(sysctl -n hw.memsize 2>/dev/null)
        if [ -n "$bytes" ]; then
            echo $((bytes / 1024 / 1024))
        else
            echo "Unknown"
        fi
    else
        echo "Unknown"
    fi
}

# =============================================================================
# Функція: отримання інформації про материнську плату
# =============================================================================
get_motherboard() {
    local manufacturer product

    if command -v dmidecode &>/dev/null; then
        manufacturer=$(sudo dmidecode -s baseboard-manufacturer 2>/dev/null || echo "Unknown")
        product=$(sudo dmidecode -s baseboard-product-name 2>/dev/null || echo "Unknown")
    elif [ -f "$HOME/dmidecode.out" ]; then
        manufacturer=$(grep -i "baseboard-manufacturer" "$HOME/dmidecode.out" 2>/dev/null | head -1 | cut -d: -f2 | xargs)
        product=$(grep -i "baseboard-product-name" "$HOME/dmidecode.out" 2>/dev/null | head -1 | cut -d: -f2 | xargs)
    elif command -v sysctl &>/dev/null; then
        manufacturer=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
        product="Apple Silicon"
    else
        manufacturer="Unknown"
        product="Unknown"
    fi

    [ -z "$manufacturer" ] && manufacturer="Unknown"
    [ -z "$product" ] && product="Unknown"

    echo "\"$manufacturer\", \"$product\""
}

# =============================================================================
# Функція: отримання серійного номера
# =============================================================================
get_serial() {
    if command -v dmidecode &>/dev/null; then
        sudo dmidecode -s system-serial-number 2>/dev/null || echo "Unknown"
    elif [ -f "$HOME/dmidecode.out" ]; then
        grep -i "system-serial-number" "$HOME/dmidecode.out" 2>/dev/null | head -1 | cut -d: -f2 | xargs
    elif command -v ioreg &>/dev/null; then
        ioreg -l | awk -F'"' '/IOPlatformSerialNumber/ {print $4; exit}' 2>/dev/null || echo "Unknown"
    else
        echo "Unknown"
    fi
}

# =============================================================================
# Функція: отримання назви дистрибутива ОС
# =============================================================================
get_os_distribution() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
    elif command -v sw_vers &>/dev/null; then
        echo "$(sw_vers -productName) $(sw_vers -productVersion)"
    else
        uname -s
    fi
}

# =============================================================================
# Функція: отримання дати встановлення ОС
# =============================================================================
get_install_date() {
    if command -v stat &>/dev/null; then
        if stat --version &>/dev/null 2>&1; then
            # Linux (GNU stat)
            stat -c %w / 2>/dev/null | cut -d' ' -f1
        else
            # macOS (BSD stat)
            stat -f "%SB" -t "%Y-%m-%d" / 2>/dev/null
        fi
    else
        echo "Unknown"
    fi
}

# =============================================================================
# Функція: отримання часу роботи (uptime)
# =============================================================================
get_uptime() {
    uptime | sed 's/.*up //' | sed 's/,  *[0-9]* user.*//' | xargs
}

# =============================================================================
# Функція: отримання кількості процесів
# =============================================================================
get_processes() {
    ps aux 2>/dev/null | wc -l | xargs
}

# =============================================================================
# Функція: отримання кількості залогінених користувачів
# =============================================================================
get_users() {
    who 2>/dev/null | wc -l | xargs
}

# =============================================================================
# Функція: отримання мережевих інтерфейсів
# =============================================================================
get_network() {
    if command -v ip &>/dev/null; then
        # Linux: ip addr
        ip -o addr show 2>/dev/null | awk '{
            iface = $2
            if ($3 == "inet") {
                split($4, a, "/")
                printf "%s: %s/%s\n", iface, a[1], a[2]
            }
        }' | sort -u
    elif command -v ifconfig &>/dev/null; then
        # macOS: ifconfig
        local current_iface=""
        ifconfig 2>/dev/null | while IFS= read -r line; do
            if echo "$line" | grep -qE '^[a-zA-Z0-9]+:'; then
                current_iface=$(echo "$line" | cut -d: -f1)
            elif echo "$line" | grep -q 'inet '; then
                local ip mask
                ip=$(echo "$line" | awk '{print $2}')
                mask=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="netmask") print $(i+1)}')
                if [ -n "$ip" ] && [ -n "$mask" ]; then
                    # Перетворення hex маски у CIDR (macOS)
                    local cidr=0
                    if [[ "$mask" == 0x* ]]; then
                        local hex="${mask#0x}"
                        local bin=""
                        for ((c=0; c<${#hex}; c++)); do
                            local digit="${hex:$c:1}"
                            case "$digit" in
                                0) bin="${bin}0000" ;; 1) bin="${bin}0001" ;; 2) bin="${bin}0010" ;; 3) bin="${bin}0011" ;;
                                4) bin="${bin}0100" ;; 5) bin="${bin}0101" ;; 6) bin="${bin}0110" ;; 7) bin="${bin}0111" ;;
                                8) bin="${bin}1000" ;; 9) bin="${bin}1001" ;; a|A) bin="${bin}1010" ;; b|B) bin="${bin}1011" ;;
                                c|C) bin="${bin}1100" ;; d|D) bin="${bin}1101" ;; e|E) bin="${bin}1110" ;; f|F) bin="${bin}1111" ;;
                            esac
                        done
                        cidr=$(echo "$bin" | grep -o "1" | wc -l | xargs)
                    elif [[ "$mask" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        # Десяткова маска
                        IFS='.' read -r o1 o2 o3 o4 <<< "$mask"
                        for octet in $o1 $o2 $o3 $o4; do
                            while [ "$octet" -gt 0 ]; do
                                cidr=$((cidr + (octet & 1)))
                                octet=$((octet >> 1))
                            done
                        done
                    fi
                    echo "${current_iface}: ${ip}/${cidr}"
                fi
            fi
        done
    fi
}

# =============================================================================
# Функція: збір та форматування всієї інформації
# =============================================================================
collect_info() {
    local date_str timestamp

    # Дата та мітка часу повинні відповідати одному моменту
    local epoch
    epoch=$(date +%s)
    date_str=$(LC_ALL=C date -r "$epoch" "+Date: %a, %d %b %Y %H:%M:%S %z" 2>/dev/null || LC_ALL=C date -d "@$epoch" "+Date: %a, %d %b %Y %H:%M:%S %z" 2>/dev/null || LC_ALL=C date "+Date: %a, %d %b %Y %H:%M:%S %z")
    timestamp="Unix Timestamp: $epoch"

    local cpu ram motherboard serial
    cpu=$(get_cpu)
    ram=$(get_ram)
    motherboard=$(get_motherboard)
    serial=$(get_serial)

    local os_dist kernel install_date hostname_val uptime_val procs users
    os_dist=$(get_os_distribution)
    kernel=$(uname -r)
    install_date=$(get_install_date)
    hostname_val=$(hostname)
    uptime_val=$(get_uptime)
    procs=$(get_processes)
    users=$(get_users)

    local network
    network=$(get_network)

    # Формування виводу
    echo "$date_str"
    echo "$timestamp"
    echo "---- Hardware ----"
    echo "CPU: \"$cpu\""
    echo "RAM: $ram MB"
    echo "Motherboard: $motherboard"
    echo "System Serial Number: $serial"
    echo "---- System ----"
    echo "OS Distribution: \"$os_dist\""
    echo "Kernel version: $kernel"
    echo "Installation date: $install_date"
    echo "Hostname: $hostname_val"
    echo "Uptime: $uptime_val"
    echo "Processes running: $procs"
    echo "Users logged in: $users"
    echo "---- Network ----"
    if [ -n "$network" ]; then
        echo "$network"
    else
        echo "-/-"
    fi
    echo "----\"EOF\"----"
}

# =============================================================================
# ГОЛОВНА ЧАСТИНА
# =============================================================================

parse_args "$@"
ensure_directory
rotate_file
cleanup_archives

# Збір та вивід інформації (stdout + файл через tee)
collect_info | tee "$OUTPUT_FILE"

exit 0
