#!/usr/bin/env node
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  openSequenceController,
  selectNextEligibleTask,
  transitionSequence,
  transitionTask
} from "./p4-sequence-controller.mjs";
import { canonicalJson, readCheckpointFile } from "./p4-data-contracts.mjs";

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function assertRejected(label, code, fn) {
  try {
    await fn();
  } catch (error) {
    if (code && error?.code !== code) {
      throw new Error(`${label} rejected with ${error?.code || "unknown"} instead of ${code}`);
    }
    return error;
  }
  throw new Error(`${label} was not rejected`);
}

function sequence(overrides = {}) {
  return {
    schemaVersion: "p4.sequence.v1",
    sequenceId: overrides.sequenceId ?? "seq-controller-test",
    title: "P4 sequence controller test",
    metadata: { approved: true, ...(overrides.metadata ?? {}) },
    tasks: overrides.tasks ?? [
      {
        taskId: "task-a",
        title: "First task",
        payload: { prompt: "first" }
      },
      {
        taskId: "task-b",
        title: "Second task",
        payload: { prompt: "second" },
        dependsOn: ["task-a"]
      }
    ]
  };
}

function clock() {
  let tick = 0;
  return () => `2026-06-08T00:00:${String(tick++).padStart(2, "0")}.000Z`;
}

async function withTempRoot(fn) {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "jj-p4-sequence-controller-"));
  try {
    await fn(path.join(tempRoot, "dispatcher", "sequences"));
  } finally {
    await fs.rm(tempRoot, { recursive: true, force: true });
  }
}

function auditEvents(checkpoint) {
  return checkpoint.metadata.auditEvents;
}

async function readCheckpoint(sequenceId, rootDir) {
  return (await readCheckpointFile(sequenceId, { rootDir })).checkpoint;
}

async function testSequenceInitializationAndIdempotentReopen() {
  await withTempRoot(async (rootDir) => {
    const testSequence = sequence();
    const now = clock();
    const opened = await openSequenceController(testSequence, { rootDir, now });

    assert(opened.created === true, "first open did not create checkpoint");
    assert(opened.checkpoint.status === "created", "initial checkpoint status changed");
    assert(opened.checkpoint.taskStates["task-a"].status === "ready", "root task was not ready");
    assert(opened.checkpoint.taskStates["task-b"].status === "pending", "dependent task was not pending");
    assert(auditEvents(opened.checkpoint).length === 1, "initial audit event count changed");
    assert(auditEvents(opened.checkpoint)[0].eventType === "sequence.initialized", "initial audit event type changed");

    const reopened = await openSequenceController(testSequence, { rootDir, now });
    assert(reopened.created === false, "second open recreated checkpoint");
    assert(auditEvents(reopened.checkpoint).length === 1, "idempotent reopen appended audit events");
    assert(canonicalJson(reopened.checkpoint) === canonicalJson(opened.checkpoint), "idempotent reopen changed checkpoint data");
  });
  console.log("PASS sequence initialization and idempotent checkpoint reopen");
}

async function testSelectsOnlyOneTaskAndRefusesActiveTask() {
  await withTempRoot(async (rootDir) => {
    const testSequence = sequence({
      sequenceId: "seq-single-select",
      tasks: [
        { taskId: "task-a", title: "First task", payload: { prompt: "first" } },
        { taskId: "task-b", title: "Second task", payload: { prompt: "second" } }
      ]
    });
    const selected = await selectNextEligibleTask(testSequence, { rootDir, now: clock() });

    assert(selected.task.taskId === "task-a", "first eligible task was not selected deterministically");
    const running = Object.values(selected.checkpoint.taskStates).filter((state) => state.status === "running");
    assert(running.length === 1, "selection marked more than one task running");
    assert(selected.checkpoint.taskStates["task-b"].status === "ready", "unselected ready task state changed unexpectedly");

    await assertRejected("selection with active task", "P4_TASK_ACTIVE", () => selectNextEligibleTask(testSequence, { rootDir, now: clock() }));
  });
  console.log("PASS exactly one next task selection and active-task refusal");
}

async function testLegalAndIllegalTaskTransitions() {
  await withTempRoot(async (rootDir) => {
    const testSequence = sequence({ sequenceId: "seq-task-transitions" });
    await selectNextEligibleTask(testSequence, { rootDir, now: clock() });

    const beforeIllegal = await readCheckpoint(testSequence.sequenceId, rootDir);
    await assertRejected(
      "illegal running to ready transition",
      "P4_ILLEGAL_TASK_TRANSITION",
      () => transitionTask(testSequence, "task-a", "ready", { rootDir, now: clock() })
    );
    const afterIllegal = await readCheckpoint(testSequence.sequenceId, rootDir);
    assert(canonicalJson(afterIllegal) === canonicalJson(beforeIllegal), "illegal transition mutated checkpoint");

    const afterComplete = await transitionTask(testSequence, "task-a", "completed", {
      rootDir,
      now: clock(),
      resultRef: "dispatcher/runs/task-a/result.json"
    });
    assert(afterComplete.taskStates["task-a"].status === "completed", "running task did not complete");
    assert(afterComplete.taskStates["task-a"].resultRef === "dispatcher/runs/task-a/result.json", "resultRef was not recorded");
    assert(afterComplete.taskStates["task-b"].status === "ready", "dependency completion did not promote next task");

    await assertRejected(
      "completed task reopen",
      "P4_ILLEGAL_TASK_TRANSITION",
      () => transitionTask(testSequence, "task-a", "running", { rootDir, now: clock() })
    );
  });
  console.log("PASS legal task transitions, dependency promotion, and illegal transition safety");
}

