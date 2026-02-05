# Claude Code Stats → Home Assistant

Push Claude Code usage statistics to Home Assistant for graphing over time.

## Sensors Created

| Sensor | Description |
|--------|-------------|
| `sensor.claude_daily_messages` | Messages sent today |
| `sensor.claude_daily_sessions` | Sessions started today |
| `sensor.claude_daily_tool_calls` | Tool calls made today |
| `sensor.claude_daily_tokens` | Tokens used today |
| `sensor.claude_total_sessions` | Total sessions all-time |
| `sensor.claude_total_messages` | Total messages all-time |
| `sensor.claude_input_tokens` | Cumulative input tokens |
| `sensor.claude_output_tokens` | Cumulative output tokens |
| `sensor.claude_cache_read_tokens` | Cache read tokens (huge number) |
| `sensor.claude_cache_creation_tokens` | Cache creation tokens |

## Setup on macOS (hypnos)

### 1. Install the script

```bash
sudo cp push-stats.sh /usr/local/bin/claude-stats-push
sudo chmod +x /usr/local/bin/claude-stats-push
```

### 2. Create environment file

Create `~/.claude-stats.env`:

```bash
export HASS_URL="https://hass.qilin-qilin.ts.net"
export HASS_TOKEN="your-long-lived-access-token"
```

Get a token from: Home Assistant → Profile → Security → Long-Lived Access Tokens

### 3. Test it

```bash
source ~/.claude-stats.env && claude-stats-push
```

Check Home Assistant → Developer Tools → States → filter for "claude"

### 4. Set up automatic updates

**Option A: launchd (recommended for macOS)**

```bash
cp com.claude.stats-pusher.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claude.stats-pusher.plist
```

**Option B: cron**

```bash
crontab -e
# Add:
*/15 * * * * source ~/.claude-stats.env && /usr/local/bin/claude-stats-push
```

## Home Assistant Dashboard

Add a card to your dashboard:

```yaml
type: entities
title: Claude Code Usage
entities:
  - entity: sensor.claude_daily_messages
  - entity: sensor.claude_daily_tool_calls
  - entity: sensor.claude_daily_tokens
  - entity: sensor.claude_total_sessions
```

Or a history graph:

```yaml
type: history-graph
title: Claude Usage Over Time
entities:
  - entity: sensor.claude_daily_messages
  - entity: sensor.claude_daily_tool_calls
hours_to_show: 168  # 1 week
```

## Troubleshooting

Check logs:
```bash
cat /tmp/claude-stats-push.log
cat /tmp/claude-stats-push.err
```

Verify launchd is running:
```bash
launchctl list | grep claude
```

Restart the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.claude.stats-pusher.plist
launchctl load ~/Library/LaunchAgents/com.claude.stats-pusher.plist
```
