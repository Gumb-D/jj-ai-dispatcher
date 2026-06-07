#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { z } from "zod";

const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const CHECKSUM_PREFIX = "sha256:";
const DEFAULT_SEQUENCE_ROOT = path.resolve("dispatcher", "sequences");

export const sequenceIdentifierSchema = z.string().trim()
  .min(1)
  .max(64)
  .regex(IDENTIFIER_PATTERN)
  .refine((value) => value !== "." && value !== ".." && !value.includes(".."), {
    message: "sequence identifiers must not contain path traversal segments"
  });

export const taskItemSchema = z.object({
  taskId: sequenceIdentifierSchema,
  title: z.string().trim().min(1),
  payload: z.unknown(),
  dependsOn: z.array(sequenceIdentifierSchema).default([]),
  metadata: z.record(z.string(), z.unknown()).default({})
}).strict();

export const sequenceDefinitionSchema = z.object({
  schemaVersion: z.literal("p4.sequence.v1"),
  sequenceId: sequenceIdentifierSchema,
  title: z.string().trim().min(1),
  tasks: z.array(taskItemSchema).min(1),
  metadata: z.record(z.string(), z.unknown()).default({})
}).strict();

export const checkpointSchema = z.object({
  schemaVersion: z.literal("p4.checkpoint.v1"),
  sequenceId: sequenceIdentifierSchema,
  checkpointId: sequenceIdentifierSchema,
  sequenceHash: z.string().regex(HASH_PATTERN),
  payloadHash: z.string().regex(HASH_PATTERN),
  status: z.enum(["created", "active", "paused", "completed", "failed", "cancelled"]),
  taskStates: z.record(sequenceIdentifierSchema, z.object({
    status: z.enum(["pending", "ready", "running", "completed", "failed", "skipped"]),
    taskHash: z.string().regex(HASH_PATTERN),
    payloadHash: z.string().regex(HASH_PATTERN).optional(),
    resultRef: z.string().trim().min(1).optional()
  }).strict()).default({}),
  updatedAt: z.string().datetime({ offset: true }),
  metadata: z.record(z.string(), z.unknown()).default({})
}).strict();

export const auditEventSchema = z.object({
  schemaVersion: z.literal("p4.audit.v1"),
  sequenceId: sequenceIdentifierSchema,
  eventId: sequenceIdentifierSchema,
  eventType: z.string().trim().min(1),
  occurredAt: z.string().datetime({ offset: true }),
  subject: z.object({
    kind: z.enum(["sequence", "task", "checkpoint"]),
    id: sequenceIdentifierSchema
  }).strict(),
  payloadHash: z.string().regex(HASH_PATTERN),
  payload: z.unknown(),
  metadata: z.record(z.string(), z.unknown()).default({})
}).strict();

function normalizeForCanonicalJson(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") {
    return value;
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new TypeError("canonical JSON does not support non-finite numbers");
    }
    return value;
  }

  if (Array.isArray(value)) {
    return value.map((item) => normalizeForCanonicalJson(item));
  }

  if (typeof value === "object") {
    const sorted = {};
    for (const key of Object.keys(value).sort()) {
      const item = value[key];
      if (item === undefined || typeof item === "function" || typeof item === "symbol") {
        throw new TypeError(`canonical JSON does not support ${typeof item} values`);
      }
      sorted[key] = normalizeForCanonicalJson(item);
    }
    return sorted;
  }

  throw new TypeError(`canonical JSON does not support ${typeof value} values`);
}

export function canonicalJson(value) {
  return JSON.stringify(normalizeForCanonicalJson(value));
}

export function sha256Hex(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

export function stablePayloadHash(payload) {
  return sha256Hex(canonicalJson(payload));
}

export function stableTaskHash(taskItem) {
  return stablePayloadHash(taskItemSchema.parse(taskItem));
}

export function stableSequenceHash(sequenceDefinition) {
  return stablePayloadHash(sequenceDefinitionSchema.parse(sequenceDefinition));
}

export function makeIdempotencyKey({ sequenceId, taskId, payloadHash }) {
  const safeSequenceId = sequenceIdentifierSchema.parse(sequenceId);
  const safeTaskId = sequenceIdentifierSchema.parse(taskId);
  const safePayloadHash = z.string().regex(HASH_PATTERN).parse(payloadHash);
  return `p4:${safeSequenceId}:${safeTaskId}:${safePayloadHash}`;
}

function resolveCheckpointPaths(sequenceId, rootDir = DEFAULT_SEQUENCE_ROOT) {
  const safeSequenceId = sequenceIdentifierSchema.parse(sequenceId);
  const root = path.resolve(rootDir);
  const sequenceDir = path.resolve(root, safeSequenceId);
  const relative = path.relative(root, sequenceDir);

  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error("checkpoint path escapes dispatcher/sequences");
  }

  return {
    root,
    sequenceDir,
    checkpointPath: path.join(sequenceDir, "checkpoint.json"),
    checksumPath: path.join(sequenceDir, "checkpoint.json.sha256")
  };
}

async function atomicWriteFile(targetPath, contents) {
  const tempPath = `${targetPath}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tempPath, contents, "utf8");
  await fs.rename(tempPath, targetPath);
}

export async function writeCheckpointFile(checkpoint, options = {}) {
  const parsed = checkpointSchema.parse(checkpoint);
  const paths = resolveCheckpointPaths(parsed.sequenceId, options.rootDir);
  await fs.mkdir(paths.sequenceDir, { recursive: true });

  const json = `${canonicalJson(parsed)}\n`;
  const checksum = `${CHECKSUM_PREFIX}${sha256Hex(json)}`;

  await atomicWriteFile(paths.checkpointPath, json);
  await atomicWriteFile(paths.checksumPath, `${checksum}\n`);

  return {
    checkpointPath: paths.checkpointPath,
    checksumPath: paths.checksumPath,
    checksum
  };
}

export async function readCheckpointFile(sequenceId, options = {}) {
  const paths = resolveCheckpointPaths(sequenceId, options.rootDir);
  const [json, checksumFile] = await Promise.all([
    fs.readFile(paths.checkpointPath, "utf8"),
    fs.readFile(paths.checksumPath, "utf8")
  ]);

  const expected = checksumFile.trim();
  const actual = `${CHECKSUM_PREFIX}${sha256Hex(json)}`;
  if (expected !== actual) {
    throw new Error("checkpoint checksum mismatch");
  }

  const parsed = checkpointSchema.parse(JSON.parse(json));
  if (parsed.sequenceId !== sequenceId) {
    throw new Error("checkpoint sequence identifier mismatch");
  }

  return {
    checkpoint: parsed,
    checksum: actual,
    checkpointPath: paths.checkpointPath,
    checksumPath: paths.checksumPath
  };
}
