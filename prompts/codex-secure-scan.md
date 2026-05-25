# Codex Task: Secure Scan

Objective:
Scan this private repository for unsafe content before commit.

Check for:
- API keys
- tokens
- passwords
- private keys
- auth files
- local device identity files
- `.env` files
- generated logs
- large binary files
- machine-specific config
- accidental build artifacts

Rules:
- Do not push.
- Do not delete files.
- Do not modify system settings.
- Do not reveal secret values in output. Mask them.
- If secrets are found, report file path and remediation steps only.

Required output:
1. Security scan summary
2. Suspicious files
3. Whether `.gitignore` needs update
4. Files safe to commit
5. Files unsafe to commit
6. Recommended next action
