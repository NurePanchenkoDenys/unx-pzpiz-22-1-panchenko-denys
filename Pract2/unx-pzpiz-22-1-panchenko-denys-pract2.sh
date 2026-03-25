#!/bin/bash

# =============================================================================
# Практичне заняття №2 — Операційні системи Unix
# Тема: Робота з файлами у Bash. Обробка параметрів командного рядка
# Автор: Панченко Денис, гр. ПЗПІз-22-1
# Опис: Скрипт фіксує дату та час запуску, записує у файл,
#        здійснює керування файлами журналу (ротація)
# =============================================================================

# --- Файл за замовчуванням ---
DEFAULT_FILE="$HOME/log/task2.out"

# --- Змінні ---
MAX_FILES=""
OUTPUT_FILE=""

# =============================================================================
# Функція: визначення мови повідомлень
# Якщо LANG або LC_MESSAGES містить uk_UA — українська, інакше англійська
# =============================================================================
is_ukrainian() {
    local lang="${LC_MESSAGES:-$LANG}"
    if [[ "$lang" == uk_UA* ]]; then
        return 0
    fi
    return 1
}

# =============================================================================
# Функція: виведення повідомлення про помилку у stderr
# =============================================================================
error_msg() {
    if is_ukrainian; then
        echo "Помилка: $1" >&2
    else
        echo "Error: $1" >&2
    fi
}

# =============================================================================
# Функція: виведення інформаційного повідомлення
# =============================================================================
info_msg() {
    if is_ukrainian; then
        echo "$1"
    else
        echo "$2"
    fi
}

# =============================================================================
# Функція: виведення довідкової інформації
# =============================================================================
show_help() {
    if is_ukrainian; then
        cat <<EOF
Використання: $0 [-h|--help] [-n кількість] [файл]

Опис:
  Скрипт фіксує дату та час свого запуску та записує їх у файл.
  Попередні файли зберігаються як архівні копії.

Параметри:
  -h, --help     Вивести цю довідку та завершити роботу
  -n кількість   Максимальна кількість архівних файлів (за замовчуванням: без обмежень)
  файл           Шлях до файлу для запису (за замовчуванням: ~/log/task2.out)

Приклади:
  $0                          Записати дату у ~/log/task2.out
  $0 -n 5 ./logs/info.txt    Записати дату, залишити до 5 архівів
  $0 --help                   Показати довідку
EOF
    else
        cat <<EOF
Usage: $0 [-h|--help] [-n count] [file]

Description:
  This script logs the current date and time to a file.
  Previous files are preserved as archived copies.

Options:
  -h, --help   Show this help message and exit
  -n count     Maximum number of archived files (default: unlimited)
  file         Path to the output file (default: ~/log/task2.out)

Examples:
  $0                          Log date to ~/log/task2.out
  $0 -n 5 ./logs/info.txt    Log date, keep up to 5 archives
  $0 --help                   Show help
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

    # Якщо файл не задано — використати за замовчуванням
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="$DEFAULT_FILE"
    fi
}

# =============================================================================
# Функція: створення каталогу для файлу
# =============================================================================
ensure_directory() {
    local dir
    dir="$(dirname "$OUTPUT_FILE")"

    if [ ! -d "$dir" ]; then
        if ! mkdir -p "$dir" 2>/dev/null; then
            error_msg "$(is_ukrainian && echo "неможливо створити каталог: $dir" || echo "cannot create directory: $dir")"
            exit 1
        fi
        info_msg "Створено каталог: $dir" "Created directory: $dir"
    fi
}

# =============================================================================
# Функція: ротація існуючого файлу (перейменування з датою та номером)
# =============================================================================
rotate_file() {
    if [ ! -f "$OUTPUT_FILE" ]; then
        return
    fi

    local base
    base="$(basename "$OUTPUT_FILE")"
    local dir
    dir="$(dirname "$OUTPUT_FILE")"
    local today
    today="$(date +%Y%m%d)"

    # Визначення наступного номера для поточного дня
    local max_num=-1
    local pattern="${base}-${today}-"

    for existing in "$dir"/${pattern}*; do
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

    local next_num=$((max_num + 1))
    local new_name
    new_name=$(printf "%s/%s-%s-%04d" "$dir" "$base" "$today" "$next_num")

    if ! mv "$OUTPUT_FILE" "$new_name" 2>/dev/null; then
        error_msg "$(is_ukrainian && echo "неможливо перейменувати файл: $OUTPUT_FILE" || echo "cannot rename file: $OUTPUT_FILE")"
        exit 1
    fi

    info_msg "Архівовано: $new_name" "Archived: $new_name"
}

# =============================================================================
# Функція: видалення старих архівних файлів (якщо задано -n)
# =============================================================================
cleanup_archives() {
    if [ -z "$MAX_FILES" ]; then
        return
    fi

    local base
    base="$(basename "$OUTPUT_FILE")"
    local dir
    dir="$(dirname "$OUTPUT_FILE")"

    # Знаходимо архівні файли, сортуємо за іменем (за датою та номером)
    local archives=()
    while IFS= read -r f; do
        archives+=("$f")
    done < <(find "$dir" -maxdepth 1 -name "${base}-[0-9]*-[0-9]*" -type f | sort)

    local count=${#archives[@]}
    local to_delete=$((count - MAX_FILES))

    if [ "$to_delete" -gt 0 ]; then
        for ((i = 0; i < to_delete; i++)); do
            rm -f "${archives[$i]}"
            info_msg "Видалено старий архів: ${archives[$i]}" "Deleted old archive: ${archives[$i]}"
        done
    fi
}

# =============================================================================
# Функція: запис дати у файл
# =============================================================================
write_date() {
    local date_string
    date_string="$(LC_ALL=C date "+Date: %a, %d %b %Y %H:%M:%S %z")"

    if ! echo "$date_string" > "$OUTPUT_FILE" 2>/dev/null; then
        error_msg "$(is_ukrainian && echo "неможливо записати у файл: $OUTPUT_FILE" || echo "cannot write to file: $OUTPUT_FILE")"
        exit 1
    fi

    info_msg "Записано у $OUTPUT_FILE: $date_string" "Written to $OUTPUT_FILE: $date_string"
}

# =============================================================================
# Головна частина скрипта
# =============================================================================
parse_args "$@"
ensure_directory
rotate_file
cleanup_archives
write_date

exit 0
