const IDENTIFIER_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const HASH_PATTERN = /^[a-f0-9]{64}$/;

const RECORD_FIELDS = Object.freeze([
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

const REQUIRED_STRING_FIELDS = Object.freeze([
  "repo",
  "worker",
  "task",
  "commitMessage",
  "sequenceId",
  "idempotencyKey"
]);

const REQUIRED_STRING_ARRAY_FIELDS = Object.freeze([
  "scope",
  "blocked",
  "validation",
  "expectedOutput"
]);

function reject(message) {
  throw new TypeError(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requiredString(value, field) {
  if (typeof value !== "string" || value.trim() === "") {
    reject(`${field} must be a non-empty string`);
  }
  return value.trim();
}

function requiredStringArray(value, field) {
  if (!Array.isArray(value)) {
    reject(`${field} must be an array of non-empty strings`);
  }
  return value.map((item, index) => requiredString(item, `${field}[${index}]`));
}

function requiredIdentifier(value, field) {
  const normalized = requiredString(value, field);
  if (!IDENTIFIER_PATTERN.test(normalized) || normalized === "." || normalized === ".." || normalized.includes("..")) {
    reject(`${field} must be a safe identifier`);
  }
  return normalized;
}

function requiredHash(value, field) {
  const normalized = requiredString(value, field);
  if (!HASH_PATTERN.test(normalized)) {
    reject(`${field} must be a lowercase 64-character hex hash`);
  }
  return normalized;
}

function requiredInteger(value, field) {
  if (!Number.isInteger(value)) {
    reject(`${field} must be an integer`);
  }
  return value;
}

export function buildP4RequestRecord(task) {
  if (!isPlainObject(task)) {
    reject("task must be an object");
  }

  for (const field of RECORD_FIELDS) {
    if (field !== "pushRequested" && !Object.hasOwn(task, field)) {
      reject(`${field} is required`);
    }
  }

  for (const field of REQUIRED_STRING_FIELDS) {
    requiredString(task[field], field);
  }

  return {
    repo: requiredIdentifier(task.repo, "repo"),
    worker: requiredIdentifier(task.worker, "worker"),
    task: requiredString(task.task, "task"),
    commitMessage: requiredString(task.commitMessage, "commitMessage"),
    scope: requiredStringArray(task.scope, "scope"),
    blocked: requiredStringArray(task.blocked, "blocked"),
    validation: requiredStringArray(task.validation, "validation"),
    expectedOutput: requiredStringArray(task.expectedOutput, "expectedOutput"),
    sequenceId: requiredIdentifier(task.sequenceId, "sequenceId"),
    taskIndex: requiredInteger(task.taskIndex, "taskIndex"),
    taskIdentityHash: requiredHash(task.taskIdentityHash, "taskIdentityHash"),
    payloadHash: requiredHash(task.payloadHash, "payloadHash"),
    idempotencyKey: requiredString(task.idempotencyKey, "idempotencyKey"),
    pushRequested: false
  };
}
