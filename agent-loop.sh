#!/usr/bin/env bash
# agent-loop.sh - Multi-Agent Autonomous Coding & QA Loop for macOS / Linux
# Usage:
#   ./agent-loop.sh <TargetDir> "<Task>" [MaxRounds]
#   or with flags:
#   ./agent-loop.sh -d <TargetDir> -t "<Task>" [-m <MaxRounds>]

set -euo pipefail

# ANSI Colors
COLOR_RESET="\033[0m"
COLOR_CYAN="\033[0;36m"
COLOR_YELLOW="\033[0;33m"
COLOR_GREEN="\033[0;32m"
COLOR_MAGENTA="\033[0;35m"
COLOR_GRAY="\033[0;90m"

TARGET_DIR=""
TASK=""
MAX_ROUNDS=8

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir|--target-dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        -t|--task)
            TASK="$2"
            shift 2
            ;;
        -m|--max-rounds)
            MAX_ROUNDS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options] <TargetDir> \"<Task>\" [MaxRounds]"
            echo "Options:"
            echo "  -d, --dir <path>          Target directory path"
            echo "  -t, --task <string>       Task description"
            echo "  -m, --max-rounds <int>    Maximum loop rounds (default: 8)"
            exit 0
            ;;
        *)
            if [[ -z "$TARGET_DIR" ]]; then
                TARGET_DIR="$1"
            elif [[ -z "$TASK" ]]; then
                TASK="$1"
            elif [[ "$MAX_ROUNDS" -eq 8 ]]; then
                MAX_ROUNDS="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$TARGET_DIR" || -z "$TASK" ]]; then
    echo "Error: TargetDir and Task are required."
    echo "Usage: $0 <TargetDir> \"<Task>\" [MaxRounds]"
    exit 1
fi

# Convert to absolute path
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
STATE_DIR="$TARGET_DIR/.agent-loop/task-$TIMESTAMP"
mkdir -p "$STATE_DIR/log"
echo "$TASK" > "$STATE_DIR/current-task.md"
ACTIVITY_LOG="$STATE_DIR/activity.log"

write_status() {
    local agent="$1"
    local action="$2"
    local color_code="$3"
    local ts
    ts=$(date +"%H:%M:%S")
    local line="[$ts] [$agent] $action"
    
    printf "%b%s%b\n" "$color_code" "$line" "$COLOR_RESET"
    echo "$line" >> "$ACTIVITY_LOG"
}

invoke_claude_cli() {
    local prompt="$1"
    local log_file="$2"
    write_status "CLAUDE" "STARTED" "$COLOR_YELLOW"

    set +e
    printf "%s\n" "$prompt" | claude -p \
        --allowedTools "Read,Write" \
        --permission-mode acceptEdits > "$log_file" 2>&1
    local exit_code=$?
    set -e

    write_status "CLAUDE" "FINISHED (exit code $exit_code)" "$COLOR_YELLOW"
    return $exit_code
}

invoke_agy_cli() {
    local prompt="$1"
    local log_file="$2"
    write_status "AGY" "STARTED" "$COLOR_GREEN"

    set +e
    agy --print "$prompt" --dangerously-skip-permissions --print-timeout 10m > "$log_file" 2>&1
    local exit_code=$?
    set -e

    write_status "AGY" "FINISHED (exit code $exit_code)" "$COLOR_GREEN"
    return $exit_code
}

invoke_codex_cli() {
    local prompt="$1"
    local log_file="$2"
    write_status "CODEX" "STARTED" "$COLOR_MAGENTA"

    set +e
    codex exec --sandbox workspace-write "$prompt" > "$log_file" 2>&1
    local exit_code=$?
    set -e

    write_status "CODEX" "FINISHED (exit code $exit_code)" "$COLOR_MAGENTA"
    return $exit_code
}

write_status "LOOP" "Task: $TASK | TargetDir: $TARGET_DIR | MaxRounds: $MAX_ROUNDS" "$COLOR_CYAN"

ORIG_DIR=$(pwd)
trap 'cd "$ORIG_DIR"' EXIT
cd "$TARGET_DIR"

for ((round=1; round<=MAX_ROUNDS; round++)); do
    write_status "LOOP" "=== Round $round START ===" "$COLOR_CYAN"

    git diff > "$STATE_DIR/current-diff.txt" 2>&1 || true

    claude_prompt="Task: $TASK. Review only. Read $STATE_DIR/current-diff.txt and $STATE_DIR/qa-report.md if present. Write findings with severity to $STATE_DIR/review.md. Do not edit source files."
    invoke_claude_cli "$claude_prompt" "$STATE_DIR/log/claude-round-$round.log" || true

    agy_prompt="Read $STATE_DIR/review.md and fix issues in source code, staying in scope of task: $TASK. Do not run git commit."
    invoke_agy_cli "$agy_prompt" "$STATE_DIR/log/agy-round-$round.log" || true

    codex_prompt="QA/pentest the latest code changes against task: $TASK. Write $STATE_DIR/qa-report.md starting with 'STATUS: PASS' or 'STATUS: FAIL'."
    codex_exit=0
    invoke_codex_cli "$codex_prompt" "$STATE_DIR/log/codex-round-$round.log" || codex_exit=$?

    if [[ $codex_exit -ne 0 ]]; then
        write_status "LOOP" "codex exit code $codex_exit - checking qa-report.md anyway" "$COLOR_YELLOW"
    fi

    status=""
    if [[ -f "$STATE_DIR/qa-report.md" ]]; then
        status=$(head -n 1 "$STATE_DIR/qa-report.md" | tr -d '\r')
    fi
    write_status "LOOP" "Round $round result: $status" "$COLOR_CYAN"

    if [[ "$status" == STATUS:\ PASS* ]]; then
        git add -A
        git commit -m "feat: $TASK (passed in $round rounds)"
        write_status "LOOP" "DONE - passed in $round rounds (committed final changes)" "$COLOR_GREEN"
        exit 0
    fi
done

write_status "LOOP" "MAX ROUNDS REACHED ($MAX_ROUNDS) - needs human review" "$COLOR_YELLOW"
exit 1
