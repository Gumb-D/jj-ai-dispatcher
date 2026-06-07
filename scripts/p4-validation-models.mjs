const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$/;
const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/;

export const VALIDATION_OUTCOMES = Object.freeze(["PASS", "FAIL", "INCOMPLETE"]);

export const validationCheckSchema = Object.freeze({
  schemaVersion: "p4.validation.check.v1",
  required: ["checkId", "title", "required"],
  optional: ["description", "metadata"]
});

export const validationPlanSchema = Object.freeze({
  schemaVersion: "p4.validation.plan.v1",
  required: ["schemaVersion", "planId", "title", "checks"],
  optional: ["metadata"]
});

export const manualEvidenceSchema = Object.freeze({
  schemaVersion: "p4.validation.evidence.v1",
  required: ["schemaVersion", "evidenceId", "checkId", "kind", "summary"],
  optional: ["details", "capturedAt", "metadata"]
});

export const normalizedResultSchema = Object.freeze({
  schemaVersion: "p4.validation.result.v1",
  required: ["schemaVersion", "planId", "outcome", "checks"],
  optional: ["metadata"]
});

export const auditRecordSchema = Object.freeze({
  schemaVersion: "p4.validation.audit.v1",
  required: ["schemaVersion", "auditId", "planId", "outcome", "recordedAt", "result"],
  optional: ["metadata"]
});

const outcomeRank = Object.freeze({
  PASS: 0,
  INCOMPLETE: 1,
  FAIL: 2
});

function fail(message) {
  throw new TypeError(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertPlainObject(value, label) {
  if (!isPlainObject(value)) {
    fail(`${label} must be an object`);
  }
}

function assertId(value, label) {
  if (typeof value !== "string" || !ID_PATTERN.test(value)) {
    fail(`${label} must be a non-empty identifier`);
  }
}

function assertString(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) {
    fail(`${label} must be a non-empty string`);
  }
}

function assertOptionalString(value, label) {
  if (value !== undefined && typeof value !== "string") {
    fail(`${label} must be a string when supplied`);
  }
}

function assertMetadata(value, label) {
  if (value !== undefined && !isPlainObject(value)) {
    fail(`${label} must be an object when supplied`);
  }
}

function assertOutcome(value, label) {
  if (!VALIDATION_OUTCOMES.includes(value)) {
    fail(`${label} must be PASS, FAIL, or INCOMPLETE`);
  }
}

function assertIsoDate(value, label) {
  if (typeof value !== "string" || !ISO_DATE_PATTERN.test(value)) {
    fail(`${label} must be an ISO UTC timestamp`);
  }
}

function cloneJson(value) {
  if (value === undefined) {
    return undefined;
  }
  return JSON.parse(JSON.stringify(value));
}

function canonicalJson(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") {
    return JSON.stringify(value);
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      fail("canonical JSON does not support non-finite numbers");
    }
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }

  if (isPlainObject(value)) {
    return `{${Object.keys(value).sort().map((key) => {
      const item = value[key];
      if (item === undefined || typeof item === "function" || typeof item === "symbol") {
        fail(`canonical JSON does not support ${typeof item} values`);
      }
      return `${JSON.stringify(key)}:${canonicalJson(item)}`;
    }).join(",")}}`;
  }

  fail(`canonical JSON does not support ${typeof value} values`);
}

function redactString(value) {
  return value
    .replace(/\bBearer\s+[A-Za-z0-9._~+/=-]{16,}/g, "Bearer [REDACTED]")
    .replace(/\b(token|api[_-]?key|secret|password|authorization)\s*[:=]\s*["']?[^"',;\s]{8,}["']?/gi, "$1=[REDACTED]")
    .replace(/\b[A-Za-z0-9_-]{32,}\b/g, "[REDACTED]");
}

export function redactTokenLikeValues(value) {
  if (typeof value === "string") {
    return redactString(value);
  }

  if (Array.isArray(value)) {
    return value.map((item) => redactTokenLikeValues(item));
  }

  if (isPlainObject(value)) {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, redactTokenLikeValues(item)]));
  }

  return value;
}

