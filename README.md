# Mighty Guardrails for Cline

Cline `PreToolUse` guardrails hook powered by **TryMightyAI Citadel**.

It can run in two modes:
- **Citadel OSS (local sidecar, free)**: text-only scanning over local HTTP (`citadel serve`)
- **Mighty Gateway (hosted, API key)**: text + multimodal scanning (images/PDFs/docs) via `POST /v1/scan`

It scans tool invocations before they run and returns a clear decision:

- **ALLOW**: proceed
- **WARN**: proceed with a warning (best-effort; Cline may ignore `warningMessage` depending on version)
- **BLOCK**: cancel the tool invocation with an error message

By default it calls a local Citadel HTTP sidecar (`citadel serve`). If Citadel is down or misconfigured, the hook still **hard-blocks** a few obvious high-risk patterns via regex (secrets, `curl | sh`, `rm -rf /`, `chmod 777`).

Tools enforced:
- `write_to_file`
- `replace_in_file`
- `execute_command`

Hard-block patterns:
- AWS access key: `AKIA[0-9A-Z]{16}`
- GitHub token: `ghp_[A-Za-z0-9]{20,}`
- OpenAI-like key: `sk-[A-Za-z0-9]{20,}`
- `curl ... | sh` (or `bash`)
- `rm -rf /`
- `chmod 777`

## Prereqs

- macOS or Linux
- `bash`, `jq`, `curl`
- Go (only if you want to build Citadel OSS locally)

## Install

### Option A: Citadel OSS (local server, text-only)

This project expects a local Citadel binary at `./bin/citadel`.

```bash
git clone https://github.com/TryMightyAI/citadel
cd citadel
# Build into this repo's ./bin/citadel
export GUARDRAILS_DIR="<REPO_ROOT>"
go build -o "${GUARDRAILS_DIR}/bin/citadel" ./cmd/gateway
```

Notes:
- This is the lightweight/heuristics build (fastest). Do not enable large model downloads for a quick demo.

Start Citadel server:

```bash
cd <REPO_ROOT>
./scripts/run-citadel.sh
```

Defaults to `http://127.0.0.1:8787`. Override with `CITADEL_PORT=...`.

### Option B: Mighty Gateway (API key, hosted, multimodal)

If you have a Mighty API key, the hook can also call the hosted Gateway `/v1/scan` endpoint.

Do not paste the key into files or commit it. Provide it via environment variable:

```bash
export MIGHTY_API_KEY="YOUR_KEY_HERE"
# Optional: prefer Gateway over local Citadel for scans
export MIGHTY_PREFER_GATEWAY=1
```

Multimodal note:
- With `MIGHTY_API_KEY` set, the `PreToolUse` hook will also attempt a **multimodal scan** for `execute_command` calls that reference an existing image/PDF file path (for example `./sephora.png`) and block if the Gateway returns `BLOCK`.
- Disable: `export MIGHTY_MULTIMODAL_FILES=0`
- Size limit: `export MIGHTY_MAX_FILE_MB=10`

### 3) Install the hook into Cline

Do not assume a specific hooks path. Use a placeholder:

- `<CLINE_HOOKS_DIR>`: your Cline hooks directory (global or project)

In many Cline versions, the hook script is loaded by **hook type filename** (for example: `PreToolUse`).

Recommended install command (global hooks on macOS):

```bash
mkdir -p "$HOME/Documents/Cline/Hooks"
cp scripts/cline-pretooluse-guard.sh "$HOME/Documents/Cline/Hooks/PreToolUse"
chmod +x "$HOME/Documents/Cline/Hooks/PreToolUse"
```

Common locations (verify in your Cline version):
- Global: `~/Documents/Cline/Hooks/`
- Project: `<REPO>/.clinerules/hooks/`

### 4) Enable it in Cline

1. Enable Hooks in Cline settings.
2. Open Cline "Hooks" UI and toggle **PreToolUse** on.

## Demo In 60 Seconds

From this repo:

```bash
cd <REPO_ROOT>
./scripts/setup.sh
```

### Demo 1: Works Everywhere (regex fallback, no Citadel required)

```bash
./scripts/demo-local.sh
```

The demo harness runs 3 cases through the hook:
- blocks `curl ... | sh`
- blocks an AWS-looking key in file content
- allows a benign `console.log(...)`

### Demo 2: Citadel OSS (local sidecar)

```bash
unset MIGHTY_API_KEY
./scripts/run-citadel.sh
./scripts/demo-local.sh
```

In the printed JSON, confirm `debug.backend` is `citadel-local`.

### Demo 3: Mighty Gateway (API key)

```bash
export MIGHTY_API_KEY="YOUR_KEY_HERE"
export MIGHTY_PREFER_GATEWAY=1
./scripts/demo-local.sh
```

In the printed JSON, confirm `debug.backend` is `mighty-gateway`.

More complete docs:
- `docs/GETTING_STARTED.md`
- `docs/CLINE_SETUP.md`

Multimodal (Gateway) quick test:

```bash
export MIGHTY_API_KEY="YOUR_KEY_HERE"
./scripts/test-mighty-multimodal.sh ./sephora.png
```

## Troubleshooting

- Check port:
  - default is `8787`
  - override: `export CITADEL_PORT=8787`
- Check server health:
  - `curl -i http://127.0.0.1:${CITADEL_PORT:-8787}/health`
- Debug hook output:
  - `CITADEL_DEBUG=1` adds `debug` fields to the hook JSON output.
- If Citadel is down:
  - regex fallback still blocks obvious secrets / `curl | sh` / `rm -rf /` / `chmod 777`
  - otherwise the hook fails open (allows) to avoid bricking the agent
- Cline shows `Aborted (exit: 130)`:
  - This is expected when a `PreToolUse` hook cancels a tool call.
  - Look for the short `errorMessage` like: `Blocked execute_command by Mighty Gateway ...`

## Env Vars

- `CITADEL_PORT` (default `8787`)
- `CITADEL_BIN` (default `./bin/citadel`)
- `CITADEL_DEBUG=1` (adds debug fields to the JSON response)
- `CITADEL_TIMEOUT_SECONDS` (default `2`)
- `CITADEL_MODE` (default `input`; you can try `output`)
- `MIGHTY_API_KEY` (enables hosted Gateway `/v1/scan`)
- `MIGHTY_GATEWAY_URL` (default `https://gateway.trymighty.ai`)
- `MIGHTY_PREFER_GATEWAY=1` (try hosted Gateway before local Citadel)
- `MIGHTY_PROFILE` (default `balanced`)
- `MIGHTY_ANALYSIS_MODE` (default `secure`)
