# Getting Started (Anyone Can Demo)

This project is a **Cline PreToolUse guardrails hook**. You can demo it locally without Cline, and then install it into Cline.

## 0) Prereqs

- macOS or Linux
- `bash`, `jq`, `curl`

Verify:

```bash
cd /Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails
./scripts/setup.sh
```

## 1) Fastest Demo (No Cline Required)

Runs 3 simulated tool invocations through the hook and checks PASS/FAIL.

```bash
cd /Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails
./scripts/demo-local.sh
```

Expected behavior:
- Unsafe `curl ... | sh` -> `{"cancel": true, ...}`
- Secret-looking AWS key -> `{"cancel": true, ...}`
- Benign write -> `{"cancel": false, ...}`

This works even if Citadel is not installed, because the hook has a small regex hard-block fallback.

## 2) Demo With Mighty Gateway (Hosted, API Key)

If you have a Mighty API key, the hook can call the hosted Gateway (`/v1/scan`).

Important:
- Do not paste API keys into files or commit them.
- Prefer exporting env vars in the same shell you use to launch the demo.

```bash
cd /Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails

export MIGHTY_API_KEY="YOUR_KEY"
export MIGHTY_PREFER_GATEWAY=1
export CITADEL_DEBUG=1

./scripts/demo-local.sh
```

In the printed JSON, confirm:
- `debug.backend` is `mighty-gateway`
- `debug.httpCode` is `200`

## 3) Demo With Local Citadel (Optional)

If you want fully local scanning, build Citadel OSS and run the local sidecar.

Build:

```bash
git clone https://github.com/TryMightyAI/citadel
cd citadel
go build -o /Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails/bin/citadel ./cmd/gateway
```

Run:

```bash
cd /Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails
./scripts/run-citadel.sh
```

Then re-run:

```bash
./scripts/demo-local.sh
```

## 4) Install Into Cline

Follow `/Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails/docs/CLINE_SETUP.md`.

