#!/bin/bash
# Claudible Statusline Script
# Displays context and balance in Claude Code statusline
# Configuration is auto-populated by install script

# Configuration (set by installer)
ENDPOINT_URL="https://claudible.io"
API_KEY='hocai-a49f136a6e1618d4e8d8f16ac012d0997e31ae1e44cb6652600c01d1e3518ec8'

# Cache settings
CACHE_DIR="${TMPDIR:-/tmp}/claudible-statusline"
CACHE_FILE="$CACHE_DIR/billing_cache.json"
MODELS_CACHE_FILE="$CACHE_DIR/models_cache.json"
GIT_CACHE_FILE="$CACHE_DIR/git_branch_cache"
LAST_REQUEST_FILE="$CACHE_DIR/last_request_time"
CACHE_TTL=30  # seconds
MODELS_CACHE_TTL=86400  # 24 hours for models/pricing
GIT_CACHE_TTL=300  # 5 minutes for git branch

# Ensure cache directory exists
mkdir -p "$CACHE_DIR" 2>/dev/null

# Read JSON input from stdin (Claude Code context)
INPUT=""
if [ ! -t 0 ]; then
    INPUT=$(cat)
fi

# Parse context from input JSON
parse_context() {
    local json="$1"

    # Extract values using grep/sed (portable, no jq dependency)
    CWD=$(echo "$json" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    GIT_NUM_FILES=$(echo "$json" | grep -o '"gitNumStagedOrUnstagedFilesChanged"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)

    # Model is object - get display_name and id
    MODEL=$(echo "$json" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    # Try to get model id from nested object first, then from flat id field
    MODEL_ID=$(echo "$json" | grep -o '"model"[[:space:]]*:[[:space:]]*{[^}]*"id"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    # Fallback: try to get id directly if model is a string or different structure
    if [ -z "$MODEL_ID" ]; then
        MODEL_ID=$(echo "$json" | grep -o '"id"[[:space:]]*:[[:space:]]*"claude[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    fi

    # Context tokens from current_usage
    INPUT_TOKENS=$(echo "$json" | grep -o '"input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    CACHE_CREATION=$(echo "$json" | grep -o '"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    CACHE_READ=$(echo "$json" | grep -o '"cache_read_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    OUTPUT_TOKENS=$(echo "$json" | grep -o '"output_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    INPUT_TOKENS="${INPUT_TOKENS:-0}"
    CACHE_CREATION="${CACHE_CREATION:-0}"
    CACHE_READ="${CACHE_READ:-0}"
    OUTPUT_TOKENS="${OUTPUT_TOKENS:-0}"
    CONVERSATION_TOKENS=$((INPUT_TOKENS + CACHE_CREATION + CACHE_READ))

    MAX_TOKENS=$(echo "$json" | grep -o '"context_window_size"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)

    # Lines changed from cost object
    LINES_ADDED=$(echo "$json" | grep -o '"total_lines_added"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_REMOVED=$(echo "$json" | grep -o '"total_lines_removed"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_ADDED="${LINES_ADDED:-0}"
    LINES_REMOVED="${LINES_REMOVED:-0}"

    # Default values
    CWD="${CWD:-$(pwd)}"
    GIT_NUM_FILES="${GIT_NUM_FILES:-0}"
    MODEL="${MODEL:-unknown}"
    MODEL_ID="${MODEL_ID:-}"
    CONVERSATION_TOKENS="${CONVERSATION_TOKENS:-0}"
    MAX_TOKENS="${MAX_TOKENS:-200000}"

    # Git branch - Claude Code doesn't send it, get ourselves (cached)
    # Only try if git command exists, CWD exists, and is a git repo
    # Wrap in subshell to prevent any errors from breaking statusline
    if [ -n "$CWD" ] && [ -d "$CWD" ] && command -v git >/dev/null 2>&1; then
        # Check if it's a git repo first
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

# Format model name for display
format_model() {
    local model="$1"
    local tier version

    # Match "Claude <Tier> <Version>" pattern (display_name)
    if echo "$model" | grep -qiE '(opus|sonnet|haiku)[[:space:]]*[0-9]'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        version=$(echo "$model" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        # Capitalize first letter
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        if [ -n "$version" ]; then
            echo "${tier}-${version}"
        else
            echo "$tier"
        fi
        return
    fi

    # Match model id like "claude-opus-4.7" or "claude-opus-4-7"
    if echo "$model" | grep -qiE 'claude.*(opus|sonnet|haiku)'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        # Extract version: "4.6" or convert "4-6" to "4.6"
        version=$(echo "$model" | grep -oE '[0-9]+[\.\-][0-9]+' | tail -1 | tr '-' '.')
        if [ -n "$version" ]; then
            echo "${tier}-${version}"
        else
            echo "$tier"
        fi
        return
    fi

    # Fallback: trim "claude-" prefix, truncate
    echo "$model" | sed 's/^claude-//' | sed 's/-[0-9]*$//' | cut -c1-12
}

# Shorten path for display
shorten_path() {
    local path="$1"
    local home="$HOME"

    # Replace home directory with ~
    path="${path/#$home/~}"

    # If path is too long, show only last 2 components
    if [ ${#path} -gt 40 ]; then
        path=$(echo "$path" | awk -F'/' '{print $(NF-1)"/"$NF}')
    fi

    echo "$path"
}

# Get models/pricing data with caching
get_models_pricing() {
    local now
    now=$(date +%s)

    # Check cache
    if [ -f "$MODELS_CACHE_FILE" ]; then
        local cache_time
        cache_time=$(stat -c %Y "$MODELS_CACHE_FILE" 2>/dev/null || stat -f %m "$MODELS_CACHE_FILE" 2>/dev/null)
        local age=$((now - cache_time))

        if [ "$age" -lt "$MODELS_CACHE_TTL" ]; then
            cat "$MODELS_CACHE_FILE"
            return 0
        fi
    fi

    # Fetch fresh data
    if [ -n "$ENDPOINT_URL" ] && [ "$ENDPOINT_URL" != "__""ENDPOINT_URL__" ] && \
       [ -n "$API_KEY" ] && [ "$API_KEY" != "__""API_KEY__" ]; then
        local response
        response=$(curl -s --max-time 5 -H "x-api-key: $API_KEY" "$ENDPOINT_URL/v1/models" 2>/dev/null)

        if [ -n "$response" ]; then
            echo "$response" > "$MODELS_CACHE_FILE"
            echo "$response"
            return 0
        fi
    fi

    # Return cached data if fetch failed
    if [ -f "$MODELS_CACHE_FILE" ]; then
        cat "$MODELS_CACHE_FILE"
    fi
}

# Get pricing for a specific model
get_model_pricing() {
    local model_id="$1"
    local models_data="$2"

    if [ -z "$model_id" ] || [ -z "$models_data" ]; then
        echo "3 15"  # Default fallback (Sonnet pricing)
        return
    fi

    # Extract pricing for the model from minified JSON
    # Split by model objects and find the one matching model_id
    local model_block=$(echo "$models_data" | sed 's/},{/}\n{/g' | grep "\"id\":\"$model_id\"")

    local input_price=""
    local output_price=""

    if [ -n "$model_block" ]; then
        input_price=$(echo "$model_block" | grep -o '"input":[0-9]*' | sed 's/"input"://')
        output_price=$(echo "$model_block" | grep -o '"output":[0-9]*' | sed 's/"output"://')
    fi

    # If not found, try matching by model family (opus, sonnet, haiku)
    if [ -z "$input_price" ]; then
        if echo "$model_id" | grep -qi "opus"; then
            input_price=5
            output_price=25
        elif echo "$model_id" | grep -qi "haiku"; then
            input_price=1
            output_price=5
        else
            # Default to Sonnet pricing
            input_price=3
            output_price=15
        fi
    fi

    # Final fallback
    input_price="${input_price:-3}"
    output_price="${output_price:-15}"

    echo "$input_price $output_price"
}

# Get billing data with caching
get_billing() {
    local now
    now=$(date +%s)

    # Check cache
    if [ -f "$CACHE_FILE" ]; then
        local cache_time
        cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null)
        local age=$((now - cache_time))

        if [ "$age" -lt "$CACHE_TTL" ]; then
            cat "$CACHE_FILE"
            return 0
        fi
    fi

    # Fetch fresh data
    if [ -n "$ENDPOINT_URL" ] && [ "$ENDPOINT_URL" != "__""ENDPOINT_URL__" ] && \
       [ -n "$API_KEY" ] && [ "$API_KEY" != "__""API_KEY__" ]; then
        local response
        response=$(curl -s --max-time 5 -X POST \
            -H "Content-Type: application/json" \
            -d "{\"key\":\"$API_KEY\"}" \
            "$ENDPOINT_URL/dashboard/lookup" 2>/dev/null)

        if [ -n "$response" ]; then
            echo "$response" > "$CACHE_FILE"
            echo "$response"
            return 0
        fi
    fi

    # Return cached data if fetch failed
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    fi
}

# Parse billing response
parse_billing() {
    local json="$1"

    BALANCE=$(echo "$json" | grep -o '"balance"[[:space:]]*:[[:space:]]*[0-9.]*' | sed 's/.*:[[:space:]]*//' | head -1)
    DAILY_QUOTA=$(echo "$json" | grep -o '"dailyQuota"[[:space:]]*:[[:space:]]*[0-9.]*' | sed 's/.*:[[:space:]]*//' | head -1)
    # Defaults
    BALANCE="${BALANCE:-0}"
    DAILY_QUOTA="${DAILY_QUOTA:-0}"
}

# Create progress bar
progress_bar() {
    local current="$1"
    local max="$2"
    local width=5

    if [ "$max" -eq 0 ]; then
        echo "▯▯▯▯▯"
        return
    fi

    local pct=$((current * 100 / max))
    local filled=$((pct * width / 100))
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="\033[32m▮\033[0m"; done
    for ((i=0; i<empty; i++)); do bar+="\033[90m▯\033[0m"; done

    echo "$bar"
}

# Format number with K suffix
format_tokens() {
    local num="$1"
    if [ "$num" -ge 1000 ]; then
        echo "$((num / 1000))k"
    else
        echo "$num"
    fi
}

# Main output
main() {
    parse_context "$INPUT"

    # ANSI colors
    local W="\033[97m"        # White (60%)
    local G="\033[32m"        # Green (30%)
    local R="\033[31m"        # Red
    local Y="\033[33m"        # Yellow
    local DM="\033[90m"       # Dim (10%)
    local D="\033[0m"         # Reset

    # Build line 1: folder + git branch + lines diff
    local line1=""

    # Working directory (cyan)
    local short_cwd
    short_cwd=$(shorten_path "$CWD")
    line1+="📂 ${W}${short_cwd}${D}"

    # Git info (white)
    if [ -n "$GIT_BRANCH" ]; then
        line1+="  🌿 ${W}${GIT_BRANCH}${D}"
        if [ "$GIT_NUM_FILES" -gt 0 ]; then
            line1+=" ${W}($GIT_NUM_FILES)${D}"
        fi
    fi

    # Lines diff (green/red - keep distinct)
    if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
        line1+="  📝 ${G}+${LINES_ADDED}${D} ${R}-${LINES_REMOVED}${D}"
    fi

    # Build line 2: context + model + balance
    local line2=""

    # Context usage
    local ctx_pct=0
    if [ "$MAX_TOKENS" -gt 0 ]; then
        ctx_pct=$((CONVERSATION_TOKENS * 100 / MAX_TOKENS))
    fi
    local ctx_bar
    ctx_bar=$(progress_bar "$CONVERSATION_TOKENS" "$MAX_TOKENS")
    local ctx_current
    ctx_current=$(format_tokens "$CONVERSATION_TOKENS")
    local ctx_max
    ctx_max=$(format_tokens "$MAX_TOKENS")

    line2+="📊 ${W}${ctx_current}/${ctx_max}${D} ${DM}|${D} $ctx_bar ${W}${ctx_pct}%${D} ${DM}|${D}"

    # Model (white)
    local model_display
    model_display=$(format_model "$MODEL")
    line2+=" 🤖 ${W}${model_display}${D}"

    # Balance (green $)
    local billing_data
    billing_data=$(get_billing)

    if [ -n "$billing_data" ]; then
        parse_billing "$billing_data"

        if [ -n "$BALANCE" ] && [ "$BALANCE" != "0" ]; then
            local bal_int=$(printf "%.0f" "$BALANCE" 2>/dev/null || echo "$BALANCE")
            local quota_int=$(printf "%.0f" "$DAILY_QUOTA" 2>/dev/null || echo "$DAILY_QUOTA")

            local bal_le_quota=$(echo "$BALANCE <= $DAILY_QUOTA" | bc 2>/dev/null || echo "0")

            if [ -n "$DAILY_QUOTA" ] && [ "$DAILY_QUOTA" != "0" ] && [ "$bal_le_quota" = "1" ]; then
                local used=$(echo "$DAILY_QUOTA - $BALANCE" | bc 2>/dev/null || echo "0")
                local used_fmt=$(printf "%.1f" "$used" 2>/dev/null || echo "$used")
                line2+=" ${DM}|${D} ${G}\$${D} ${W}${bal_int}/${quota_int} (-${used_fmt})${D}"
            else
                line2+=" ${DM}|${D} ${G}\$${D} ${W}${bal_int}${D}"
            fi
        fi
    fi

    # Build line 3: cost per request + last request time
    local line3=""

    # Cost estimate
    local models_data
    models_data=$(get_models_pricing)

    local pricing
    pricing=$(get_model_pricing "$MODEL_ID" "$models_data")
    local input_price=$(echo "$pricing" | cut -d' ' -f1)
    local output_price=$(echo "$pricing" | cut -d' ' -f2)

    local est_cost="0.00"
    if command -v bc >/dev/null 2>&1 && [ "$CONVERSATION_TOKENS" -gt 0 ]; then
        local regular_input="${INPUT_TOKENS:-0}"
        local cache_write="${CACHE_CREATION:-0}"
        local cache_hit="${CACHE_READ:-0}"
        local output_for_calc="${OUTPUT_TOKENS:-0}"
        est_cost=$(printf '%.2f' $(echo "scale=6; ($regular_input * $input_price / 1000000) + ($cache_write * $input_price * 1.25 / 1000000) + ($cache_hit * $input_price / 10 / 1000000) + ($output_for_calc * $output_price / 1000000)" | bc 2>/dev/null || echo 0))
    fi
    line3+="☘️  ${W}\$${est_cost}${D}"

    # Last request time: read previous, then save current timestamp
    local now
    now=$(date +%s)
    local last_req_display=""
    local cache_warn=""

    if [ -f "$LAST_REQUEST_FILE" ]; then
        local last_ts
        last_ts=$(cat "$LAST_REQUEST_FILE" 2>/dev/null)
        if [ -n "$last_ts" ] && [ "$last_ts" -gt 0 ] 2>/dev/null; then
            local elapsed=$((now - last_ts))
            # Warn if last request was >5 min ago (next request won't have cache)
            if [ "$elapsed" -ge 300 ]; then
                cache_warn=" ${Y}⚠ no cache${D}"
            fi
        fi
    fi
    echo "$now" > "$LAST_REQUEST_FILE" 2>/dev/null

    # Show time of current request so user knows when 5-min cache window started
    local req_time
    req_time=$(date +%H:%M:%S 2>/dev/null)
    if [ -n "$req_time" ]; then
        last_req_display="last req ${req_time}${cache_warn}"
        line3+=" ${DM}|${D} 🕐 ${W}${last_req_display}${D}"
    fi

    echo -e "$line1"
    echo -e "$line2"
    echo -e "$line3"
}

main