export function validateValidationCheck(value) {
  assertPlainObject(value, "validation check");
  assertId(value.checkId, "validation check checkId");
  assertString(value.title, "validation check title");
  if (typeof value.required !== "boolean") {
    fail("validation check required must be a boolean");
  }
  assertOptionalString(value.description, "validation check description");
  assertMetadata(value.metadata, "validation check metadata");

  return {
    checkId: value.checkId,
    title: value.title.trim(),
    required: value.required,
    ...(value.description !== undefined ? { description: value.description.trim() } : {}),
    ...(value.metadata !== undefined ? { metadata: cloneJson(value.metadata) } : {})
  };
}

export function validateValidationPlan(value) {
  assertPlainObject(value, "validation plan");
  if (value.schemaVersion !== validationPlanSchema.schemaVersion) {
    fail(`validation plan schemaVersion must be ${validationPlanSchema.schemaVersion}`);
  }
  assertId(value.planId, "validation plan planId");
  assertString(value.title, "validation plan title");
  if (!Array.isArray(value.checks) || value.checks.length === 0) {
    fail("validation plan checks must be a non-empty array");
  }
  assertMetadata(value.metadata, "validation plan metadata");

  const checks = value.checks.map((check) => validateValidationCheck(check));
  const checkIds = new Set();
  for (const check of checks) {
    if (checkIds.has(check.checkId)) {
      fail(`validation plan contains duplicate checkId ${check.checkId}`);
    }
    checkIds.add(check.checkId);
  }

  return {
    schemaVersion: value.schemaVersion,
    planId: value.planId,
    title: value.title.trim(),
    checks,
    ...(value.metadata !== undefined ? { metadata: cloneJson(value.metadata) } : {})
  };
}

export function validateManualEvidence(value) {
  assertPlainObject(value, "manual evidence");
  if (value.schemaVersion !== manualEvidenceSchema.schemaVersion) {
    fail(`manual evidence schemaVersion must be ${manualEvidenceSchema.schemaVersion}`);
  }
  assertId(value.evidenceId, "manual evidence evidenceId");
  assertId(value.checkId, "manual evidence checkId");
  assertString(value.kind, "manual evidence kind");
  assertString(value.summary, "manual evidence summary");
  assertOptionalString(value.details, "manual evidence details");
  if (value.capturedAt !== undefined) {
    assertIsoDate(value.capturedAt, "manual evidence capturedAt");
  }
  assertMetadata(value.metadata, "manual evidence metadata");

  return {
    schemaVersion: value.schemaVersion,
    evidenceId: value.evidenceId,
    checkId: value.checkId,
    kind: value.kind.trim(),
    summary: value.summary.trim(),
    ...(value.details !== undefined ? { details: value.details.trim() } : {}),
    ...(value.capturedAt !== undefined ? { capturedAt: value.capturedAt } : {}),
    ...(value.metadata !== undefined ? { metadata: cloneJson(value.metadata) } : {})
  };
}

export function normalizeEvidence(evidence) {
  const parsed = validateManualEvidence(evidence);
  const redacted = redactTokenLikeValues(parsed);
  return {
    ...redacted,
    redacted: canonicalJson(parsed) !== canonicalJson(redacted)
  };
}

function validateSuppliedRecord(value) {
  assertPlainObject(value, "validation record");
  assertId(value.checkId, "validation record checkId");
  assertOutcome(value.outcome, "validation record outcome");
  if (value.evidence !== undefined && !Array.isArray(value.evidence)) {
    fail("validation record evidence must be an array when supplied");
  }
  if (value.notes !== undefined && !Array.isArray(value.notes)) {
    fail("validation record notes must be an array when supplied");
  }

  const notes = value.notes === undefined ? [] : value.notes.map((note) => {
    assertString(note, "validation record note");
    return redactTokenLikeValues(note.trim());
  });

  return {
    checkId: value.checkId,
    outcome: value.outcome,
    evidence: (value.evidence ?? []).map((item) => normalizeEvidence(item)),
    notes: [...new Set(notes)].sort()
  };
}

function mergeRecords(left, right) {
  return {
    checkId: left.checkId,
    outcome: outcomeRank[right.outcome] > outcomeRank[left.outcome] ? right.outcome : left.outcome,
    evidence: [...left.evidence, ...right.evidence].sort((a, b) => a.evidenceId.localeCompare(b.evidenceId)),
    notes: [...new Set([...left.notes, ...right.notes])].sort()
  };
}

