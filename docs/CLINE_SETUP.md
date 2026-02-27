# Cline Hook Setup

## Recommended: auto-install hooks

```bash
cd <REPO_ROOT>
./install.sh
```

If you run this, you can skip the manual hook paste steps below.

## Open Cline panel

In VS Code:
- Click the Cline icon on the left sidebar, or
- `Cmd+Shift+P` -> type `Cline` -> run the open/focus command.

## Configure Hook: PreToolUse

In **Cline -> Hooks -> Global Hooks -> PreToolUse**, paste:

```bash
#!/usr/bin/env bash
exec "<REPO_ROOT>/scripts/cline-pretooluse.sh"
```

## Configure Hook: TaskCancel

In **Cline -> Hooks -> Global Hooks -> TaskCancel**, paste:

```bash
#!/usr/bin/env bash
exec "<REPO_ROOT>/scripts/cline-taskcancel.sh"
```

## Make scripts executable

```bash
chmod +x <REPO_ROOT>/scripts/cline-pretooluse.sh
chmod +x <REPO_ROOT>/scripts/cline-taskcancel.sh
chmod +x <REPO_ROOT>/scripts/mighty-guardrails
```

## Environment rules

- Put secrets in workspace `.env` only.
- Do not put API keys in Cline JSON settings.
- `.env.template` shows required variables.

## Behavior in Cline

- Block -> one clean message with source label:
  - `Blocked by Mighty Guardrails ...`
  - or `Blocked by Host Guardrails (Cline) ...`
- Warn -> one single-line warning on stderr, tool proceeds.
- Allow -> no hook output.

`Aborted (exit: 130)` is normal for blocked tool execution.
