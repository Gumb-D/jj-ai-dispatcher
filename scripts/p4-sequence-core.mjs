const TERMINAL_SEQUENCE_STATUSES = new Set(["completed", "failed", "cancelled"]);
const TERMINAL_TASK_STATUSES = new Set(["completed", "failed", "skipped"]);
const ACTIVE_TASK_STATUSES = new Set(["running"]);

const LEGAL_SEQUENCE_TRANSITIONS = new Map([
  ["created", new Set(["active", "paused", "cancelled"])],
  ["active", new Set(["paused", "completed", "failed", "cancelled"])],
  ["paused", new Set(["active", "cancelled"])],
  ["completed", new Set()],
  ["failed", new Set()],
  ["cancelled", new Set()]
]);

const LEGAL_TASK_TRANSITIONS = new Map([
  ["pending", new Set(["running", "skipped"])],
  ["running", new Set(["completed", "failed"])],
  ["completed", new Set()],
  ["failed", new Set()],
  ["skipped", new Set()]
]);

function sequenceCoreError(code, message) {
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

function getAuditEvents(state) {
  return Array.isArray(state.auditEvents) ? state.auditEvents : [];
}

function appendAuditEvent(state, eventType, subject, payload, options = {}) {
  const auditEvents = getAuditEvents(state);
  const ordinal = auditEvents.length + 1;
  const event = {
    eventId: `evt-${String(ordinal).padStart(6, "0")}`,
    eventType,
    occurredAt: options.occurredAt ?? nowIso(options),
    subject: cloneJson(subject),
    payload: cloneJson(payload),
    ordinal
  };

  state.auditEvents = [...auditEvents, event];
  return event;
}

function findTask(sequence, taskId) {
  return sequence.tasks.find((task) => task.taskId === taskId) ?? null;
}

function findActiveTaskId(state) {
  for (const [taskId, taskState] of Object.entries(state.taskStates)) {
    if (ACTIVE_TASK_STATUSES.has(taskState.status)) {
      return taskId;
    }
  }
  return null;
}

function dependenciesCompleted(task, state) {
  return task.dependsOn.every((dependency) => state.taskStates[dependency]?.status === "completed");
}

function recomputeSequenceStatus(sequence, state, changedTaskStatus) {
  if (changedTaskStatus === "failed") {
    state.status = "failed";
    return;
  }

  const allDone = sequence.tasks.every((task) => {
    const status = state.taskStates[task.taskId]?.status;
    return status === "completed" || status === "skipped";
  });

  if (allDone) {
    state.status = "completed";
  }
}

function assertCanSelectTask(state) {
  if (TERMINAL_SEQUENCE_STATUSES.has(state.status)) {
    throw sequenceCoreError("P4_SEQUENCE_TERMINAL", `sequence is ${state.status}`);
  }
  if (state.status === "paused") {
    throw sequenceCoreError("P4_SEQUENCE_PAUSED", "sequence is paused");
  }

  const activeTaskId = findActiveTaskId(state);
  if (activeTaskId) {
    throw sequenceCoreError("P4_TASK_ACTIVE", `task ${activeTaskId} is already active`);
  }
}

export function initializeSequenceState(sequence, options = {}) {
  const initializedAt = nowIso(options);
  const state = {
    schemaVersion: "p4.sequence-state.v1",
    sequenceId: sequence.sequenceId,
    status: "created",
    taskStates: {},
    auditEvents: [],
    updatedAt: initializedAt
  };

  for (const task of sequence.tasks) {
    state.taskStates[task.taskId] = {
      status: "pending"
    };
  }

  appendAuditEvent(
    state,
    "sequence.initialized",
    { kind: "sequence", id: sequence.sequenceId },
    { sequenceId: sequence.sequenceId },
    { ...options, occurredAt: initializedAt }
  );

  return state;
}

export function selectNextPendingTask(sequence, state, options = {}) {
  const nextState = cloneJson(state);
  assertCanSelectTask(nextState);

  const task = sequence.tasks.find((candidate) => {
    const taskState = nextState.taskStates[candidate.taskId];
    return taskState?.status === "pending" && dependenciesCompleted(candidate, nextState);
  });

  if (!task) {
    throw sequenceCoreError("P4_NO_PENDING_TASK", "no pending task is eligible");
  }

  if (nextState.status === "created") {
    const previous = nextState.status;
    const activatedAt = nowIso(options);
    nextState.status = "active";
    appendAuditEvent(
      nextState,
      "sequence.transition",
      { kind: "sequence", id: sequence.sequenceId },
      { from: previous, to: nextState.status },
      { ...options, occurredAt: activatedAt }
    );
  }

  const selectedAt = nowIso(options);
  nextState.taskStates[task.taskId].status = "running";
  nextState.updatedAt = selectedAt;
  appendAuditEvent(
    nextState,
    "task.selected",
    { kind: "task", id: task.taskId },
    { taskId: task.taskId, from: "pending", to: "running" },
    { ...options, occurredAt: selectedAt }
  );

  return {
    state: nextState,
    task: cloneJson(task)
  };
}

export function transitionSequenceState(sequence, state, nextStatus, options = {}) {
  const nextState = cloneJson(state);
  const allowed = LEGAL_SEQUENCE_TRANSITIONS.get(nextState.status) ?? new Set();
  if (!allowed.has(nextStatus)) {
    throw sequenceCoreError(
      "P4_ILLEGAL_SEQUENCE_TRANSITION",
      `cannot transition sequence from ${nextState.status} to ${nextStatus}`
    );
  }

  const previous = nextState.status;
  const transitionedAt = nowIso(options);
  nextState.status = nextStatus;
  nextState.updatedAt = transitionedAt;
  appendAuditEvent(
    nextState,
    "sequence.transition",
    { kind: "sequence", id: sequence.sequenceId },
    { from: previous, to: nextStatus },
    { ...options, occurredAt: transitionedAt }
  );

  return nextState;
}

export function transitionTaskState(sequence, state, taskId, nextStatus, options = {}) {
  const task = findTask(sequence, taskId);
  if (!task) {
    throw sequenceCoreError("P4_UNKNOWN_TASK", `unknown task ${taskId}`);
  }

  const nextState = cloneJson(state);
  if (TERMINAL_SEQUENCE_STATUSES.has(nextState.status)) {
    throw sequenceCoreError("P4_SEQUENCE_TERMINAL", `sequence is ${nextState.status}`);
  }

  const taskState = nextState.taskStates[taskId];
  if (!taskState) {
    throw sequenceCoreError("P4_TASK_STATE_MISSING", `missing task state for ${taskId}`);
  }

  const allowed = LEGAL_TASK_TRANSITIONS.get(taskState.status) ?? new Set();
  if (!allowed.has(nextStatus)) {
    throw sequenceCoreError(
      "P4_ILLEGAL_TASK_TRANSITION",
      `cannot transition task ${taskId} from ${taskState.status} to ${nextStatus}`
    );
  }

  const previous = taskState.status;
  const transitionedAt = nowIso(options);
  taskState.status = nextStatus;
  if (options.resultRef) {
    taskState.resultRef = options.resultRef;
  }
  recomputeSequenceStatus(sequence, nextState, nextStatus);

  nextState.updatedAt = transitionedAt;
  appendAuditEvent(
    nextState,
    "task.transition",
    { kind: "task", id: taskId },
    {
      taskId,
      from: previous,
      to: nextStatus,
      ...(options.resultRef ? { resultRef: options.resultRef } : {})
    },
    { ...options, occurredAt: transitionedAt }
  );

  return nextState;
}

export const sequenceStateCore = Object.freeze({
  activeTaskStatuses: ACTIVE_TASK_STATUSES,
  legalSequenceTransitions: LEGAL_SEQUENCE_TRANSITIONS,
  legalTaskTransitions: LEGAL_TASK_TRANSITIONS,
  terminalSequenceStatuses: TERMINAL_SEQUENCE_STATUSES,
  terminalTaskStatuses: TERMINAL_TASK_STATUSES
});
