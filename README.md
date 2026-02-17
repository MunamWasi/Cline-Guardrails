# Mighty Guardrails for Cline

Cline `PreToolUse` guardrails hook powered by **TryMightyAI Citadel** (local server). It scans tool invocations before they run and returns a clear decision:

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

### 1) Build Citadel OSS (local server)

This project expects a local Citadel binary at `./bin/citadel`.

```bash
git clone https://github.com/TryMightyAI/citadel
cd citadel
go build -o ../cline-mighty-guardrails/bin/citadel ./cmd/gateway
```

Notes:
- This is the lightweight/heuristics build (fastest). Do not enable large model downloads for a quick demo.

### 2) Start Citadel server

```bash
cd cline-mighty-guardrails
./scripts/run-citadel.sh
```

Defaults to `http://127.0.0.1:8787`. Override with `CITADEL_PORT=...`.

### Optional: Use Mighty Gateway (paid, API key)

If you have a Mighty API key, the hook can also call the hosted Gateway `/v1/scan` endpoint.

Do not paste the key into files or commit it. Provide it via environment variable:

```bash
export MIGHTY_API_KEY="YOUR_KEY_HERE"
# Optional: prefer Gateway over local Citadel for scans
export MIGHTY_PREFER_GATEWAY=1
```

### 3) Install the hook into Cline

Do not assume a specific hooks path. Use a placeholder:

- `<CLINE_HOOKS_DIR>`: your Cline hooks directory (global or project)

Example install command (hook name is arbitrary; it just needs to be executable):

```bash
cp scripts/cline-pretooluse-guard.sh <CLINE_HOOKS_DIR>/mighty-guardrails
chmod +x <CLINE_HOOKS_DIR>/mighty-guardrails
```

Common locations (verify in your Cline version):
- Global: `~/Documents/Cline/Hooks/`
- Project: `<REPO>/.clinerules/hooks/`

### 4) Enable it in Cline

1. Enable Hooks in Cline settings.
2. Open Cline "Hooks" UI, find `mighty-guardrails` under `PreToolUse` hooks, and toggle it on.

## Demo In 60 Seconds

From this repo:

```bash
cd cline-mighty-guardrails
./scripts/setup.sh
./scripts/demo-local.sh
```

The demo harness runs 3 cases:
- blocks `curl ... | sh`
- blocks an AWS-looking key in file content
- allows a benign `console.log(...)`

More complete docs:
- `/Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails/docs/GETTING_STARTED.md`
- `/Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails/docs/CLINE_SETUP.md`

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
