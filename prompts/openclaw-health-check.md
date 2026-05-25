# OpenClaw Task: Health Check

Objective:
Check OpenClaw runtime health.

Check:
- gateway status
- local listening ports
- available skills
- recent errors
- authentication/runtime files existence without exposing content

Rules:
- Do not modify system settings.
- Do not delete files.
- Do not expose credentials.

Required output:
1. Gateway status
2. Runtime status
3. Recent errors
4. Available skills/tools
5. Recommended fix if unhealthy
