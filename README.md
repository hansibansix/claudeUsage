# Claude Usage

A [DankMaterialShell](https://github.com/DankMaterialShell) bar widget that shows your Claude Pro/Max plan usage at a glance.

## Features

- **Bar pill** — shows current utilization percentage and reset countdown
- **Popout panel** — detailed breakdown of all usage windows:
  - 5-hour rolling rate limit
  - Weekly (7-day) usage
  - Weekly Opus / Sonnet model-specific limits
  - Extra usage spending ($used / $limit)
  - Plan info (type + tier)
- **Color-coded** — uses your theme's primary/warning/error colors based on utilization (< 50%, 50-80%, > 80%)
- **Auto-refresh** — polls the API on a configurable interval (default: 2 min)
- **OAuth token refresh** — expired tokens are refreshed automatically
- **Configurable** — toggle individual sections, choose which window to show in the pill

## Prerequisites

- [DankMaterialShell](https://github.com/DankMaterialShell) (Quickshell-based Wayland shell)
- [Claude Code](https://claude.ai/code) installed and logged in (`claude` CLI)
  - This creates `~/.claude/.credentials.json` with OAuth tokens

## Installation

```bash
# Clone into DMS plugins directory
git clone https://github.com/hansibansix/claudeUsage ~/.config/DankMaterialShell/plugins/claudeUsage

# Enable the plugin
dms plugin toggle claudeUsage

# Restart DMS
dms restart
```

## How it works

The widget reads your Claude Code OAuth credentials from `~/.claude/.credentials.json` and calls the Anthropic usage API (`api.anthropic.com/api/oauth/usage`) to fetch real-time plan utilization data — the same data shown at [claude.ai/settings/usage](https://claude.ai/settings/usage).

## Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Bar Display | Which window to show in the pill (5h or 7d) | 5-Hour |
| Refresh Interval | API polling interval in minutes | 2 |
| 5-Hour Window | Show/hide in popout | On |
| Weekly Window | Show/hide in popout | On |
| Weekly Opus | Show/hide in popout | On |
| Weekly Sonnet | Show/hide in popout | On |
| Extra Usage | Show/hide in popout | On |
| Plan Info | Show/hide in popout | On |

## Files

```
claudeUsage/
  plugin.json               # Plugin manifest
  ClaudeUsage.qml           # Main widget (pill + popout + API logic)
  ClaudeUsageSettings.qml   # Settings panel
  UsageUtils.js             # Formatting helpers
```