async function testCompletedFailedAndPausedBehavior() {
  await withTempRoot(async (rootDir) => {
    const completeSequence = sequence({ sequenceId: "seq-complete-terminal" });
    await selectNextEligibleTask(completeSequence, { rootDir, now: clock() });
    await transitionTask(completeSequence, "task-a", "completed", { rootDir, now: clock() });
    await selectNextEligibleTask(completeSequence, { rootDir, now: clock() });
    const completed = await transitionTask(completeSequence, "task-b", "completed", { rootDir, now: clock() });
    assert(completed.status === "completed", "sequence did not become completed after all tasks completed");
    await assertRejected("selection after completed sequence", "P4_SEQUENCE_TERMINAL", () => selectNextEligibleTask(completeSequence, { rootDir, now: clock() }));

    const failedSequence = sequence({ sequenceId: "seq-failed-terminal" });
    await selectNextEligibleTask(failedSequence, { rootDir, now: clock() });
    const failed = await transitionTask(failedSequence, "task-a", "failed", { rootDir, now: clock() });
    assert(failed.status === "failed", "task failure did not fail sequence");
    await assertRejected("selection after failed sequence", "P4_SEQUENCE_TERMINAL", () => selectNextEligibleTask(failedSequence, { rootDir, now: clock() }));

    const pausedSequence = sequence({ sequenceId: "seq-paused-terminal" });
    const paused = await transitionSequence(pausedSequence, "paused", { rootDir, now: clock() });
    assert(paused.status === "paused", "sequence did not pause");
    await assertRejected("selection while paused", "P4_SEQUENCE_PAUSED", () => selectNextEligibleTask(pausedSequence, { rootDir, now: clock() }));
  });
  console.log("PASS completed, failed, and paused selection behavior");
}

async function testSequenceTransitionLegality() {
  await withTempRoot(async (rootDir) => {
    const testSequence = sequence({ sequenceId: "seq-sequence-transitions" });
    const paused = await transitionSequence(testSequence, "paused", { rootDir, now: clock() });
    assert(paused.status === "paused", "created to paused transition failed");

    const active = await transitionSequence(testSequence, "active", { rootDir, now: clock() });
    assert(active.status === "active", "paused to active transition failed");

    await assertRejected(
      "illegal active to created transition",
      "P4_ILLEGAL_SEQUENCE_TRANSITION",
      () => transitionSequence(testSequence, "created", { rootDir, now: clock() })
    );
  });
  console.log("PASS legal and illegal sequence state transitions");
}

async function testAuditOrdering() {
  await withTempRoot(async (rootDir) => {
    const testSequence = sequence({ sequenceId: "seq-audit-order" });
    const now = clock();
    await selectNextEligibleTask(testSequence, { rootDir, now });
    await transitionTask(testSequence, "task-a", "completed", { rootDir, now });
    await selectNextEligibleTask(testSequence, { rootDir, now });

    const checkpoint = await readCheckpoint(testSequence.sequenceId, rootDir);
    const events = auditEvents(checkpoint);
    assert(events.map((event) => event.eventId).join(",") === "evt-000001,evt-000002,evt-000003,evt-000004,evt-000005", "audit event ids are not deterministic");
    assert(events.every((event, index) => event.metadata.ordinal === index + 1), "audit ordinals are not ordered");
    assert(events.map((event) => event.eventType).join(",") === "sequence.initialized,sequence.transition,task.selected,task.transition,task.selected", "audit event ordering changed");
  });
  console.log("PASS deterministic audit ordering");
}

async function testApprovedSequenceValidation() {
  await withTempRoot(async (rootDir) => {
    await assertRejected(
      "unapproved sequence",
      "P4_SEQUENCE_NOT_APPROVED",
      () => openSequenceController(sequence({ sequenceId: "seq-unapproved", metadata: { approved: false } }), { rootDir, now: clock() })
    );
    await assertRejected(
      "unknown dependency",
      "P4_UNKNOWN_DEPENDENCY",
      () => openSequenceController(sequence({
        sequenceId: "seq-unknown-dependency",
        tasks: [{ taskId: "task-a", title: "First task", payload: {}, dependsOn: ["missing-task"] }]
      }), { rootDir, now: clock() })
    );
  });
  console.log("PASS approved sequence and graph validation");
}

async function main() {
  await testSequenceInitializationAndIdempotentReopen();
  await testSelectsOnlyOneTaskAndRefusesActiveTask();
  await testLegalAndIllegalTaskTransitions();
  await testCompletedFailedAndPausedBehavior();
  await testSequenceTransitionLegality();
  await testAuditOrdering();
  await testApprovedSequenceValidation();
}

await main().catch((error) => {
  console.error(`FAIL P4 sequence controller validation - ${error?.message || "unknown error"}`);
  process.exitCode = 1;
});
