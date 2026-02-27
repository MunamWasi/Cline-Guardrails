# Mighty Guardrails for Cline

**Cline Guardrails Hook powered by Citadel (local server)**.

This repo gives you a production-ready `PreToolUse` hook wrapper for Cline with deterministic behavior:
- `BLOCK` -> one clean JSON response on stdout (`{"cancel":true,"errorMessage":"..."}`)
- `WARN` -> one clean single-line warning on stderr (allowed)
- `ALLOW` -> no stdout/stderr noise

It supports two scanner backends:
- **OSS mode**: local Citadel sidecar (`citadel serve`) over HTTP.
- **PRO mode**: Mighty Gateway API key (`/v1/scan`) including multimodal protection.

## Prereqs

- macOS or Linux
- `bash`, `jq`, `curl`
- Go (only if building Citadel OSS locally)

Run prerequisite check:

```bash
./scripts/setup.sh
```

## Super Easy Install (Recommended)

From repo root:

```bash
chmod +x ./install.sh
./install.sh
```

What this does:
- installs `PreToolUse` + `TaskCancel` into `~/Documents/Cline/Hooks` (or `CLINE_HOOKS_DIR`)
- creates `.env` from template/example if missing
- runs a local smoke test (block + allow)

Custom hooks directory:

```bash
./install.sh --hooks-dir "/absolute/path/to/Hooks"
```

## Environment Setup (.env only)

Never store keys in `settings.json` or JSON config files.

```bash
cp .env.template .env
```

Edit `.env` and set:

```dotenv
MIGHTY_API_KEY=
MIGHTY_MODE=pro|oss
MIGHTY_WARN_THRESHOLD=0.70
MIGHTY_BLOCK_THRESHOLD=0.85
```

Notes:
- `MIGHTY_MODE=oss` ignores `MIGHTY_API_KEY`.
- `MIGHTY_MODE=pro` prefers Mighty Gateway.
- The hook auto-loads `.env` from the workspace root, then falls back to process env.

## OSS Mode (Local Citadel)

Build Citadel binary into this repo:

```bash
git clone https://github.com/TryMightyAI/citadel
cd citadel
go build -o <REPO_ROOT>/bin/citadel ./cmd/gateway
```

Start local sidecar:

```bash
./scripts/run-citadel.sh
```

## PRO Mode (Mighty API Key)

Put your key in `.env`:

```dotenv
MIGHTY_MODE=pro
MIGHTY_API_KEY=your_key_here
```

Optional explicit override:

```bash
export MIGHTY_PREFER_GATEWAY=1
```

Multimodal check helper:

```bash
./scripts/test-mighty-multimodal.sh /absolute/path/to/file.png
```

## Demo in 60 Seconds

```bash
./scripts/setup.sh
./scripts/demo-local.sh
```

This runs three cases through the guardrails logic:
- unsafe command (`curl | sh`) -> blocked
- secret-like write (`AKIA...`) -> blocked
- benign content -> allowed

## Cline Setup (Hooks UI)

If you used `./install.sh`, these files are already written for you. This section is only for manual setup.

### 1) Open Cline panel in VS Code

- Click the Cline icon in the left activity bar, or
- `Cmd+Shift+P` -> search `Cline` -> open/focus panel.

### 2) In Cline -> Hooks -> Global Hooks -> `PreToolUse`, paste exactly

```bash
#!/usr/bin/env bash
exec "<REPO_ROOT>/scripts/cline-pretooluse.sh"
```

### 3) In Cline -> Hooks -> Global Hooks -> `TaskCancel`, paste exactly

```bash
#!/usr/bin/env bash
exec "<REPO_ROOT>/scripts/cline-taskcancel.sh"
```

### 4) Ensure hook scripts are executable

```bash
chmod +x <REPO_ROOT>/scripts/cline-pretooluse.sh
chmod +x <REPO_ROOT>/scripts/cline-taskcancel.sh
chmod +x <REPO_ROOT>/scripts/mighty-guardrails
```

## What You Should See in Cline

- Blocked action: one concise message, e.g.
  - `Blocked by Mighty Guardrails (confidence: 0.88): ...`
  - or `Blocked by Host Guardrails (Cline): ...` for `curl | sh` style host safety text
- Warn action: one concise warning line and execution continues.
- Allowed action: no hook noise.

`Aborted (exit: 130)` is expected when `PreToolUse` returns `cancel=true`.

## Troubleshooting

- Check sidecar port:
  - `echo ${CITADEL_PORT:-8787}`
  - `curl -i http://127.0.0.1:${CITADEL_PORT:-8787}/health`
- Show richer debug from scanner layer:
  - `export CITADEL_DEBUG=1`
- If Citadel is down:
  - The regex fallback still hard-blocks obvious unsafe patterns.
  - Non-matching payloads fail open to avoid bricking Cline tasks.
- If hooks do not run:
  - Confirm they are enabled in Cline Hooks UI.
  - Confirm the pasted path is absolute and executable.

## Optional: Local Runner Tests

```bash
./scripts/test-cline-pretooluse.sh
./scripts/test-install.sh
```

Covers:
- secret redaction
- warn/block threshold routing
- allow silence (no stdout)
- host guardrails label routing
- installer workflow

## Create a Shareable Package

```bash
./scripts/package-release.sh
```

Outputs:
- `dist/mighty-guardrails-cline_<timestamp>.tar.gz`
- `dist/...sha256` (if `shasum` exists)

## Public Consumption Quickstart

```bash
git clone https://github.com/<YOUR_ORG_OR_USER>/<YOUR_REPO>.git
cd <YOUR_REPO>
./install.sh
```

Then:
1. Set `MIGHTY_MODE` and `MIGHTY_API_KEY` in `.env` for pro mode.
2. Keep Cline Global Hooks enabled.
3. Run `./scripts/demo-local.sh` to validate behavior.
