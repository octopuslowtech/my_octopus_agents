#!/bin/bash

CACHE_DIR="${TMPDIR:-/tmp}/claudible-statusline"
GIT_CACHE_FILE="$CACHE_DIR/git_branch_cache"
GIT_CACHE_TTL=300

mkdir -p "$CACHE_DIR" 2>/dev/null

INPUT=""
if [ ! -t 0 ]; then
    INPUT=$(cat)
fi

parse_context() {
    local json="$1"

    CWD=$(echo "$json" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    GIT_NUM_FILES=$(echo "$json" | grep -o '"gitNumStagedOrUnstagedFilesChanged"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)

    MODEL=$(echo "$json" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)

    INPUT_TOKENS=$(echo "$json" | grep -o '"input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    CACHE_CREATION=$(echo "$json" | grep -o '"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    CACHE_READ=$(echo "$json" | grep -o '"cache_read_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    INPUT_TOKENS="${INPUT_TOKENS:-0}"
    CACHE_CREATION="${CACHE_CREATION:-0}"
    CACHE_READ="${CACHE_READ:-0}"
    CONVERSATION_TOKENS=$((INPUT_TOKENS + CACHE_CREATION + CACHE_READ))

    MAX_TOKENS=$(echo "$json" | grep -o '"context_window_size"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)

    LINES_ADDED=$(echo "$json" | grep -o '"total_lines_added"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_REMOVED=$(echo "$json" | grep -o '"total_lines_removed"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_ADDED="${LINES_ADDED:-0}"
    LINES_REMOVED="${LINES_REMOVED:-0}"

    CWD="${CWD:-$(pwd)}"
    GIT_NUM_FILES="${GIT_NUM_FILES:-0}"
    MODEL="${MODEL:-unknown}"
    CONVERSATION_TOKENS="${CONVERSATION_TOKENS:-0}"
    MAX_TOKENS="${MAX_TOKENS:-200000}"

    if [ -n "$CWD" ] && [ -d "$CWD" ] && command -v git >/dev/null 2>&1; then
        if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local git_cache_key="$GIT_CACHE_FILE.$(echo "$CWD" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "nocache")"
            local now=$(date +%s)

            if [ -f "$git_cache_key" ]; then
                local cache_time=$(stat -c %Y "$git_cache_key" 2>/dev/null || stat -f %m "$git_cache_key" 2>/dev/null || echo "0")
                local age=$((now - cache_time))
                if [ "$age" -lt "$GIT_CACHE_TTL" ]; then
                    GIT_BRANCH=$(cat "$git_cache_key" 2>/dev/null)
                fi
            fi

            if [ -z "$GIT_BRANCH" ]; then
                GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
                [ -n "$GIT_BRANCH" ] && [ -n "$git_cache_key" ] && echo "$GIT_BRANCH" > "$git_cache_key" 2>/dev/null
            fi
        fi
    fi
}

format_model() {
    local model="$1"
    local tier version

    if echo "$model" | grep -qiE '(opus|sonnet|haiku)[[:space:]]*[0-9]'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        version=$(echo "$model" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        if [ -n "$version" ]; then
            echo "${tier}-${version}"
        else
            echo "$tier"
        fi
        return
    fi

    if echo "$model" | grep -qiE 'claude.*(opus|sonnet|haiku)'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        version=$(echo "$model" | grep -oE '[0-9]+[\.\-][0-9]+' | tail -1 | tr '-' '.')
        if [ -n "$version" ]; then
            echo "${tier}-${version}"
        else
            echo "$tier"
        fi
        return
    fi

    echo "$model" | sed 's/^claude-//' | sed 's/-[0-9]*$//' | cut -c1-12
}

shorten_path() {
    local path="$1"
    local home="$HOME"

    path="${path/#$home/~}"

    if [ ${#path} -gt 40 ]; then
        path=$(echo "$path" | awk -F'/' '{print $(NF-1)"/"$NF}')
    fi

    echo "$path"
}

format_tokens() {
    local num="$1"
    if [ "$num" -ge 1000 ]; then
        echo "$((num / 1000))k"
    else
        echo "$num"
    fi
}

main() {
    parse_context "$INPUT"

    local W="\033[97m"
    local G="\033[32m"
    local R="\033[31m"
    local DM="\033[90m"
    local D="\033[0m"

    local line1=""

    local short_cwd
    short_cwd=$(shorten_path "$CWD")
    line1+="📂 ${W}${short_cwd}${D}"

    if [ -n "$GIT_BRANCH" ]; then
        line1+="  🌿 ${W}${GIT_BRANCH}${D}"
        if [ "$GIT_NUM_FILES" -gt 0 ]; then
            line1+=" ${W}($GIT_NUM_FILES)${D}"
        fi
    fi

    if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
        line1+="  📝 ${G}+${LINES_ADDED}${D} ${R}-${LINES_REMOVED}${D}"
    fi

    local line2=""

    local ctx_current
    ctx_current=$(format_tokens "$CONVERSATION_TOKENS")
    local ctx_max
    ctx_max=$(format_tokens "$MAX_TOKENS")

    line2+="📊 ${W}${ctx_current}/${ctx_max}${D} ${DM}|${D}"

    local model_display
    model_display=$(format_model "$MODEL")
    line2+=" 🤖 ${W}${model_display}${D}"

    echo -e "$line1"
    echo -e "$line2"
}

main
