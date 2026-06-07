import { z } from "zod";

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

export const errorOutputSchema = z.object({
  status: z.literal("error").describe("Error status indicator."),
  errorType: z.string().describe("Type classification of this error."),
  message: z.string().describe("Detailed human-readable error description."),
  retryable: z.boolean().describe("Whether this request can be retried safely."),
  bridgeStatus: z.number().optional().describe("Optional raw HTTP response status from the bridge.")
});

export const statusOutputSchema = z.object({
  status: z.string().describe("Status indicator, usually ok or error."),
  dispatcherRoot: z.string().optional().describe("The root directory of the dispatcher."),
  defaultWorker: z.string().optional().describe("Default workspace worker."),
  autoPush: z.boolean().optional().describe("Whether git auto push is enabled."),
  bridgeEnabled: z.boolean().optional().describe("Whether the bridge server is active."),
  taskState: z.string().optional().describe("Current dispatcher task state: idle or running."),
  errorType: z.string().optional().describe("Type classification of this error."),
  message: z.string().optional().describe("Detailed human-readable error description."),
  retryable: z.boolean().optional().describe("Whether this request can be retried safely."),
  bridgeStatus: z.number().optional().describe("Optional raw HTTP response status from the bridge.")
});

export const dispatchOutputSchema = z.object({
  status: z.string().describe("Current dispatch execution status or error indicator."),
  accepted: z.boolean().optional().describe("Whether the task was accepted for dispatch."),
  worker: z.string().optional().describe("Task execution worker."),
  taskState: z.string().optional().describe("Dispatcher task state after dispatch."),
  processId: z.number().optional().describe("Local OS process ID of the dispatcher."),
  error: z.string().optional().describe("Reason why the dispatch failed."),
  errorType: z.string().optional().describe("Type classification of this error."),
  message: z.string().optional().describe("Detailed human-readable error description."),
  retryable: z.boolean().optional().describe("Whether this request can be retried safely."),
  bridgeStatus: z.number().optional().describe("Optional raw HTTP response status from the bridge.")
});

const logsSchema = z.object({
  stdout: z.string().describe("Relative path to stdout logs."),
  stderr: z.string().describe("Relative path to stderr logs."),
  diff: z.string().optional().describe("Relative path to git diff patch.")
});

const artifactsSchema = z.object({
  runDir: z.string().optional().describe("Relative run artifact directory."),
  task: z.string().optional().describe("Relative task artifact path."),
  result: z.string().optional().describe("Relative result artifact path."),
  summary: z.string().optional().describe("Relative summary artifact path."),
  stdout: z.string().optional().describe("Relative stdout log artifact path."),
  stderr: z.string().optional().describe("Relative stderr log artifact path."),
  diff: z.string().optional().describe("Relative git diff artifact path.")
}).passthrough();

export const runOutputSchema = z.object({
  status: z.string().describe("Backward-compatible run execution status. For run results this mirrors executionStatus."),
  executionStatus: z.enum(["queued", "running", "success", "failed", "cancelled"]).optional().describe("Execution outcome independent of result delivery."),
  deliveryStatus: z.enum(["not_requested", "pending", "delivered", "timeout", "failed", "skipped", "unavailable"]).optional().describe("Delivery outcome for optional result channels."),
  deliveryChannel: z.string().nullable().optional().describe("Optional result delivery channel, such as browser_postback."),
  deliveryRequired: z.boolean().optional().describe("Whether delivery through the channel was required for the task."),
  taskId: z.string().optional().describe("Task ID of this run."),
  repo: z.string().optional().describe("Target repository path."),
  worker: z.string().optional().describe("Assigned coding worker."),
  filesChanged: z.array(z.string()).optional().describe("List of files modified."),
  commit: z.string().nullable().optional().describe("Git commit hash if success."),
  commitMessage: z.string().optional().describe("Staged git commit message."),
  pushed: z.boolean().optional().describe("Whether changes were pushed to origin."),
  workingTreeClean: z.boolean().optional().describe("Whether the git working tree is clean."),
  validationSummary: z.array(z.string()).optional().describe("Focused validation summary captured or derived from the run result."),
  summary: z.string().optional().describe("Human readable summary of the task run."),
  workerSummary: z.string().optional().describe("Bounded redacted one-line summary derived from the worker's final report."),
  workerReport: z.string().optional().describe("Bounded redacted worker final report persisted for read-only/no-change retrieval."),
  workerReportMetadata: z.object({
    maxLength: z.number().optional().describe("Maximum persisted worker report length."),
    originalLength: z.number().optional().describe("Redacted report length before truncation."),
    persistedLength: z.number().optional().describe("Persisted report length after truncation."),
    truncated: z.boolean().optional().describe("Whether the worker report was truncated."),
    redacted: z.boolean().optional().describe("Whether redaction was applied before persistence.")
  }).passthrough().optional().describe("Worker report truncation and redaction metadata."),
  workerReportTruncated: z.boolean().optional().describe("Backward-compatible shortcut for workerReportMetadata.truncated."),
  logs: logsSchema.optional().describe("Log references for this run."),
  artifacts: artifactsSchema.optional().describe("Run artifact paths available for retrieval or manual review."),
  error: z.string().optional().describe("Error details if the task failed."),
  errors: z.array(z.string()).optional().describe("Safe error and review guidance messages captured for failed runs."),
  recovery: z.string().optional().describe("Recovery guidance for retrieving persisted results after delivery or client interruption."),
  needsReview: z.boolean().optional().describe("Whether this run needs manual code review."),
  reviewHints: z.array(z.string()).optional().describe("Specific review hints or guidelines for the user."),
  errorType: z.string().optional().describe("Type classification of this error."),
  message: z.string().optional().describe("Detailed human-readable error description."),
  retryable: z.boolean().optional().describe("Whether this request can be retried safely."),
  bridgeStatus: z.number().optional().describe("Optional raw HTTP response status from the bridge.")
});

