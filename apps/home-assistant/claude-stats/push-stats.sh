#!/bin/bash
# Push Claude Code stats to Home Assistant
# Parses session JSONL files directly for accurate stats
#
# Setup:
#   1. Create a long-lived access token in HA (Profile -> Security -> Long-Lived Access Tokens)
#   2. Set HASS_URL and HASS_TOKEN environment variables (or edit below)
#   3. Add to crontab: */15 * * * * /path/to/push-stats.sh

set -euo pipefail

# Configuration
HASS_URL="${HASS_URL:-https://hass.qilin-qilin.ts.net}"
HASS_TOKEN="${HASS_TOKEN:-}"
CLAUDE_DIR="${HOME}/.claude"
PROJECTS_DIR="${CLAUDE_DIR}/projects"

if [[ -z "$HASS_TOKEN" ]]; then
  echo "Error: HASS_TOKEN not set" >&2
  exit 1
fi

if [[ ! -d "$PROJECTS_DIR" ]]; then
  echo "Error: Claude projects directory not found: $PROJECTS_DIR" >&2
  exit 1
fi

today=$(date +%Y-%m-%d)

# Parse all JSONL files and compute stats
# This gives us accurate real-time data instead of relying on the cache
compute_stats() {
  find "$PROJECTS_DIR" -name "*.jsonl" -type f 2>/dev/null | while read -r jsonl; do
    cat "$jsonl"
  done | jq -s --arg today "$today" '
    # Filter to assistant messages with usage data
    [.[] | select(.type == "assistant" and .message.usage != null)] |
    
    # Group by date (from timestamp)
    group_by(.timestamp | split("T")[0]) |
    
    # Compute per-day and total stats
    {
      daily: (
        [.[] | {
          date: (.[0].timestamp | split("T")[0]),
          messages: length,
          input_tokens: ([.[].message.usage.input_tokens // 0] | add),
          output_tokens: ([.[].message.usage.output_tokens // 0] | add),
          cache_read: ([.[].message.usage.cache_read_input_tokens // 0] | add),
          cache_creation: ([.[].message.usage.cache_creation_input_tokens // 0] | add)
        }]
      ),
      totals: {
        messages: ([.[][] | select(.message.usage != null)] | length),
        input_tokens: ([.[][][].message.usage.input_tokens // 0] | add),
        output_tokens: ([.[][][].message.usage.output_tokens // 0] | add),
        cache_read: ([.[][][].message.usage.cache_read_input_tokens // 0] | add),
        cache_creation: ([.[][][].message.usage.cache_creation_input_tokens // 0] | add)
      }
    } |
    
    # Add today specific stats
    . + {
      today: (
        .daily | map(select(.date == $today)) | .[0] // {
          date: $today,
          messages: 0,
          input_tokens: 0,
          output_tokens: 0,
          cache_read: 0,
          cache_creation: 0
        }
      )
    }
  '
}

# Simpler approach: just count from JONLs
stats=$(find "$PROJECTS_DIR" -name "*.jsonl" -type f -print0 2>/dev/null | \
  xargs -0 cat 2>/dev/null | \
  jq -s --arg today "$today" '
    [.[] | select(.message.usage != null)] |
    {
      today_messages: ([.[] | select(.timestamp | startswith($today))] | length),
      today_input: ([.[] | select(.timestamp | startswith($today)) | .message.usage.input_tokens // 0] | add // 0),
      today_output: ([.[] | select(.timestamp | startswith($today)) | .message.usage.output_tokens // 0] | add // 0),
      today_cache_read: ([.[] | select(.timestamp | startswith($today)) | .message.usage.cache_read_input_tokens // 0] | add // 0),
      today_cache_creation: ([.[] | select(.timestamp | startswith($today)) | .message.usage.cache_creation_input_tokens // 0] | add // 0),
      total_messages: length,
      total_input: ([.[].message.usage.input_tokens // 0] | add // 0),
      total_output: ([.[].message.usage.output_tokens // 0] | add // 0),
      total_cache_read: ([.[].message.usage.cache_read_input_tokens // 0] | add // 0),
      total_cache_creation: ([.[].message.usage.cache_creation_input_tokens // 0] | add // 0)
    }
  ')

# Extract values
today_messages=$(echo "$stats" | jq -r '.today_messages // 0')
today_input=$(echo "$stats" | jq -r '.today_input // 0')
today_output=$(echo "$stats" | jq -r '.today_output // 0')
today_cache_read=$(echo "$stats" | jq -r '.today_cache_read // 0')
today_cache_creation=$(echo "$stats" | jq -r '.today_cache_creation // 0')
today_tokens=$((today_input + today_output))

total_messages=$(echo "$stats" | jq -r '.total_messages // 0')
total_input=$(echo "$stats" | jq -r '.total_input // 0')
total_output=$(echo "$stats" | jq -r '.total_output // 0')
total_cache_read=$(echo "$stats" | jq -r '.total_cache_read // 0')
total_cache_creation=$(echo "$stats" | jq -r '.total_cache_creation // 0')

# Function to update HA sensor
update_sensor() {
  local entity_id=$1
  local state=$2
  local friendly_name=$3
  local unit=${4:-""}
  local icon=${5:-"mdi:robot"}

  local attributes="{\"friendly_name\": \"$friendly_name\", \"icon\": \"$icon\""
  if [[ -n "$unit" ]]; then
    attributes="$attributes, \"unit_of_measurement\": \"$unit\""
  fi
  attributes="$attributes}"

  curl -s -X POST "${HASS_URL}/api/states/sensor.${entity_id}" \
    -H "Authorization: Bearer ${HASS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"state\": \"$state\", \"attributes\": $attributes}" > /dev/null
}

# Update daily sensors
update_sensor "claude_daily_messages" "$today_messages" "Claude Daily Messages" "messages" "mdi:message-text"
update_sensor "claude_daily_tokens" "$today_tokens" "Claude Daily Tokens" "tokens" "mdi:counter"
update_sensor "claude_daily_input_tokens" "$today_input" "Claude Daily Input Tokens" "tokens" "mdi:arrow-right"
update_sensor "claude_daily_output_tokens" "$today_output" "Claude Daily Output Tokens" "tokens" "mdi:arrow-left"

# Update total sensors
update_sensor "claude_total_messages" "$total_messages" "Claude Total Messages" "messages" "mdi:message-text"
update_sensor "claude_total_input_tokens" "$total_input" "Claude Total Input Tokens" "tokens" "mdi:arrow-right"
update_sensor "claude_total_output_tokens" "$total_output" "Claude Total Output Tokens" "tokens" "mdi:arrow-left"
update_sensor "claude_total_cache_read" "$total_cache_read" "Claude Cache Read Tokens" "tokens" "mdi:cached"
update_sensor "claude_total_cache_creation" "$total_cache_creation" "Claude Cache Creation Tokens" "tokens" "mdi:database-plus"

echo "[$(date)] Stats pushed: today=${today_messages} msgs, ${today_tokens} tokens | total=${total_messages} msgs"
