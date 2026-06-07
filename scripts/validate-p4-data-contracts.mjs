#!/usr/bin/env node
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  auditEventSchema,
  canonicalJson,
  checkpointSchema,
  makeIdempotencyKey,
  readCheckpointFile,
  sequenceDefinitionSchema,
  stablePayloadHash,
  stableSequenceHash,
  stableTaskHash,
  taskItemSchema,
  writeCheckpointFile
} from "./p4-data-contracts.mjs";

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

async function assertRejectedAsync(label, fn) {
  let rejected = false;
  try {
    await fn();
  } catch {
    rejected = true;
  }
  assert(rejected, `${label} was not rejected`);
}

const task = {
  taskId: "task-001",
  title: "Create local contract utility",
  payload: {
    commitMessage: "feat: add P4 data contract foundation",
    scope: ["scripts", "dispatcher", "package.json"]
  }
};

const taskWithReorderedPayload = {
  title: "Create local contract utility",
  taskId: "task-001",
  payload: {
    scope: ["scripts", "dispatcher", "package.json"],
    commitMessage: "feat: add P4 data contract foundation"
  }
};

const sequence = {
  schemaVersion: "p4.sequence.v1",
  sequenceId: "seq-local-p4",
  title: "Local P4 data contract foundation",
  tasks: [task]
};

const sequenceHash = stableSequenceHash(sequence);
const taskHash = stableTaskHash(task);
const payloadHash = stablePayloadHash(task.payload);

const checkpoint = {
  schemaVersion: "p4.checkpoint.v1",
  sequenceId: "seq-local-p4",
  checkpointId: "checkpoint-001",
  sequenceHash,
  payloadHash,
  status: "active",
  taskStates: {
    "task-001": {
      status: "pending",
      taskHash,
      payloadHash
    }
  },
  updatedAt: "2026-06-07T14:30:00.000Z"
};

function testSchemaValidation() {
  assert(taskItemSchema.safeParse(task).success, "valid task item failed validation");
  assert(sequenceDefinitionSchema.safeParse(sequence).success, "valid sequence definition failed validation");
  assert(checkpointSchema.safeParse(checkpoint).success, "valid checkpoint failed validation");
  assert(auditEventSchema.safeParse({
    schemaVersion: "p4.audit.v1",
    sequenceId: "seq-local-p4",
    eventId: "event-001",
    eventType: "checkpoint.write",
    occurredAt: "2026-06-07T14:30:00.000Z",
    subject: { kind: "checkpoint", id: "checkpoint-001" },
    payloadHash,
    payload: { checkpointId: "checkpoint-001" }
  }).success, "valid audit event failed validation");

  assertRejected("invalid sequence identifier", () => sequenceDefinitionSchema.parse({
    ...sequence,
    sequenceId: "../escape"
  }));
  assertRejected("unknown task field", () => taskItemSchema.parse({ ...task, execute: "npm test" }));
  console.log("PASS P4 schema validation and invalid identifier rejection");
}

function testStableHashing() {
  assert(canonicalJson({ b: 2, a: 1 }) === "{\"a\":1,\"b\":2}", "canonical JSON did not sort keys");
  assert(stableTaskHash(task) === stableTaskHash(taskWithReorderedPayload), "task hash changed with object key order");
  assert(stablePayloadHash({ b: 2, a: [3, { d: 4, c: 5 }] }) === stablePayloadHash({ a: [3, { c: 5, d: 4 }], b: 2 }), "payload hash changed with nested key order");
  assert(makeIdempotencyKey({ sequenceId: "seq-local-p4", taskId: "task-001", payloadHash }) === `p4:seq-local-p4:task-001:${payloadHash}`, "idempotency key format changed");
  console.log("PASS deterministic canonical hashing and idempotency key construction");
}

async function testCheckpointWriteReadback() {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "jj-p4-contract-"));
  try {
    const rootDir = path.join(tempRoot, "dispatcher", "sequences");
    const written = await writeCheckpointFile(checkpoint, { rootDir });
    assert(written.checksum.startsWith("sha256:"), "checkpoint checksum missing sha256 prefix");

    const read = await readCheckpointFile("seq-local-p4", { rootDir });
    assert(read.checksum === written.checksum, "readback checksum did not match write result");
    assert(JSON.stringify(read.checkpoint) === JSON.stringify(checkpointSchema.parse(checkpoint)), "checkpoint readback changed data");

    const checksumContents = await fs.readFile(written.checksumPath, "utf8");
    assert(checksumContents.trim() === written.checksum, "sidecar checksum file did not match returned checksum");

    await fs.writeFile(written.checkpointPath, `${canonicalJson({ ...checkpoint, status: "failed" })}\n`, "utf8");
    await assertRejectedAsync("checkpoint checksum mismatch", () => readCheckpointFile("seq-local-p4", { rootDir }));

    await assertRejectedAsync("path traversal sequence id", () => readCheckpointFile("../escape", { rootDir }));
    await assertRejectedAsync("nested path sequence id", () => writeCheckpointFile({ ...checkpoint, sequenceId: "seq/escape" }, { rootDir }));
    console.log("PASS atomic checkpoint write/readback, checksum verification, mismatch rejection, and path safety");
  } finally {
    await fs.rm(tempRoot, { recursive: true, force: true });
  }
}

async function testRuntimeIsolation() {
  const filesToCheck = [
    "dispatcher/run.ps1",
    "dispatcher/bridge.ps1",
    "dispatcher/ask.ps1",
    "mcp/tools/index.js",
    "mcp/tools/schemas.js",
    "mcp/server/server.js",
    "mcp/server/index.js",
    "mcp/server/http.js",
    "mcp/server/bridgeClient.js"
  ];

  for (const file of filesToCheck) {
    const contents = await fs.readFile(file, "utf8");
    assert(!contents.includes("p4-data-contracts"), `${file} imports P4 data contracts`);
    assert(!contents.includes("writeCheckpointFile"), `${file} references checkpoint writer`);
    assert(!contents.includes("readCheckpointFile"), `${file} references checkpoint reader`);
  }
  console.log("PASS P4 utilities remain unreferenced by Dispatcher, MCP, Bridge, and task execution code");
}

async function main() {
  testSchemaValidation();
  testStableHashing();
  await testCheckpointWriteReadback();
  await testRuntimeIsolation();
}

await main().catch((error) => {
  console.error(`FAIL P4 data contract validation - ${error?.message || "unknown error"}`);
  process.exitCode = 1;
});
