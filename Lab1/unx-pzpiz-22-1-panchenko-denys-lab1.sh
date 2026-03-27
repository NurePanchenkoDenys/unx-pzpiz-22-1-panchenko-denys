#!/bin/bash

# =============================================================================
# Лабораторна робота №1 — Операційні системи Unix
# Тема: Робота з процесами, сигналами та журналюванням у Bash
# Автор: Панченко Денис, гр. ПЗПІз-22-1
# =============================================================================

# --- Файл журналу ---
LOG_DIR="$HOME/log"
LOG_FILE="$LOG_DIR/unx-pzpiz-22-1-panchenko-denys-lab1.log"
SCRIPT_NAME="$(basename "$0")"
CHILD_PID=""

# =============================================================================
# Функція: визначення мови повідомлень
# =============================================================================
is_ukrainian() {
    local lang="${LC_MESSAGES:-$LANG}"
    [[ "$lang" == uk_UA* ]]
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
# Функція: виведення довідки
# =============================================================================
show_help() {
    if is_ukrainian; then
        cat <<EOF
Використання: $SCRIPT_NAME [-h|--help]

Опис:
  Скрипт демонструє взаємодію батьківського та дочірнього процесів
  з використанням сигналів та журналювання.

Команди інтерактивного режиму:
  status     — перевірити стан дочірнього процесу
  send USR1  — надіслати SIGUSR1 дочірньому процесу
  send USR2  — надіслати SIGUSR2 дочірньому процесу
  send HUP   — надіслати SIGHUP дочірньому процесу
  stop       — зупинити дочірній процес (SIGTERM)
  quit       — завершити роботу скрипта
  help       — показати цю довідку

Параметри:
  -h, --help   Вивести довідку та завершити роботу
EOF
    else
        cat <<EOF
Usage: $SCRIPT_NAME [-h|--help]

Description:
  Script demonstrates parent-child process interaction
  using signals and logging.

Interactive commands:
  status     — check child process status
  send USR1  — send SIGUSR1 to child process
  send USR2  — send SIGUSR2 to child process
  send HUP   — send SIGHUP to child process
  stop       — stop child process (SIGTERM)
  quit       — exit the script
  help       — show this help

Options:
  -h, --help   Show help and exit
EOF
    fi
}

# =============================================================================
# Функція: запис у локальний журнал
# Формат: <дата>; <timestamp>; <PID>; <signal_number>; <signal_name>; <опис>
# =============================================================================
log_event() {
    local pid="$1"
    local sig_num="$2"
    local sig_name="$3"
    local description="$4"
    local date_str
    date_str="$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")"
    local timestamp
    timestamp="$(date +%s)"

    echo "${date_str}; ${timestamp}; ${pid}; ${sig_num}; ${sig_name}; ${description}" >> "$LOG_FILE"
}

# =============================================================================
# Функція: запис у системний журнал (syslog)
# =============================================================================
log_syslog() {
    logger -t "$SCRIPT_NAME" "$1"
}

# =============================================================================
# Функція: створення каталогу для журналу
# =============================================================================
ensure_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            error_msg "$(is_ukrainian && echo "неможливо створити каталог: $LOG_DIR" || echo "cannot create directory: $LOG_DIR")"
            exit 1
        fi
    fi
}

