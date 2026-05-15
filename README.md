# cc-switch

Switch between Claude Code configuration profiles by merging profile settings into `~/.claude/settings.json`. Non-profile keys (hooks, theme, plugins) are always preserved.

## Requirements

- `bash`
- `jq` — `sudo apt install jq`

## Usage

```bash
./cc-switch.sh <profile-name> [--reset]
```

**Switch to a profile:**
```bash
./cc-switch.sh profile1
```

**Switch with interactive model selection** (first time only for profiles with `model_slots`):
```bash
./cc-switch.sh profile2
# Prompts you to pick sonnet/opus/default models from a numbered list
# Saves your choices — next run is instant
```

**Re-select models:**
```bash
./cc-switch.sh profile2 --reset
```

## Profiles

Profiles are defined in `profiles.json`. Two types of values:

- **Static** — written directly into `~/.claude/settings.json`
- **`null` (model slots)** — you're prompted to pick from `available_models` on first run; choice is saved to `preferences.json`

### Example profiles.json

```json
{
  "profile1": {
    "env": {
      "ANTHROPIC_BASE_URL": "https://your-router.example.com/v1",
      "ANTHROPIC_AUTH_TOKEN": "YOUR_API_KEY_HERE",
      "ANTHROPIC_MODEL": "cc/claude-sonnet-4-6",
      "ANTHROPIC_DEFAULT_SONNET_MODEL": "cc/claude-sonnet-4-6",
      "ANTHROPIC_DEFAULT_OPUS_MODEL": "cc/claude-opus-4-7",
      "ANTHROPIC_DEFAULT_HAIKU_MODEL": "cc/claude-haiku-4-5-20251001"
    },
    "model": "sonnet"
  },
  "profile2": {
    "env": {
      "ANTHROPIC_BASE_URL": "https://your-router.example.com/v1",
      "ANTHROPIC_AUTH_TOKEN": "YOUR_API_KEY_HERE",
      "ANTHROPIC_MODEL": null,
      "ANTHROPIC_DEFAULT_SONNET_MODEL": null,
      "ANTHROPIC_DEFAULT_OPUS_MODEL": null,
      "ANTHROPIC_DEFAULT_HAIKU_MODEL": "cc/claude-haiku-4-5-20251001"
    },
    "hasCompletedOnboarding": true,
    "model_slots": [
      "ANTHROPIC_DEFAULT_SONNET_MODEL",
      "ANTHROPIC_DEFAULT_OPUS_MODEL",
      "ANTHROPIC_MODEL"
    ],
    "available_models": [
      "provider/model-a",
      "provider/model-b",
      "provider/model-c"
    ]
  }
}
```

## Setup

1. Copy `profiles.json` and fill in your `ANTHROPIC_AUTH_TOKEN` values
2. `chmod +x cc-switch.sh`
3. Run `./cc-switch.sh profile1`

`preferences.json` is auto-created when you first select models — no need to create it manually. It is gitignored.

## Testing

```bash
bash test.sh
```

All 7 tests run in isolated temp directories and never touch your real `~/.claude/settings.json`.
