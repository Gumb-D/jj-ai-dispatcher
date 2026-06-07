#!/usr/bin/env node
import {
  deriveValidationOutcome,
  normalizeEvidence,
  normalizeValidationResult,
  redactTokenLikeValues,
  validateAuditRecord,
  validateManualEvidence,
  validateNormalizedResult,
  validateValidationCheck,
  validateValidationPlan
} from "./p4-validation-models.mjs";

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertRejected(label, fn) {
  let rejected = false;
  try {
    fn();
  } catch {
    rejected = true;
  }
  assert(rejected, `${label} was not rejected`);
}

const plan = {
  schemaVersion: "p4.validation.plan.v1",
  planId: "p4-validation-local",
  title: "P4 validation data model",
  checks: [
    { checkId: "syntax", title: "Syntax checks", required: true },
    { checkId: "focused-validator", title: "Focused validator", required: true },
    { checkId: "working-tree", title: "Working tree status", required: false }
  ]
};

const manualEvidence = {
  schemaVersion: "p4.validation.evidence.v1",
  evidenceId: "evidence-001",
  checkId: "focused-validator",
  kind: "manual",
  summary: "Observed Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789",
  details: "secret=super-secret-token and api_key=abcdefghijklmnopqrstuvwxyz012345",
  capturedAt: "2026-06-08T00:00:00.000Z",
  metadata: {
    nested: "token=abcdefghijklmnopqrstuvwxyz012345"
  }
};

const passingRequiredRecords = [
  { checkId: "syntax", outcome: "PASS", notes: ["node --check passed"] },
  { checkId: "focused-validator", outcome: "PASS", evidence: [manualEvidence] }
];

function testValidAndInvalidRecords() {
  assert(validateValidationCheck(plan.checks[0]).checkId === "syntax", "valid check failed");
  assert(validateValidationPlan(plan).checks.length === 3, "valid plan failed");
  assert(validateManualEvidence(manualEvidence).evidenceId === "evidence-001", "valid evidence failed");

  assertRejected("missing required check title", () => validateValidationCheck({
    checkId: "syntax",
    required: true
  }));
  assertRejected("duplicate plan check", () => validateValidationPlan({
    ...plan,
    checks: [...plan.checks, plan.checks[0]]
  }));
  assertRejected("invalid evidence timestamp", () => validateManualEvidence({
    ...manualEvidence,
    capturedAt: "not-a-date"
  }));
  assertRejected("record outside plan", () => normalizeValidationResult(plan, [
    { checkId: "not-in-plan", outcome: "PASS" }
  ]));

  console.log("PASS valid and invalid validation records");
}

function testRequiredVersusOptionalChecks() {
  const optionalMissing = normalizeValidationResult(plan, passingRequiredRecords);
  assert(optionalMissing.outcome === "PASS", "missing optional check should not block PASS");
  assert(optionalMissing.checks.find((check) => check.checkId === "working-tree").outcome === "INCOMPLETE", "missing optional check should be marked INCOMPLETE");

  const requiredMissing = normalizeValidationResult(plan, passingRequiredRecords.filter((record) => record.checkId !== "syntax"));
  assert(requiredMissing.outcome === "INCOMPLETE", "missing required check should produce INCOMPLETE");

  const requiredFailed = normalizeValidationResult(plan, [
    ...passingRequiredRecords.filter((record) => record.checkId !== "syntax"),
    { checkId: "syntax", outcome: "FAIL", notes: ["syntax error"] }
  ]);
  assert(requiredFailed.outcome === "FAIL", "failed required check should produce FAIL");

  console.log("PASS required and optional check outcomes");
}

function testManualEvidenceAndRedaction() {
  const normalized = normalizeEvidence(manualEvidence);
  assert(normalized.redacted === true, "evidence should report redaction");
  assert(normalized.summary.includes("Bearer [REDACTED]"), "bearer token was not redacted");
  assert(normalized.details.includes("secret=[REDACTED]"), "secret was not redacted");
  assert(normalized.details.includes("api_key=[REDACTED]"), "api key was not redacted");
  assert(normalized.metadata.nested === "token=[REDACTED]", "nested token metadata was not redacted");

  const redacted = redactTokenLikeValues({
    safe: "short ordinary value",
    token: "abcdefghijklmnopqrstuvwxyz012345"
  });
  assert(redacted.safe === "short ordinary value", "ordinary text changed");
  assert(redacted.token === "[REDACTED]", "token-like value was not redacted");

  console.log("PASS manual evidence normalization and redaction");
}

function testDeterministicOutcomesAndAuditRecord() {
  const first = normalizeValidationResult(plan, [
    ...passingRequiredRecords,
    { checkId: "syntax", outcome: "INCOMPLETE", notes: ["duplicate worse status"] },
    { checkId: "working-tree", outcome: "FAIL", notes: ["optional fail"] }
  ], {
    authorization: "Bearer abcdefghijklmnopqrstuvwxyz0123456789"
  });
  const second = normalizeValidationResult(plan, [
    { checkId: "working-tree", outcome: "FAIL", notes: ["optional fail"] },
    { checkId: "focused-validator", outcome: "PASS", evidence: [manualEvidence] },
    { checkId: "syntax", outcome: "INCOMPLETE", notes: ["duplicate worse status"] },
    { checkId: "syntax", outcome: "PASS", notes: ["node --check passed"] }
  ], {
    authorization: "Bearer abcdefghijklmnopqrstuvwxyz0123456789"
  });

  assert(first.outcome === "INCOMPLETE", "duplicate required records should settle on worse status");
  assert(JSON.stringify(first) === JSON.stringify(second), "normalized result should be deterministic");
  assert(deriveValidationOutcome(plan, passingRequiredRecords) === "PASS", "derived PASS outcome changed");
  assert(validateNormalizedResult(first).schemaVersion === "p4.validation.result.v1", "normalized result validation failed");

  const audit = validateAuditRecord({
    schemaVersion: "p4.validation.audit.v1",
    auditId: "audit-001",
    planId: first.planId,
    outcome: first.outcome,
    recordedAt: "2026-06-08T00:01:00.000Z",
    result: first,
    metadata: { apiKey: "api_key=abcdefghijklmnopqrstuvwxyz012345" }
  });
  assert(audit.metadata.apiKey === "api_key=[REDACTED]", "audit metadata was not redacted");

  console.log("PASS deterministic normalized outcomes and audit record validation");
}

function main() {
  testValidAndInvalidRecords();
  testRequiredVersusOptionalChecks();
  testManualEvidenceAndRedaction();
  testDeterministicOutcomesAndAuditRecord();
}

try {
  main();
} catch (error) {
  console.error(`FAIL P4 validation model validation - ${error?.message || "unknown error"}`);
  process.exitCode = 1;
}