# =============================================================================
# Функція: перевірка існування дочірнього процесу
# =============================================================================
is_child_alive() {
    if [ -n "$CHILD_PID" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
        return 0
    fi
    return 1
}

# =============================================================================
# Дочірній процес
# =============================================================================
child_process() {
    local my_pid=$BASHPID
    local parent_pid=$$

    # Обробник SIGUSR1 — повідомлення від батька
    trap '{
        log_event "'"$my_pid"'" "10" "SIGUSR1" "Child: received SIGUSR1 from parent"
        info_msg "[Дочірній] Отримано SIGUSR1. Надсилаю підтвердження." "[Child] Received SIGUSR1. Sending confirmation."
        kill -SIGUSR1 "'"$parent_pid"'" 2>/dev/null
    }' SIGUSR1

    # Обробник SIGUSR2 — додаткова дія
    trap '{
        log_event "'"$my_pid"'" "12" "SIGUSR2" "Child: received SIGUSR2 from parent"
        info_msg "[Дочірній] Отримано SIGUSR2. Виконую додаткову дію." "[Child] Received SIGUSR2. Performing additional action."
        kill -SIGUSR2 "'"$parent_pid"'" 2>/dev/null
    }' SIGUSR2

    # Обробник SIGHUP — перезавантаження конфігурації
    trap '{
        log_event "'"$my_pid"'" "1" "SIGHUP" "Child: received SIGHUP, reloading"
        info_msg "[Дочірній] Отримано SIGHUP. Перезавантаження." "[Child] Received SIGHUP. Reloading."
    }' SIGHUP

    # Обробник SIGTERM — коректне завершення
    trap '{
        log_event "'"$my_pid"'" "15" "SIGTERM" "Child: received SIGTERM, exiting"
        log_syslog "Child process $my_pid terminated by SIGTERM"
        info_msg "[Дочірній] Отримано SIGTERM. Завершення роботи." "[Child] Received SIGTERM. Exiting."
        exit 0
    }' SIGTERM

    # Ігнорування SIGINT (Ctrl+C) — дочірній не завершується від Ctrl+C
    trap '' SIGINT

    log_event "$my_pid" "0" "NONE" "Child process started"
    log_syslog "Child process started with PID $my_pid"
    info_msg "[Дочірній] Процес запущено (PID: $my_pid)" "[Child] Process started (PID: $my_pid)"

    # Основний цикл дочірнього процесу
    while true; do
        sleep 1
    done
}

# =============================================================================
# Обробники сигналів батьківського процесу
# =============================================================================

# Підтвердження від дочірнього (SIGUSR1)
handle_parent_sigusr1() {
    log_event "$$" "10" "SIGUSR1" "Parent: received confirmation SIGUSR1 from child"
    info_msg "[Батьківський] Отримано підтвердження SIGUSR1 від дочірнього." "[Parent] Received SIGUSR1 confirmation from child."
}

# Підтвердження від дочірнього (SIGUSR2)
handle_parent_sigusr2() {
    log_event "$$" "12" "SIGUSR2" "Parent: received confirmation SIGUSR2 from child"
    info_msg "[Батьківський] Отримано підтвердження SIGUSR2 від дочірнього." "[Parent] Received SIGUSR2 confirmation from child."
}

# Обробка SIGINT (Ctrl+C) — коректне завершення
handle_parent_sigint() {
    echo ""
    info_msg "[Батьківський] Отримано SIGINT (Ctrl+C). Завершення..." "[Parent] Received SIGINT (Ctrl+C). Shutting down..."
    log_event "$$" "2" "SIGINT" "Parent: received SIGINT, shutting down"
    cleanup_and_exit
}

# Обробка SIGTERM
handle_parent_sigterm() {
    info_msg "[Батьківський] Отримано SIGTERM. Завершення..." "[Parent] Received SIGTERM. Shutting down..."
    log_event "$$" "15" "SIGTERM" "Parent: received SIGTERM, shutting down"
    cleanup_and_exit
}

# =============================================================================
# Функція: коректне завершення з очищенням
# =============================================================================
cleanup_and_exit() {
    if is_child_alive; then
        info_msg "[Батьківський] Зупиняю дочірній процес (PID: $CHILD_PID)..." "[Parent] Stopping child process (PID: $CHILD_PID)..."
        kill -SIGTERM "$CHILD_PID" 2>/dev/null
        # Очікування завершення дочірнього процесу
        wait "$CHILD_PID" 2>/dev/null
    fi
    log_event "$$" "0" "NONE" "Parent process exiting"
    log_syslog "Parent process $$ exiting"
    info_msg "[Батьківський] Роботу завершено." "[Parent] Exiting."
    exit 0
}

# =============================================================================
# Функція: надсилання сигналу дочірньому процесу
# =============================================================================
send_signal_to_child() {
    local signal="$1"
    local sig_num="$2"
    local sig_name="$3"

    if ! is_child_alive; then
        error_msg "$(is_ukrainian && echo "дочірній процес не існує" || echo "child process does not exist")"
        return 1
    fi

    kill "-${signal}" "$CHILD_PID" 2>/dev/null
    if [ $? -eq 0 ]; then
        log_event "$$" "$sig_num" "$sig_name" "Parent: sent $sig_name to child $CHILD_PID"
        info_msg "[Батьківський] Надіслано $sig_name дочірньому (PID: $CHILD_PID)" "[Parent] Sent $sig_name to child (PID: $CHILD_PID)"
    else
        error_msg "$(is_ukrainian && echo "не вдалося надіслати сигнал" || echo "failed to send signal")"
    fi
}

