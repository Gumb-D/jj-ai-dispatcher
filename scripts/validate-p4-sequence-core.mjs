#!/usr/bin/env node
import assert from "node:assert/strict";

import {
  initializeSequenceState,
  selectNextPendingTask,
  transitionSequenceState,
  transitionTaskState
} from "./p4-sequence-core.mjs";

function sequence(overrides = {}) {
  return {
    schemaVersion: "p4.sequence.v1",
    sequenceId: overrides.sequenceId ?? "seq-core-test",
    title: "P4 sequence core test",
    metadata: { approved: true },
    tasks: overrides.tasks ?? [
      {
        taskId: "task-a",
        title: "First task",
        dependsOn: [],
        payload: { prompt: "first" },
        metadata: {}
      },
      {
        taskId: "task-b",
        title: "Second task",
        dependsOn: ["task-a"],
        payload: { prompt: "second" },
        metadata: {}
      }
    ]
  };
}

function clock() {
  let tick = 0;
  return () => `2026-06-08T00:00:${String(tick++).padStart(2, "0")}.000Z`;
}

function assertRejected(label, code, fn) {
  try {
    fn();
  } catch (error) {
    assert.equal(error?.code, code, `${label} rejected with ${error?.code ?? "unknown"} instead of ${code}`);
    return error;
  }
  throw new Error(`${label} was not rejected`);
}

function eventTypes(state) {
  return state.auditEvents.map((event) => event.eventType);
}

function testInitialization() {
  const testSequence = sequence();
  const state = initializeSequenceState(testSequence, { now: clock() });

  assert.equal(state.schemaVersion, "p4.sequence-state.v1");
  assert.equal(state.sequenceId, testSequence.sequenceId);
  assert.equal(state.status, "created");
  assert.deepEqual(Object.keys(state.taskStates), ["task-a", "task-b"]);
  assert.equal(state.taskStates["task-a"].status, "pending");
  assert.equal(state.taskStates["task-b"].status, "pending");
  assert.deepEqual(eventTypes(state), ["sequence.initialized"]);
  assert.equal(state.auditEvents[0].eventId, "evt-000001");
  assert.equal(state.auditEvents[0].ordinal, 1);
  console.log("PASS initialization");
}

function testSingleTaskSelection() {
  const testSequence = sequence({
    sequenceId: "seq-single-selection",
    tasks: [
      { taskId: "task-a", title: "First task", dependsOn: [], payload: {}, metadata: {} },
      { taskId: "task-b", title: "Second task", dependsOn: [], payload: {}, metadata: {} }
    ]
  });
  const initialState = initializeSequenceState(testSequence, { now: clock() });
  const selected = selectNextPendingTask(testSequence, initialState, { now: clock() });

  assert.equal(selected.task.taskId, "task-a");
  assert.equal(selected.state.status, "active");
  assert.equal(selected.state.taskStates["task-a"].status, "running");
  assert.equal(selected.state.taskStates["task-b"].status, "pending");
  assert.equal(Object.values(selected.state.taskStates).filter((taskState) => taskState.status === "running").length, 1);
  assert.equal(initialState.status, "created", "selection mutated the input state");
  assert.equal(initialState.taskStates["task-a"].status, "pending", "selection mutated the input task state");
  console.log("PASS single-task selection");
}

function testActiveTaskRejection() {
  const testSequence = sequence({ sequenceId: "seq-active-rejection" });
  const initialState = initializeSequenceState(testSequence, { now: clock() });
  const selected = selectNextPendingTask(testSequence, initialState, { now: clock() });

  assertRejected("select while task is active", "P4_TASK_ACTIVE", () => {
    selectNextPendingTask(testSequence, selected.state, { now: clock() });
  });
  console.log("PASS active-task rejection");
}

function testLegalAndIllegalTaskTransitions() {
  const testSequence = sequence({ sequenceId: "seq-task-transitions" });
  const initialState = initializeSequenceState(testSequence, { now: clock() });
  const selected = selectNextPendingTask(testSequence, initialState, { now: clock() });

  assertRejected("running to pending", "P4_ILLEGAL_TASK_TRANSITION", () => {
    transitionTaskState(testSequence, selected.state, "task-a", "pending", { now: clock() });
  });

  const completed = transitionTaskState(testSequence, selected.state, "task-a", "completed", {
    now: clock(),
    resultRef: "dispatcher/runs/task-a/result.json"
  });
  assert.equal(completed.taskStates["task-a"].status, "completed");
  assert.equal(completed.taskStates["task-a"].resultRef, "dispatcher/runs/task-a/result.json");
  assert.equal(selected.state.taskStates["task-a"].status, "running", "task transition mutated the input state");

  const secondSelected = selectNextPendingTask(testSequence, completed, { now: clock() });
  assert.equal(secondSelected.task.taskId, "task-b");

  assertRejected("unknown task", "P4_UNKNOWN_TASK", () => {
    transitionTaskState(testSequence, completed, "missing-task", "completed", { now: clock() });
  });
  console.log("PASS legal and illegal task transitions");
}

