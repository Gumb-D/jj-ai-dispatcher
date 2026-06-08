#!/usr/bin/env node
import fs from "node:fs/promises";

import {
  auditEventSchema,
  checkpointSchema,
  makeIdempotencyKey,
  readCheckpointFile,
  sequenceDefinitionSchema,
  stablePayloadHash,
  stableSequenceHash,
  stableTaskHash,
  writeCheckpointFile
} from "./p4-data-contracts.mjs";

const ACTIVE_TASK_STATUSES = new Set(["running"]);
const TERMINAL_SEQUENCE_STATUSES = new Set(["completed", "failed", "cancelled"]);
const TERMINAL_TASK_STATUSES = new Set(["completed", "failed", "skipped"]);

const LEGAL_SEQUENCE_TRANSITIONS = new Map([
  ["created", new Set(["active", "paused", "cancelled"])],
  ["active", new Set(["paused", "completed", "failed", "cancelled"])],
  ["paused", new Set(["active", "cancelled"])],
  ["completed", new Set()],
  ["failed", new Set()],
  ["cancelled", new Set()]
]);

const LEGAL_TASK_TRANSITIONS = new Map([
  ["pending", new Set(["ready", "running", "skipped"])],
  ["ready", new Set(["running", "skipped"])],
  ["running", new Set(["completed", "failed"])],
  ["completed", new Set()],
  ["failed", new Set()],
  ["skipped", new Set()]
]);

function controllerError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function nowIso(options) {
  return typeof options.now === "function" ? options.now() : new Date().toISOString();
}

function assertApproved(sequence) {
  if (sequence.metadata?.approved !== true) {
    throw controllerError("P4_SEQUENCE_NOT_APPROVED", "sequence metadata.approved must be true");
  }
}

function validateSequenceGraph(sequence) {
  const taskIds = new Set();
  for (const task of sequence.tasks) {
    if (taskIds.has(task.taskId)) {
      throw controllerError("P4_DUPLICATE_TASK", `duplicate taskId ${task.taskId}`);
    }
    taskIds.add(task.taskId);
  }

  for (const task of sequence.tasks) {
    for (const dependency of task.dependsOn) {
      if (dependency === task.taskId) {
        throw controllerError("P4_SELF_DEPENDENCY", `task ${task.taskId} depends on itself`);
      }
      if (!taskIds.has(dependency)) {
        throw controllerError("P4_UNKNOWN_DEPENDENCY", `task ${task.taskId} depends on unknown task ${dependency}`);
      }
    }
  }

  const visiting = new Set();
  const visited = new Set();
  const byId = new Map(sequence.tasks.map((task) => [task.taskId, task]));

  function visit(taskId) {
    if (visited.has(taskId)) {
      return;
    }
    if (visiting.has(taskId)) {
      throw controllerError("P4_CYCLIC_DEPENDENCY", `sequence ${sequence.sequenceId} has a dependency cycle`);
    }
    visiting.add(taskId);
    for (const dependency of byId.get(taskId).dependsOn) {
      visit(dependency);
    }
    visiting.delete(taskId);
    visited.add(taskId);
  }

  for (const task of sequence.tasks) {
    visit(task.taskId);
  }
}

export async function loadApprovedSequenceDefinition(source, options = {}) {
  const raw = typeof source === "string"
    ? JSON.parse(await fs.readFile(source, "utf8"))
    : source;
  const sequence = sequenceDefinitionSchema.parse(raw);
  if (options.requireApproved !== false) {
    assertApproved(sequence);
  }
  validateSequenceGraph(sequence);
  return sequence;
}

function getAuditEvents(checkpoint) {
  const auditEvents = checkpoint.metadata?.auditEvents;
  return Array.isArray(auditEvents) ? auditEvents : [];
}

function appendAuditEvent(checkpoint, eventType, subject, payload, options = {}) {
  const auditEvents = getAuditEvents(checkpoint);
  const event = auditEventSchema.parse({
    schemaVersion: "p4.audit.v1",
    sequenceId: checkpoint.sequenceId,
    eventId: `evt-${String(auditEvents.length + 1).padStart(6, "0")}`,
    eventType,
    occurredAt: nowIso(options),
    subject,
    payloadHash: stablePayloadHash(payload),
    payload,
    metadata: {
      ordinal: auditEvents.length + 1
    }
  });

  checkpoint.metadata = {
    ...checkpoint.metadata,
    auditEvents: [...auditEvents, event]
  };
  return event;
}

function taskReadyStatus(task) {
  return task.dependsOn.length === 0 ? "ready" : "pending";
}

