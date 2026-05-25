# Codex Task: Safe Commit Review

You are working inside a private repository.

Objective:
Inspect current repo changes and prepare a safe commit recommendation.

Rules:
- Do not push.
- Do not delete files.
- Do not modify system settings.
- Do not commit secrets, tokens, local credentials, runtime auth files, or machine-specific config.
- If tracked runtime files are modified, report them separately.
- If a `.gitignore` update is needed, propose it clearly.
- Prefer small, focused commits.

Required output:
1. Current branch
2. Git status summary
3. Files changed
4. Risk review
5. Suggested staging list
6. Suggested commit message
7. Exact commands to run manually
8. Anything that should remain uncommitted
