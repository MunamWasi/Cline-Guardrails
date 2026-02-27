# Getting Started

## Fast path

```bash
cd <REPO_ROOT>
./install.sh
./scripts/demo-local.sh
```

`./install.sh` wires hooks, prepares `.env`, and runs smoke tests.

Expected:
- unsafe `curl | sh` input is blocked
- secret-looking key write is blocked
- benign write is allowed

## Choose backend mode

Recommended order:
1. Configure OSS mode first (Go + local Citadel).
2. Verify behavior with the demo.
3. Configure PRO mode (Gateway + API key) after OSS is confirmed.

### OSS mode (local Citadel sidecar)

```bash
# build once
git clone https://github.com/TryMightyAI/citadel
cd citadel
go build -o <REPO_ROOT>/bin/citadel ./cmd/gateway

# run sidecar
cd <REPO_ROOT>
./scripts/run-citadel.sh
```

Use `.env`:

```dotenv
MIGHTY_MODE=oss
MIGHTY_WARN_THRESHOLD=0.70
MIGHTY_BLOCK_THRESHOLD=0.85
```

### PRO mode (Mighty Gateway API key)

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

## Hook scripts to use in Cline

Use the robust runner, not the raw scanner:
- `<REPO_ROOT>/scripts/cline-pretooluse.sh`
- `<REPO_ROOT>/scripts/cline-taskcancel.sh`
