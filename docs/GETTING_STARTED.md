# Getting Started

## Fast path

```bash
cd /absolute/path/to/cline-mighty-guardrails/Cline-Hackathon
./scripts/setup.sh
./scripts/demo-local.sh
```

Expected:
- unsafe `curl | sh` input is blocked
- secret-looking key write is blocked
- benign write is allowed

## Choose backend mode

### OSS mode (local Citadel sidecar)

```bash
# build once
git clone https://github.com/TryMightyAI/citadel
cd citadel
go build -o /absolute/path/to/cline-mighty-guardrails/Cline-Hackathon/bin/citadel ./cmd/gateway

# run sidecar
cd /absolute/path/to/cline-mighty-guardrails/Cline-Hackathon
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
./scripts/test-mighty-multimodal.sh /absolute/path/to/file.png
```

## Hook scripts to use in Cline

Use the robust runner, not the raw scanner:
- `/absolute/path/to/cline-mighty-guardrails/Cline-Hackathon/scripts/cline-pretooluse.sh`
- `/absolute/path/to/cline-mighty-guardrails/Cline-Hackathon/scripts/cline-taskcancel.sh`
