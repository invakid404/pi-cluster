#!/bin/bash
# Push Claude Code stats to Home Assistant
# Run this via cron on the machine where Claude Code runs
#
# Setup:
#   1. Create a long-lived access token in HA (Profile -> Security -> Long-Lived Access Tokens)
#   2. Set HASS_URL and HASS_TOKEN environment variables (or edit below)
#   3. Add to crontab: */15 * * * * /path/to/push-stats.sh

set -euo pipefail

# Configuration - override via environment or edit here
HASS_URL="${HASS_URL:-https://hass.qilin-qilin.ts.net}"
HASS_TOKEN="${HASS_TOKEN:-}"
STATS_FILE="${HOME}/.claude/stats-cache.json"

if [[ -z "$HASS_TOKEN" ]]; then
  echo "Error: HASS_TOKEN not set" >&2
  exit 1
fi

if [[ ! -f "$STATS_FILE" ]]; then
  echo "Error: Stats file not found: $STATS_FILE" >&2
  exit 1
fi

# Read the stats file
stats=$(cat "$STATS_FILE")

# Get today's date
today=$(date +%Y-%m-%d)

# Extract today's activity (or zeros if not present)
daily_messages=$(echo "$stats" | jq -r --arg d "$today" '.dailyActivity[] | select(.date == $d) | .messageCount // 0')
daily_sessions=$(echo "$stats" | jq -r --arg d "$today" '.dailyActivity[] | select(.date == $d) | .sessionCount // 0')
daily_tool_calls=$(echo "$stats" | jq -r --arg d "$today" '.dailyActivity[] | select(.date == $d) | .toolCallCount // 0')
daily_tokens=$(echo "$stats" | jq -r --arg d "$today" '.dailyModelTokens[] | select(.date == $d) | [.tokensByModel[]] | add // 0')

# Default to 0 if empty
daily_messages=${daily_messages:-0}
daily_sessions=${daily_sessions:-0}
daily_tool_calls=${daily_tool_calls:-0}
daily_tokens=${daily_tokens:-0}

# Extract cumulative stats
total_sessions=$(echo "$stats" | jq -r '.totalSessions // 0')
total_messages=$(echo "$stats" | jq -r '.totalMessages // 0')

# Extract model usage totals
input_tokens=$(echo "$stats" | jq -r '[.modelUsage[].inputTokens] | add // 0')
output_tokens=$(echo "$stats" | jq -r '[.modelUsage[].outputTokens] | add // 0')
cache_read_tokens=$(echo "$stats" | jq -r '[.modelUsage[].cacheReadInputTokens] | add // 0')
cache_creation_tokens=$(echo "$stats" | jq -r '[.modelUsage[].cacheCreationInputTokens] | add // 0')

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

# Update all sensors
update_sensor "claude_daily_messages" "$daily_messages" "Claude Daily Messages" "messages" "mdi:message-text"
update_sensor "claude_daily_sessions" "$daily_sessions" "Claude Daily Sessions" "sessions" "mdi:application"
update_sensor "claude_daily_tool_calls" "$daily_tool_calls" "Claude Daily Tool Calls" "calls" "mdi:wrench"
update_sensor "claude_daily_tokens" "$daily_tokens" "Claude Daily Tokens" "tokens" "mdi:counter"

update_sensor "claude_total_sessions" "$total_sessions" "Claude Total Sessions" "sessions" "mdi:application"
update_sensor "claude_total_messages" "$total_messages" "Claude Total Messages" "messages" "mdi:message-text"

update_sensor "claude_input_tokens" "$input_tokens" "Claude Input Tokens" "tokens" "mdi:arrow-right"
update_sensor "claude_output_tokens" "$output_tokens" "Claude Output Tokens" "tokens" "mdi:arrow-left"
update_sensor "claude_cache_read_tokens" "$cache_read_tokens" "Claude Cache Read Tokens" "tokens" "mdi:cached"
update_sensor "claude_cache_creation_tokens" "$cache_creation_tokens" "Claude Cache Creation Tokens" "tokens" "mdi:database-plus"

echo "Stats pushed to Home Assistant at $(date)"
