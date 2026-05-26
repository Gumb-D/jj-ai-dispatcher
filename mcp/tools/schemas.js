import * as z from "zod/v4";

import { ValidationError } from "../server/errors.js";

const stringArray = z.array(z.string().min(1)).min(1);

export const emptyInputSchema = z.object({}).strict();

export const dispatchInputSchema = z.object({
  repo: z.string().min(1),
  worker: z.literal("codex"),
  task: z.string().trim().min(1),
  commitMessage: z.string().trim().min(1),
  scope: stringArray,
  blocked: stringArray,
  validation: stringArray,
  expectedOutput: stringArray
}).strict();

export const getRunInputSchema = z.object({
  taskId: z.string().trim().regex(/^[0-9]{8}-[0-9]{6}-[A-Za-z0-9_-]+$/)
}).strict();

export const dispatchInputShape = {
  repo: z.string().describe("Target repo accepted by the existing Dispatcher bridge, usually self."),
  worker: z.literal("codex").describe("Initial MCP skeleton supports only the codex worker."),
  task: z.string().describe("Explicit task instruction for the Dispatcher."),
  commitMessage: z.string().describe("Expected commit message for file-changing work."),
  scope: z.array(z.string()).describe("Approved file or directory scope."),
  blocked: z.array(z.string()).describe("Files, folders, or behaviors that are out of bounds."),
  validation: z.array(z.string()).describe("Validation the worker is expected to run or report."),
  expectedOutput: z.array(z.string()).describe("Concrete expected result artifacts or changes.")
};

export const getRunInputShape = {
  taskId: z.string().describe("Dispatcher task ID from a run result.")
};

export function parseInput(schema, input, label) {
  const result = schema.safeParse(input ?? {});
  if (!result.success) {
    throw new ValidationError(`invalid ${label} payload`);
  }
  return result.data;
}

export function assertSafeDispatch(input) {
  const unsafeText = [
    input.task,
    input.commitMessage,
    ...input.scope,
    ...input.blocked,
    ...input.validation,
    ...input.expectedOutput
  ].join("\n").toLowerCase();

  const blockedTerms = [
    "public tunnel",
    "reverse proxy",
    "remote endpoint",
    "auto-chain",
    "autochain",
    "execute shell",
    "run shell",
    "direct git",
    "git command"
  ];

  if (input.repo !== "self") {
    throw new ValidationError("repo must be self for the minimal MCP skeleton");
  }

  if (blockedTerms.some((term) => unsafeText.includes(term))) {
    throw new ValidationError("dispatcher_dispatch payload requests behavior outside the MCP boundary");
  }
}