export function normalizeValidationResult(plan, suppliedRecords = [], metadata = {}) {
  const parsedPlan = validateValidationPlan(plan);
  if (!Array.isArray(suppliedRecords)) {
    fail("supplied validation records must be an array");
  }
  assertMetadata(metadata, "normalized result metadata");

  const planCheckIds = new Set(parsedPlan.checks.map((check) => check.checkId));
  const recordsByCheckId = new Map();

  for (const suppliedRecord of suppliedRecords) {
    const record = validateSuppliedRecord(suppliedRecord);
    if (!planCheckIds.has(record.checkId)) {
      fail(`validation record checkId is not in plan: ${record.checkId}`);
    }

    const current = recordsByCheckId.get(record.checkId);
    recordsByCheckId.set(record.checkId, current ? mergeRecords(current, record) : record);
  }

  const checks = parsedPlan.checks.map((check) => {
    const record = recordsByCheckId.get(check.checkId);
    if (record === undefined) {
      return {
        checkId: check.checkId,
        title: check.title,
        required: check.required,
        outcome: "INCOMPLETE",
        evidence: [],
        notes: [check.required ? "required check missing" : "optional check missing"]
      };
    }

    return {
      checkId: check.checkId,
      title: check.title,
      required: check.required,
      outcome: record.outcome,
      evidence: record.evidence,
      notes: record.notes
    };
  });

  const requiredChecks = checks.filter((check) => check.required);
  const outcome = requiredChecks.some((check) => check.outcome === "FAIL")
    ? "FAIL"
    : requiredChecks.some((check) => check.outcome === "INCOMPLETE")
      ? "INCOMPLETE"
      : "PASS";

  return validateNormalizedResult({
    schemaVersion: normalizedResultSchema.schemaVersion,
    planId: parsedPlan.planId,
    outcome,
    checks,
    ...(Object.keys(metadata).length > 0 ? { metadata: redactTokenLikeValues(cloneJson(metadata)) } : {})
  });
}

export function deriveValidationOutcome(plan, suppliedRecords = []) {
  return normalizeValidationResult(plan, suppliedRecords).outcome;
}

export function validateNormalizedResult(value) {
  assertPlainObject(value, "normalized result");
  if (value.schemaVersion !== normalizedResultSchema.schemaVersion) {
    fail(`normalized result schemaVersion must be ${normalizedResultSchema.schemaVersion}`);
  }
  assertId(value.planId, "normalized result planId");
  assertOutcome(value.outcome, "normalized result outcome");
  if (!Array.isArray(value.checks) || value.checks.length === 0) {
    fail("normalized result checks must be a non-empty array");
  }
  assertMetadata(value.metadata, "normalized result metadata");

  const checks = value.checks.map((check) => {
    assertPlainObject(check, "normalized result check");
    assertId(check.checkId, "normalized result checkId");
    assertString(check.title, "normalized result check title");
    if (typeof check.required !== "boolean") {
      fail("normalized result check required must be a boolean");
    }
    assertOutcome(check.outcome, "normalized result check outcome");
    if (!Array.isArray(check.evidence)) {
      fail("normalized result check evidence must be an array");
    }
    if (!Array.isArray(check.notes)) {
      fail("normalized result check notes must be an array");
    }
    return cloneJson(check);
  });

  return {
    schemaVersion: value.schemaVersion,
    planId: value.planId,
    outcome: value.outcome,
    checks,
    ...(value.metadata !== undefined ? { metadata: cloneJson(value.metadata) } : {})
  };
}

export function validateAuditRecord(value) {
  assertPlainObject(value, "audit record");
  if (value.schemaVersion !== auditRecordSchema.schemaVersion) {
    fail(`audit record schemaVersion must be ${auditRecordSchema.schemaVersion}`);
  }
  assertId(value.auditId, "audit record auditId");
  assertId(value.planId, "audit record planId");
  assertOutcome(value.outcome, "audit record outcome");
  assertIsoDate(value.recordedAt, "audit record recordedAt");
  const result = validateNormalizedResult(value.result);
  if (result.planId !== value.planId) {
    fail("audit record planId must match result planId");
  }
  if (result.outcome !== value.outcome) {
    fail("audit record outcome must match result outcome");
  }
  assertMetadata(value.metadata, "audit record metadata");

  return {
    schemaVersion: value.schemaVersion,
    auditId: value.auditId,
    planId: value.planId,
    outcome: value.outcome,
    recordedAt: value.recordedAt,
    result,
    ...(value.metadata !== undefined ? { metadata: redactTokenLikeValues(cloneJson(value.metadata)) } : {})
  };
}
