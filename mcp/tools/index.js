import { safeErrorResult, toToolResult } from "../server/errors.js";
import {
  assertSafeDispatch,
  dispatchInputSchema,
  emptyInputSchema,
  getRunInputSchema,
  parseInput,
  statusOutputSchema,
  dispatchOutputSchema,
  runOutputSchema
} from "./schemas.js";

export function registerDispatcherTools(server, bridgeClient) {
  server.registerTool("dispatcher_status", {
    description: "Read local Dispatcher bridge status.",
    inputSchema: emptyInputSchema,
    outputSchema: statusOutputSchema
  }, async (input) => callTool(async () => {
    parseInput(emptyInputSchema, input, "dispatcher_status");
    return bridgeClient.status();
  }));

  server.registerTool("dispatcher_dispatch", {
    description: "Submit one explicit, approved task to the existing local Dispatcher bridge.",
    inputSchema: dispatchInputSchema,
    outputSchema: dispatchOutputSchema,
    annotations: {
      destructiveHint: true,
      openWorldHint: false
    }
  }, async (input) => callTool(async () => {
    const payload = parseInput(dispatchInputSchema, input, "dispatcher_dispatch");
    assertSafeDispatch(payload);
    return bridgeClient.dispatch({
      repo: payload.repo,
      worker: payload.worker,
      task: formatTaskEnvelope(payload),
      commitMessage: payload.commitMessage,
      ...getOptionalDispatchMetadata(payload)
    });
  }));

  server.registerTool("dispatcher_latest_result", {
    description: "Read the latest Dispatcher run result from the local bridge.",
    inputSchema: emptyInputSchema,
    outputSchema: runOutputSchema
  }, async (input) => callTool(async () => {
    parseInput(emptyInputSchema, input, "dispatcher_latest_result");
    return bridgeClient.latestResult();
  }));

  server.registerTool("dispatcher_get_run", {
    description: "Read a specific Dispatcher run result by task ID from the local bridge.",
    inputSchema: getRunInputSchema,
    outputSchema: runOutputSchema
  }, async (input) => callTool(async () => {
    const { taskId } = parseInput(getRunInputSchema, input, "dispatcher_get_run");
    return bridgeClient.getRun(taskId);
  }));
}

async function callTool(fn) {
  try {
    return toToolResult(await fn());
  } catch (error) {
    return toToolResult(safeErrorResult(error));
  }
}

function getOptionalDispatchMetadata(payload) {
  const metadata = {};
  for (const name of ["sequenceId", "taskIndex", "taskIdentityHash", "payloadHash", "idempotencyKey", "pushRequested"]) {
    if (Object.prototype.hasOwnProperty.call(payload, name)) {
      metadata[name] = payload[name];
    }
  }
  return metadata;
}

function formatTaskEnvelope(payload) {
  return [
    payload.task,
    "",
    "MCP safety fields:",
    `- repo: ${payload.repo}`,
    `- worker: ${payload.worker}`,
    `- commitMessage: ${payload.commitMessage}`,
    "- scope:",
    ...payload.scope.map((item) => `  - ${item}`),
    "- blocked:",
    ...payload.blocked.map((item) => `  - ${item}`),
    "- validation:",
    ...payload.validation.map((item) => `  - ${item}`),
    "- expectedOutput:",
    ...payload.expectedOutput.map((item) => `  - ${item}`)
  ].join("\n");
}