function makeInitialCheckpoint(sequence, options = {}) {
  const taskStates = {};
  for (const task of sequence.tasks) {
    taskStates[task.taskId] = {
      status: taskReadyStatus(task),
      taskHash: stableTaskHash(task),
      payloadHash: stablePayloadHash(task.payload)
    };
  }

  const checkpoint = checkpointSchema.parse({
    schemaVersion: "p4.checkpoint.v1",
    sequenceId: sequence.sequenceId,
    checkpointId: "checkpoint",
    sequenceHash: stableSequenceHash(sequence),
    payloadHash: stablePayloadHash(sequence.tasks.map((task) => task.payload)),
    status: "created",
    taskStates,
    updatedAt: nowIso(options),
    metadata: {
      auditEvents: []
    }
  });

  appendAuditEvent(
    checkpoint,
    "sequence.initialized",
    { kind: "sequence", id: sequence.sequenceId },
    { sequenceId: sequence.sequenceId, checkpointId: checkpoint.checkpointId },
    options
  );
  return checkpoint;
}

function assertCheckpointMatchesSequence(sequence, checkpoint) {
  if (checkpoint.sequenceId !== sequence.sequenceId) {
    throw controllerError("P4_SEQUENCE_MISMATCH", "checkpoint sequenceId does not match sequence definition");
  }
  if (checkpoint.sequenceHash !== stableSequenceHash(sequence)) {
    throw controllerError("P4_SEQUENCE_HASH_MISMATCH", "checkpoint sequenceHash does not match sequence definition");
  }
  for (const task of sequence.tasks) {
    const state = checkpoint.taskStates[task.taskId];
    if (!state) {
      throw controllerError("P4_TASK_STATE_MISSING", `checkpoint missing task state for ${task.taskId}`);
    }
    if (state.taskHash !== stableTaskHash(task)) {
      throw controllerError("P4_TASK_HASH_MISMATCH", `checkpoint taskHash does not match ${task.taskId}`);
    }
  }
}

async function persistCheckpoint(checkpoint, options = {}) {
  const parsed = checkpointSchema.parse(checkpoint);
  await writeCheckpointFile(parsed, options);
  return parsed;
}

function promoteReadyTasks(sequence, checkpoint) {
  for (const task of sequence.tasks) {
    const state = checkpoint.taskStates[task.taskId];
    if (state.status !== "pending") {
      continue;
    }
    const dependenciesComplete = task.dependsOn.every((dependency) => checkpoint.taskStates[dependency]?.status === "completed");
    if (dependenciesComplete) {
      state.status = "ready";
    }
  }
}

function findActiveTask(checkpoint) {
  for (const [taskId, state] of Object.entries(checkpoint.taskStates)) {
    if (ACTIVE_TASK_STATUSES.has(state.status)) {
      return taskId;
    }
  }
  return null;
}

function makeTaskDescriptor(sequence, task, checkpoint) {
  const payloadHash = stablePayloadHash(task.payload);
  return {
    sequenceId: sequence.sequenceId,
    taskId: task.taskId,
    title: task.title,
    dependsOn: [...task.dependsOn],
    payload: cloneJson(task.payload),
    metadata: cloneJson(task.metadata),
    taskHash: stableTaskHash(task),
    payloadHash,
    idempotencyKey: makeIdempotencyKey({
      sequenceId: sequence.sequenceId,
      taskId: task.taskId,
      payloadHash
    }),
    checkpointId: checkpoint.checkpointId
  };
}

function assertSequenceCanSelect(checkpoint) {
  if (TERMINAL_SEQUENCE_STATUSES.has(checkpoint.status)) {
    throw controllerError("P4_SEQUENCE_TERMINAL", `sequence is ${checkpoint.status}`);
  }
  if (checkpoint.status === "paused") {
    throw controllerError("P4_SEQUENCE_PAUSED", "sequence is paused");
  }
  const activeTask = findActiveTask(checkpoint);
  if (activeTask) {
    throw controllerError("P4_TASK_ACTIVE", `task ${activeTask} is already active`);
  }
}

export async function openSequenceController(source, options = {}) {
  const sequence = await loadApprovedSequenceDefinition(source, options);
  let checkpoint;
  let created = false;

  try {
    checkpoint = (await readCheckpointFile(sequence.sequenceId, options)).checkpoint;
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
    checkpoint = makeInitialCheckpoint(sequence, options);
    checkpoint = await persistCheckpoint(checkpoint, options);
    created = true;
  }

  assertCheckpointMatchesSequence(sequence, checkpoint);
  return {
    sequence,
    checkpoint,
    created
  };
}

