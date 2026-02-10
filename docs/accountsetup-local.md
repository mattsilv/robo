# Using an API Key with Claude Code (Hackathon Setup)

For this project and the Claude Code Hackathon, I need to use an API key, whereas on the rest of my computer, I use my Claude Code OAuth subscription.

## How Authentication Works

Claude Code supports multiple authentication methods simultaneously, including Claude.ai (OAuth), API keys, Azure, Bedrock, and Vertex. On macOS, credentials are stored in the encrypted Keychain.

## Recommended Setup: `ANTHROPIC_API_KEY`

The officially documented way to use an API key is the `ANTHROPIC_API_KEY` environment variable. This overrides subscription auth for a single session without affecting your default OAuth setup.

### Option 1: Shell Alias (Simplest)

Add to `~/.zshrc`:

```bash
alias claude-hackathon='ANTHROPIC_API_KEY=sk-ant-XXXXX claude'
```

Then use `claude-hackathon` to launch Claude Code with your API key for this project.

### Option 2: Export Before Launching

```bash
cd /Users/m/gh/hackathon-cc-2026/robo
export ANTHROPIC_API_KEY=sk-ant-XXXXX
claude
```

### Option 3: Project `.env` File

Create a `.env` file in the project root (add to `.gitignore`):

```
ANTHROPIC_API_KEY=sk-ant-XXXXX
```

Then source it before launching:

```bash
source .env && claude
```

### Verification

Once Claude Code starts, confirm it's using the API key rather than your subscription account.

## Advanced: Custom API Key Helper Scripts

Claude Code supports an `apiKeyHelper` setting that runs a shell script to return API keys dynamically. This script:

- Is called after 5 minutes by default or on HTTP 401 responses
- Can be customized with `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` environment variable
- Allows dynamic key selection based on context

This is useful if you need to rotate keys or pull them from a secrets manager.

## What NOT to Do

- **Don't use `CLAUDE_HOME`** — not found in official Claude Code documentation; sourced from a third-party GitHub Gist
- **Don't set up Docker containers** — unnecessary complexity for switching auth on a single project
- **Don't create separate `~/.claude-*` config directories** — adds complexity when `ANTHROPIC_API_KEY` handles it cleanly
- **Don't commit API keys** — always use `.gitignore` or environment variables