function testLegalAndIllegalSequenceTransitions() {
  const testSequence = sequence({ sequenceId: "seq-sequence-transitions" });
  const initialState = initializeSequenceState(testSequence, { now: clock() });
  const paused = transitionSequenceState(testSequence, initialState, "paused", { now: clock() });
  const active = transitionSequenceState(testSequence, paused, "active", { now: clock() });

  assert.equal(paused.status, "paused");
  assert.equal(active.status, "active");
  assertRejected("active to created", "P4_ILLEGAL_SEQUENCE_TRANSITION", () => {
    transitionSequenceState(testSequence, active, "created", { now: clock() });
  });
  console.log("PASS legal and illegal sequence transitions");
}

function testCompletedFailedAndPausedBehavior() {
  const completeSequence = sequence({ sequenceId: "seq-completed" });
  const completeInitial = initializeSequenceState(completeSequence, { now: clock() });
  const firstSelected = selectNextPendingTask(completeSequence, completeInitial, { now: clock() });
  const firstCompleted = transitionTaskState(completeSequence, firstSelected.state, "task-a", "completed", { now: clock() });
  const secondSelected = selectNextPendingTask(completeSequence, firstCompleted, { now: clock() });
  const allCompleted = transitionTaskState(completeSequence, secondSelected.state, "task-b", "completed", { now: clock() });

  assert.equal(allCompleted.status, "completed");
  assertRejected("select completed sequence", "P4_SEQUENCE_TERMINAL", () => {
    selectNextPendingTask(completeSequence, allCompleted, { now: clock() });
  });

  const failedSequence = sequence({ sequenceId: "seq-failed" });
  const failedInitial = initializeSequenceState(failedSequence, { now: clock() });
  const failedSelected = selectNextPendingTask(failedSequence, failedInitial, { now: clock() });
  const failed = transitionTaskState(failedSequence, failedSelected.state, "task-a", "failed", { now: clock() });
  assert.equal(failed.status, "failed");
  assertRejected("select failed sequence", "P4_SEQUENCE_TERMINAL", () => {
    selectNextPendingTask(failedSequence, failed, { now: clock() });
  });

  const pausedSequence = sequence({ sequenceId: "seq-paused" });
  const pausedInitial = initializeSequenceState(pausedSequence, { now: clock() });
  const paused = transitionSequenceState(pausedSequence, pausedInitial, "paused", { now: clock() });
  assertRejected("select paused sequence", "P4_SEQUENCE_PAUSED", () => {
    selectNextPendingTask(pausedSequence, paused, { now: clock() });
  });
  console.log("PASS completed, failed, and paused behavior");
}

function testDeterministicAuditOrdering() {
  const testSequence = sequence({ sequenceId: "seq-audit-order" });
  const now = clock();
  const initialState = initializeSequenceState(testSequence, { now });
  const firstSelected = selectNextPendingTask(testSequence, initialState, { now });
  const firstCompleted = transitionTaskState(testSequence, firstSelected.state, "task-a", "completed", { now });
  const secondSelected = selectNextPendingTask(testSequence, firstCompleted, { now });

  assert.deepEqual(
    secondSelected.state.auditEvents.map((event) => event.eventId),
    ["evt-000001", "evt-000002", "evt-000003", "evt-000004", "evt-000005"]
  );
  assert.deepEqual(
    secondSelected.state.auditEvents.map((event) => event.ordinal),
    [1, 2, 3, 4, 5]
  );
  assert.deepEqual(eventTypes(secondSelected.state), [
    "sequence.initialized",
    "sequence.transition",
    "task.selected",
    "task.transition",
    "task.selected"
  ]);
  assert.deepEqual(
    secondSelected.state.auditEvents.map((event) => event.occurredAt),
    [
      "2026-06-08T00:00:00.000Z",
      "2026-06-08T00:00:01.000Z",
      "2026-06-08T00:00:02.000Z",
      "2026-06-08T00:00:03.000Z",
      "2026-06-08T00:00:04.000Z"
    ]
  );
  console.log("PASS deterministic audit ordering");
}

function main() {
  testInitialization();
  testSingleTaskSelection();
  testActiveTaskRejection();
  testLegalAndIllegalTaskTransitions();
  testLegalAndIllegalSequenceTransitions();
  testCompletedFailedAndPausedBehavior();
  testDeterministicAuditOrdering();
}

try {
  main();
} catch (error) {
  console.error(`FAIL P4 sequence core validation - ${error?.message ?? "unknown error"}`);
  process.exitCode = 1;
}
