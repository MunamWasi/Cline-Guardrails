# Getting Started

## TL;DR (Copy/Paste)

```bash
git clone https://github.com/MunamWasi/Cline-Guardrails.git
cd Cline-Guardrails
./install.sh
./scripts/demo-local.sh
```

## Recommended Setup Order

1. OSS first: build/run local Citadel.
2. Verify local behavior.
3. PRO second: add API key for Gateway/multimodal.

## OSS Mode (Go + Local Citadel)

```bash
git clone https://github.com/TryMightyAI/citadel
cd citadel
go build -o <REPO_ROOT>/bin/citadel ./cmd/gateway

cd <REPO_ROOT>
./scripts/run-citadel.sh
```

Use `.env`:

```dotenv
MIGHTY_MODE=oss
MIGHTY_WARN_THRESHOLD=0.70
MIGHTY_BLOCK_THRESHOLD=0.85
```

## PRO Mode (Gateway + API Key)

Use `.env`:

```dotenv
MIGHTY_MODE=pro
MIGHTY_API_KEY=your_key_here
MIGHTY_WARN_THRESHOLD=0.70
MIGHTY_BLOCK_THRESHOLD=0.85
```

Multimodal test:

```bash
./scripts/test-mighty-multimodal.sh <PATH_TO_IMAGE_OR_PDF>
```

## Manual Hook Targets (if you skip installer)

- `<REPO_ROOT>/scripts/cline-pretooluse.sh`
- `<REPO_ROOT>/scripts/cline-taskcancel.sh`
