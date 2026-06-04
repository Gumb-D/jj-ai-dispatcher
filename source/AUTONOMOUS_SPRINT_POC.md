# Autonomous Sprint POC

## Purpose

Validate whether ChatGPT can coordinate continuous execution through the existing dispatcher loop: ChatGPT sends work to Dispatcher, Dispatcher assigns Codex, Codex completes the scoped task, Dispatcher posts the result back, and ChatGPT decides the next step.

This POC is documentation-only. It does not change bridge behavior, MCP tools, browser connector behavior, dispatcher runtime, launchers, autonomous execution logic, or production configuration.

## Current Architecture

- ChatGPT provides task instructions, scope, blocked areas, validation requirements, and expected output.
- Dispatcher receives the task envelope and routes work to the selected worker.
- Codex executes within the repository workspace and applies only the requested changes.
- Dispatcher captures the worker result, validation status, and final output.
- ChatGPT consumes the postback and determines whether to continue, stop, or request correction.

## Hypothesis

The existing ChatGPT to Dispatcher to Codex to Postback to ChatGPT path can support a controlled autonomous sprint loop if each task is narrowly scoped, includes explicit blocked areas, and requires verifiable completion criteria.

## POC Workflow

1. ChatGPT sends a single scoped task to Dispatcher with repository, worker, scope, blocked areas, validation, and expected output.
2. Dispatcher invokes Codex in the target repository.
3. Codex performs only the requested work and avoids blocked files or runtime behavior.
4. Codex validates the task using repository-local checks.
5. Codex commits the change with the requested commit message.
6. Dispatcher returns the result, including changed files, validation notes, commit reference, and working tree status.
7. ChatGPT reviews the postback and decides whether to issue the next scoped task.

## Continuous Execution Validation

The continuous path is measured across one uninterrupted chain: Task1 -> Postback -> Task2 -> Postback -> Task3.

Success requires all of the following:

- Each task starts only after ChatGPT receives and reviews the prior dispatcher postback.
- Each postback includes task id, worker, changed files, validation results, commit reference, working tree status, and any blocked-area observations.
- Task1, Task2, and Task3 each complete within their declared scope and create a commit with the requested message.
- Both postbacks give ChatGPT enough evidence to issue the next task without manual repository inspection.
- The final Task3 postback reports a clean working tree and no blocked-area changes across the full chain.

Failure is recorded if any of the following occur:

- A task starts before the prior postback is available to ChatGPT.
- Any task modifies bridge, MCP, browser connector, dispatcher runtime, launcher, autonomous execution, or production configuration files.
- A postback omits changed files, validation results, commit reference, or working tree status.
- Validation fails, the commit is missing, or the working tree is not clean after any task.
- ChatGPT cannot determine the next action from the postback evidence alone.

Evidence collection must retain the original task envelopes, both dispatcher postbacks, each commit hash and message, `git diff --stat` for each task, and final `git status --short` output.

## POC Result Log

### Task 1

- Status: success
- Commit: e038412
- Result: Created `source/AUTONOMOUS_SPRINT_POC.md`.

### Task 2

- Status: success
- Commit: 58c3735
- Result: Added `Continuous Execution Validation`.

### Preliminary Conclusion

Same-session postback and consecutive ChatGPT-directed dispatch have been validated. Fully unattended autonomous overnight execution remains not yet proven.

## Success Criteria

- The task completes without modifying bridge, MCP, browser connector, dispatcher runtime, launcher, autonomous execution, or production configuration.
- Only the requested documentation file changes.
- The new markdown document exists and is readable.
- A commit is created with the requested message.
- The working tree is clean after commit.
- The dispatcher result gives ChatGPT enough information to continue or stop without out-of-band inspection.

## Risks

- Scope leakage could modify runtime or production files unintentionally.
- Missing or vague validation could allow incomplete work to appear successful.
- Postback data may omit details needed for ChatGPT to choose the next action.
- Long-running tasks could exceed practical turn, worker, or context limits.
- Commit or repository state issues could block clean handoff.

## Next Tasks

- Define the minimal dispatcher postback fields required for ChatGPT continuation decisions.
- Run a second documentation-only task to confirm repeatability.
- Add a lightweight checklist template for future autonomous sprint tasks.
- Evaluate whether task envelopes need stricter schema validation before execution.
- Decide whether a later POC should simulate failure recovery without changing production runtime.