# =============================================================================
# Функція: перевірка стану дочірнього процесу
# =============================================================================
check_child_status() {
    if is_child_alive; then
        info_msg "[Батьківський] Дочірній процес активний (PID: $CHILD_PID)" "[Parent] Child process is active (PID: $CHILD_PID)"
    else
        info_msg "[Батьківський] Дочірній процес не працює" "[Parent] Child process is not running"
        CHILD_PID=""
    fi
}

# =============================================================================
# Функція: виведення запрошення інтерактивного режиму
# =============================================================================
show_prompt() {
    if is_ukrainian; then
        echo -n "[батьківський]> "
    else
        echo -n "[parent]> "
    fi
}

# =============================================================================
# Обробка параметрів командного рядка
# =============================================================================
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error_msg "$(is_ukrainian && echo "невідомий параметр: $1" || echo "unknown option: $1")"
                exit 1
                ;;
            *)
                error_msg "$(is_ukrainian && echo "зайвий аргумент: $1" || echo "extra argument: $1")"
                exit 1
                ;;
        esac
        shift
    done
}

# =============================================================================
# ГОЛОВНА ЧАСТИНА СКРИПТА
# =============================================================================

# Обробка аргументів
parse_args "$@"

# Створення каталогу для журналу
ensure_log_dir

# Встановлення обробників сигналів для батьківського процесу
trap 'handle_parent_sigusr1' SIGUSR1
trap 'handle_parent_sigusr2' SIGUSR2
trap 'handle_parent_sigint' SIGINT
trap 'handle_parent_sigterm' SIGTERM

# Запис у журнали про запуск
log_event "$$" "0" "NONE" "Parent process started"
log_syslog "Script $SCRIPT_NAME started with PID $$"

info_msg "=== Лабораторна робота №1: Процеси, сигнали, журналювання ===" "=== Lab 1: Processes, signals, logging ==="
info_msg "[Батьківський] Процес запущено (PID: $$)" "[Parent] Process started (PID: $$)"

# Запуск дочірнього процесу у фоновому режимі
child_process &
CHILD_PID=$!

log_event "$$" "0" "NONE" "Child process created with PID $CHILD_PID"
log_syslog "Child process created with PID $CHILD_PID"
info_msg "[Батьківський] Дочірній процес створено (PID: $CHILD_PID)" "[Parent] Child process created (PID: $CHILD_PID)"
echo ""

# Виведення доступних команд
if is_ukrainian; then
    echo "Доступні команди: status, send USR1, send USR2, send HUP, stop, quit, help"
else
    echo "Available commands: status, send USR1, send USR2, send HUP, stop, quit, help"
fi
echo ""

# Інтерактивний цикл батьківського процесу
while true; do
    show_prompt
    read -r cmd arg || continue

    case "$cmd" in
        status)
            check_child_status
            ;;
        send)
            case "$arg" in
                USR1|usr1)
                    send_signal_to_child "SIGUSR1" "10" "SIGUSR1"
                    ;;
                USR2|usr2)
                    send_signal_to_child "SIGUSR2" "12" "SIGUSR2"
                    ;;
                HUP|hup)
                    send_signal_to_child "SIGHUP" "1" "SIGHUP"
                    ;;
                TERM|term)
                    send_signal_to_child "SIGTERM" "15" "SIGTERM"
                    ;;
                *)
                    error_msg "$(is_ukrainian && echo "невідомий сигнал: $arg. Доступні: USR1, USR2, HUP, TERM" || echo "unknown signal: $arg. Available: USR1, USR2, HUP, TERM")"
                    ;;
            esac
            ;;
        stop)
            if is_child_alive; then
                send_signal_to_child "SIGTERM" "15" "SIGTERM"
                wait "$CHILD_PID" 2>/dev/null
                CHILD_PID=""
            else
                info_msg "[Батьківський] Дочірній процес вже зупинено" "[Parent] Child process is already stopped"
            fi
            ;;
        quit|exit)
            cleanup_and_exit
            ;;
        help)
            show_help
            ;;
        "")
            # Порожній рядок — ігнорувати
            ;;
        *)
            error_msg "$(is_ukrainian && echo "невідома команда: $cmd. Введіть 'help' для довідки" || echo "unknown command: $cmd. Type 'help' for help")"
            ;;
    esac

    # Невелика пауза для обробки сигналів
    sleep 0.1
done
