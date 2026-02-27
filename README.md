# Cline Guardrails (Mighty + Citadel)

Cline `PreToolUse`/`TaskCancel` hooks that enforce ALLOW/WARN/BLOCK before risky tool actions execute.

## TL;DR (Copy/Paste)

```bash
git clone https://github.com/MunamWasi/Cline-Guardrails.git
cd Cline-Guardrails
chmod +x ./install.sh
./install.sh
```

That single script will:
- install `PreToolUse` and `TaskCancel` hooks into `~/Documents/Cline/Hooks` (or `CLINE_HOOKS_DIR`)
- create `.env` if missing
- run a smoke test

## Quick Start After Install

1. Open `.env` and choose mode.
2. In Cline, keep Global Hooks enabled.
3. Run a quick demo:

```bash
./scripts/demo-local.sh
```

## Install Script Options

```bash
./install.sh --help
```

Most useful:

```bash
./install.sh --hooks-dir "<CLINE_HOOKS_DIR>"
./install.sh --force
./install.sh --skip-smoke
```

## Setup Order (Recommended)

1. Set up OSS first (Go + local sidecar).
2. Validate behavior.
3. Enable PRO mode with API key.

## OSS Setup (Go / Local Citadel First)

Build Citadel OSS binary:

```bash
git clone https://github.com/TryMightyAI/citadel
cd citadel
go build -o <REPO_ROOT>/bin/citadel ./cmd/gateway
```

Run sidecar:

```bash
cd <REPO_ROOT>
./scripts/run-citadel.sh
```

Use `.env`:

```dotenv
MIGHTY_MODE=oss
MIGHTY_WARN_THRESHOLD=0.70
MIGHTY_BLOCK_THRESHOLD=0.85
```

## PRO Setup (Mighty Gateway After OSS)

Use `.env`:

```dotenv
MIGHTY_MODE=pro
MIGHTY_API_KEY=your_key_here
MIGHTY_WARN_THRESHOLD=0.70
MIGHTY_BLOCK_THRESHOLD=0.85
```

Optional override:

```bash
export MIGHTY_PREFER_GATEWAY=1
```

Multimodal check:

```bash
./scripts/test-mighty-multimodal.sh <PATH_TO_IMAGE_OR_PDF>
```

## Environment Rules

- Store secrets in `.env` only.
- Do not store API keys in JSON settings.
- The hook loads `.env` from workspace root, then falls back to process env.

## Manual Cline Hook Setup (Only If Needed)

If you used `./install.sh`, you can skip this.

`PreToolUse` script body:

```bash
#!/usr/bin/env bash
exec "<REPO_ROOT>/scripts/cline-pretooluse.sh"
```

`TaskCancel` script body:

```bash
#!/usr/bin/env bash
exec "<REPO_ROOT>/scripts/cline-taskcancel.sh"
```

Make sure scripts are executable:

```bash
chmod +x <REPO_ROOT>/scripts/cline-pretooluse.sh
chmod +x <REPO_ROOT>/scripts/cline-taskcancel.sh
chmod +x <REPO_ROOT>/scripts/mighty-guardrails
```

## Expected Runtime Behavior

- BLOCK: one clean JSON block message.
- WARN: one single-line warning, then continue.
- ALLOW: no hook noise.
- `Aborted (exit: 130)` is expected for blocked tool calls.

## Troubleshooting

Check sidecar:

```bash
echo ${CITADEL_PORT:-8787}
curl -i http://127.0.0.1:${CITADEL_PORT:-8787}/health
```

If Citadel is down:
- regex fallback still blocks obvious unsafe payloads
- non-matching payloads fail open

Enable scanner debug:

```bash
export CITADEL_DEBUG=1
```

## Test Commands

```bash
./scripts/test-install.sh
./scripts/test-cline-pretooluse.sh
```

## Build Shareable Package

```bash
./scripts/package-release.sh
```

Outputs:
- `dist/mighty-guardrails-cline_<timestamp>.tar.gz`
- `dist/...sha256` (when `shasum` exists)