export async function selectNextEligibleTask(source, options = {}) {
  const controller = await openSequenceController(source, options);
  const { sequence } = controller;
  const checkpoint = cloneJson(controller.checkpoint);

  assertSequenceCanSelect(checkpoint);
  promoteReadyTasks(sequence, checkpoint);

  const task = sequence.tasks.find((candidate) => checkpoint.taskStates[candidate.taskId]?.status === "ready");
  if (!task) {
    if (sequence.tasks.every((candidate) => checkpoint.taskStates[candidate.taskId]?.status === "completed")) {
      return {
        checkpoint,
        task: null
      };
    }
    throw controllerError("P4_NO_ELIGIBLE_TASK", "no eligible task is ready");
  }

  if (checkpoint.status === "created") {
    checkpoint.status = "active";
    appendAuditEvent(
      checkpoint,
      "sequence.transition",
      { kind: "sequence", id: sequence.sequenceId },
      { from: "created", to: "active" },
      options
    );
  }

  checkpoint.taskStates[task.taskId].status = "running";
  checkpoint.updatedAt = nowIso(options);
  appendAuditEvent(
    checkpoint,
    "task.selected",
    { kind: "task", id: task.taskId },
    { taskId: task.taskId, from: "ready", to: "running" },
    options
  );

  const persisted = await persistCheckpoint(checkpoint, options);
  return {
    checkpoint: persisted,
    task: makeTaskDescriptor(sequence, task, persisted)
  };
}

export async function transitionSequence(source, nextStatus, options = {}) {
  const controller = await openSequenceController(source, options);
  const checkpoint = cloneJson(controller.checkpoint);
  const allowed = LEGAL_SEQUENCE_TRANSITIONS.get(checkpoint.status) ?? new Set();
  if (!allowed.has(nextStatus)) {
    throw controllerError("P4_ILLEGAL_SEQUENCE_TRANSITION", `cannot transition sequence from ${checkpoint.status} to ${nextStatus}`);
  }

  const previous = checkpoint.status;
  checkpoint.status = nextStatus;
  checkpoint.updatedAt = nowIso(options);
  appendAuditEvent(
    checkpoint,
    "sequence.transition",
    { kind: "sequence", id: checkpoint.sequenceId },
    { from: previous, to: nextStatus },
    options
  );

  return persistCheckpoint(checkpoint, options);
}

export async function transitionTask(source, taskId, nextStatus, options = {}) {
  const controller = await openSequenceController(source, options);
  const { sequence } = controller;
  const checkpoint = cloneJson(controller.checkpoint);
  const task = sequence.tasks.find((candidate) => candidate.taskId === taskId);
  if (!task) {
    throw controllerError("P4_UNKNOWN_TASK", `unknown task ${taskId}`);
  }
  if (TERMINAL_SEQUENCE_STATUSES.has(checkpoint.status)) {
    throw controllerError("P4_SEQUENCE_TERMINAL", `sequence is ${checkpoint.status}`);
  }

  const state = checkpoint.taskStates[taskId];
  const allowed = LEGAL_TASK_TRANSITIONS.get(state.status) ?? new Set();
  if (!allowed.has(nextStatus)) {
    throw controllerError("P4_ILLEGAL_TASK_TRANSITION", `cannot transition task ${taskId} from ${state.status} to ${nextStatus}`);
  }

  const previous = state.status;
  state.status = nextStatus;
  if (options.resultRef) {
    state.resultRef = options.resultRef;
  }
  promoteReadyTasks(sequence, checkpoint);

  if (nextStatus === "failed") {
    checkpoint.status = "failed";
  } else if (sequence.tasks.every((candidate) => checkpoint.taskStates[candidate.taskId]?.status === "completed")) {
    checkpoint.status = "completed";
  }

  checkpoint.updatedAt = nowIso(options);
  appendAuditEvent(
    checkpoint,
    "task.transition",
    { kind: "task", id: taskId },
    {
      taskId,
      from: previous,
      to: nextStatus,
      ...(options.resultRef ? { resultRef: options.resultRef } : {})
    },
    options
  );

  return persistCheckpoint(checkpoint, options);
}

export const sequenceControllerState = Object.freeze({
  legalSequenceTransitions: LEGAL_SEQUENCE_TRANSITIONS,
  legalTaskTransitions: LEGAL_TASK_TRANSITIONS,
  terminalSequenceStatuses: TERMINAL_SEQUENCE_STATUSES,
  terminalTaskStatuses: TERMINAL_TASK_STATUSES
});
