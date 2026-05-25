# Example Codex Output

```text
[codex-worker] Prompt: codex-safe-commit.md
[codex-worker] Repo: D:\dev\projects\example-repo

Current branch: main

Git status:
 M .gitignore
 M identity/device-auth.json
 M openclaw.json

Risk review:
- .gitignore is safe to commit.
- identity/device-auth.json should remain uncommitted.
- openclaw.json appears machine-specific and should remain local.

Suggested staging:
git add .gitignore

Suggested commit:
git commit -m "chore: ignore local OpenClaw runtime files"

Do not push unless explicitly requested.
```
