#!/usr/bin/env node
import assert from "node:assert/strict";

import { buildP4RequestRecord } from "./p4-request-record.mjs";

const TASK_IDENTITY_HASH = "a".repeat(64);
const PAYLOAD_HASH = "b".repeat(64);

function approvedTask(overrides = {}) {
  return {
    repo: "self",
    worker: "codex",
    task: "Add minimal P4 request record builder",
    commitMessage: "feat: add minimal P4 request record builder",
    scope: [
      "scripts/p4-request-record.mjs",
      "scripts/validate-p4-request-record.mjs"
    ],
    blocked: [
      "No existing file changes",
      "No package.json changes",
      "No Dispatcher, MCP, or Bridge calls",
      "No task execution",
      "No chaining, scheduling, checkpoint, retry, or resume",
      "No Git, shell, process, or network APIs"
    ],
    validation: [
      "Run node --check scripts/p4-request-record.mjs",
      "Run node --check scripts/validate-p4-request-record.mjs",
      "Run node scripts/validate-p4-request-record.mjs",
      "Run git diff --check",
      "Confirm only the two approved files changed",
      "Confirm clean working tree after Dispatcher commit"
    ],
    expectedOutput: [
      "Two files changed only",
      "Focused validator passes",
      "Commit hash",
      "Push status",
      "Working tree status"
    ],
    sequenceId: "p4-request-record",
    taskIndex: 0,
    taskIdentityHash: TASK_IDENTITY_HASH,
    payloadHash: PAYLOAD_HASH,
    idempotencyKey: `p4-request-record:0:${TASK_IDENTITY_HASH}:${PAYLOAD_HASH}`,
    pushRequested: true,
    ...overrides
  };
}

function assertRejected(label, task) {
  assert.throws(
    () => buildP4RequestRecord(task),
    TypeError,
    `${label} should reject`
  );
}

function testValidRecord() {
  const record = buildP4RequestRecord(approvedTask({ pushRequested: false }));

  assert.deepEqual(Object.keys(record), [
    "repo",
    "worker",
    "task",
    "commitMessage",
    "scope",
    "blocked",
    "validation",
    "expectedOutput",
    "sequenceId",
    "taskIndex",
    "taskIdentityHash",
    "payloadHash",
    "idempotencyKey",
    "pushRequested"
  ]);
  assert.equal(record.repo, "self");
  assert.equal(record.worker, "codex");
  assert.equal(record.taskIndex, 0);
  assert.equal(record.taskIdentityHash, TASK_IDENTITY_HASH);
  assert.equal(record.payloadHash, PAYLOAD_HASH);
  assert.equal(record.pushRequested, false);
}

function testDeterministicOutput() {
  const first = JSON.stringify(buildP4RequestRecord(approvedTask()));
  const second = JSON.stringify(buildP4RequestRecord(approvedTask()));

  assert.equal(first, second);
}

function testMissingFieldRejection() {
  const task = approvedTask();
  delete task.commitMessage;

  assertRejected("missing commitMessage", task);
}

function testInvalidIdentifierAndHashRejection() {
  assertRejected("invalid repo", approvedTask({ repo: "../self" }));
  assertRejected("invalid worker", approvedTask({ worker: "Code X" }));
  assertRejected("invalid sequenceId", approvedTask({ sequenceId: "p4/record" }));
  assertRejected("uppercase hash", approvedTask({ taskIdentityHash: "A".repeat(64) }));
  assertRejected("short hash", approvedTask({ payloadHash: "b".repeat(63) }));
  assertRejected("non-integer taskIndex", approvedTask({ taskIndex: 0.5 }));
}

function testPushRequestedForcedFalse() {
  const record = buildP4RequestRecord(approvedTask({ pushRequested: true }));

  assert.equal(record.pushRequested, false);
}

testValidRecord();
testDeterministicOutput();
testMissingFieldRejection();
testInvalidIdentifierAndHashRejection();
testPushRequestedForcedFalse();

console.log("PASS p4 request record validation");
