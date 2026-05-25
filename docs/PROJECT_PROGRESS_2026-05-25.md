# JJ AI Dispatcher — Project Progress
Date: 2026-05-25

---

## Current Baseline

```text
Version: v0.2
Status: ACTIVE
```

Git:

```text
Branch: main
HEAD: e7966ba
Working Tree: clean
Origin Sync: verify before update
```

---

## Project Definition

Project purpose:

```text
ChatGPT = Brain
Dispatcher = Execution Controller
Codex = Coding Worker
Git = Control Point
```

Primary objective:

```text
Reduce:

ChatGPT
→ copy
→ Codex chat
→ manual commit
→ manual push

Toward:

ChatGPT
→ Dispatcher
→ Codex
→ Dispatcher Git Control
→ Feedback Loop
```

---

## Phase Status

### Phase 1 — Dispatcher Core

Status:

```text
COMPLETED
```

Delivered:

```text
✓ dispatcher core
✓ codex worker
✓ shared config loader
✓ config.local override
✓ env_check
✓ menu loop
✓ logging
✓ target repo override
✓ dispatcher-owned git commit
✓ optional auto push
✓ safety guards
✓ GitHub backup
```

Result:

```text
Dispatcher → Codex → Git
working end-to-end
```

---

### Phase 2A — Operator CLI

Status:

```text
COMPLETED
```

Delivered:

```text
✓ CLI Prompt Mode
✓ Repo Alias Mode
✓ Better Ask UX
✓ Commit Message UX
✓ README Usage Snapshot
```

Supported commands:

```powershell
.\dispatcher\ask "task"

.\dispatcher\ask self "task"

.\dispatcher\ask <repo-path> "task"

.\dispatcher\ask -repo self "task"

.\dispatcher\ask self "task" -m "commit message"
```

Result:

```text
User no longer edits codex-task.txt manually.
Dispatcher owns execution workflow.
```

---

### Phase 2B

Status:

```text
DEFERRED
```

Candidate:

```text
repo alias config file
```

Reason:

```text
Current bottleneck shifted from CLI ergonomics
to bridge + feedback architecture.
```

---

### Phase 3 — Feedback + Bridge Foundation

Status:

```text
IN PROGRESS
```

Official order:

```text
3.0 Run Result Contract COMPLETE
3.1 Local Bridge Foundation NEXT
3.2 Dispatch API
3.3 Result API
3.4 Token Safety
```

Phase 3.0 completion:

```text
Commit: b12b993 feat: add dispatcher run result contract
```

Delivered:

```text
dispatcher/runs/<task-id>/task.json
dispatcher/runs/<task-id>/result.json
dispatcher/runs/<task-id>/summary.md
dispatcher/runs/<task-id>/codex-output.log
dispatcher/runs/<task-id>/codex-error.log
dispatcher/runs/<task-id>/git-diff.patch
```

Validation:

```text
PowerShell parser check PASS
env_check PASS
safe self test PASS
run artifacts confirmed
git diff --check PASS
working tree clean
```

Current status:

```text
Ready for Phase 3.1 Local HTTP Bridge
```

---

## Current Technical Direction

Reference:

```text
docs/TECHNICAL_DESIGN_CHATGPT_DISPATCHER_BRIDGE.md
```

Official architecture:

```text
ChatGPT
↓
Bridge Channel
↓
Dispatcher
↓
Worker Adapter
↓
Codex
↓
Git
↓
Result Feedback
↓
ChatGPT Review
```

---

## Phase 3.0 — Run Result Contract

Status:

```text
COMPLETE
```

Commit:

```text
b12b993 feat: add dispatcher run result contract
```

Deliverables:

```text
dispatcher/runs/<task-id>/
├─ task.json
├─ result.json
├─ summary.md
├─ codex-output.log
├─ codex-error.log
└─ git-diff.patch
```

Requirements:

```text
✓ worker result normalization
✓ lifecycle fields
✓ dispatcher artifact generation
✓ clean feedback artifacts
```

Validation:

```text
✓ PowerShell parser check PASS
✓ env_check PASS
✓ safe self test PASS
✓ run artifacts confirmed
✓ git diff --check PASS
✓ working tree clean
```

Explicitly blocked:

```text
✗ HTTP bridge
✗ API
✗ MCP
✗ tunnel
✗ GitHub bridge
✗ bot bridge
✗ distributed execution
✗ VM dispatch
```

---

## Current Working Flow

Today:

```text
User
↓
ChatGPT Brain
↓
dispatcher command
↓
Dispatcher
↓
Codex
↓
Dispatcher commit
↓
optional push
↓
User pastes result back
↓
ChatGPT review
```

Target future state:

```text
User
↓
ChatGPT
↓
Bridge Channel
↓
Dispatcher
↓
Codex
↓
Dispatcher Result Contract
↓
ChatGPT Review
```

---

## Immediate Next Action

Recommended next Codex task:

```text
Implement Phase 3.1 Local HTTP Bridge.

Phase 3.0 Run Result Contract is complete.

Current status: Ready for Phase 3.1 Local HTTP Bridge.
```
