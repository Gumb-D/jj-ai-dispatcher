#!/usr/bin/env node
import { loadConfig } from "../mcp/config/loadConfig.js";
import { BridgeClient } from "../mcp/server/bridgeClient.js";
import { registerDispatcherTools } from "../mcp/tools/index.js";

const EXPECTED_TOOLS = [
  "dispatcher_status",
  "dispatcher_dispatch",
  "dispatcher_latest_result",
  "dispatcher_get_run"
];

const FORBIDDEN_TOOLS = [
  "arbitrary_shell",
  "arbitrary_file_read",
  "arbitrary_file_write",
  "delete",
  "push",
  "tunnel_enable",
  "remote_exec",
  "vscode_ui_control",
  "credential_read",
  "config_write"
];

const checks = [];

function pass(name, detail = "") {
  checks.push({ ok: true, name, detail });
  console.log(`PASS ${name}${detail ? ` - ${detail}` : ""}`);
}

function fail(name, detail = "") {
  checks.push({ ok: false, name, detail });
  console.error(`FAIL ${name}${detail ? ` - ${detail}` : ""}`);
}

function parseToolPayload(result, label) {
  const textItem = result?.content?.find((item) => item.type === "text");
  if (!textItem?.text) {
    throw new Error(`${label} returned no text content`);
  }

  try {
    return JSON.parse(textItem.text);
  } catch {
    return textItem.text;
  }
}

function assertExactTools(tools) {
  const names = tools.map((tool) => tool.name).sort();
  const expected = [...EXPECTED_TOOLS].sort();

  if (JSON.stringify(names) !== JSON.stringify(expected)) {
    throw new Error(`registered tools were ${names.join(", ") || "(none)"}`);
  }

  const forbidden = names.filter((name) => FORBIDDEN_TOOLS.includes(name));
  if (forbidden.length > 0) {
    throw new Error(`forbidden tools registered: ${forbidden.join(", ")}`);
  }
}

function assertStatus(payload) {
  if (!payload || typeof payload !== "object") {
    throw new Error("dispatcher_status returned a non-object payload");
  }
  if (payload.status !== "ok") {
    throw new Error(`dispatcher_status returned status ${String(payload.status)}`);
  }
  if (payload.bridgeEnabled !== true) {
    throw new Error("dispatcher_status did not report bridgeEnabled=true");
  }
  if (Object.prototype.hasOwnProperty.call(payload, "token")) {
    throw new Error("dispatcher_status returned a token field");
  }
}

function assertLatestResult(payload) {
  if (!payload || typeof payload !== "object") {
    throw new Error("dispatcher_latest_result returned a non-object payload");
  }
  if (Object.prototype.hasOwnProperty.call(payload, "token")) {
    throw new Error("dispatcher_latest_result returned a token field");
  }
  if (typeof payload.taskId === "string" && payload.taskId.length > 0) {
    assertRunStatusFields(payload, "dispatcher_latest_result");
    return "latest run present";
  }
  if (payload.status === "error" && payload.errorType === "bridge_error" && payload.bridgeStatus === 404) {
    return "no latest run available";
  }
  throw new Error("dispatcher_latest_result did not return a run or expected no-run state");
}

function assertRunStatusFields(payload, label) {
  const executionStatuses = new Set(["queued", "running", "success", "failed", "cancelled"]);
  const deliveryStatuses = new Set(["not_requested", "pending", "delivered", "timeout", "failed", "skipped", "unavailable"]);

  if (!executionStatuses.has(payload.executionStatus)) {
    throw new Error(`${label} returned invalid executionStatus ${String(payload.executionStatus)}`);
  }
  if (payload.status !== payload.executionStatus) {
    throw new Error(`${label} status did not mirror executionStatus`);
  }
  if (!deliveryStatuses.has(payload.deliveryStatus)) {
    throw new Error(`${label} returned invalid deliveryStatus ${String(payload.deliveryStatus)}`);
  }
  if (typeof payload.deliveryRequired !== "boolean") {
    throw new Error(`${label} returned non-boolean deliveryRequired`);
  }
  if (!Object.prototype.hasOwnProperty.call(payload, "deliveryChannel")) {
    throw new Error(`${label} omitted deliveryChannel`);
  }
}

async function main() {
  try {
    const config = await loadConfig();
    const bridgeClient = new BridgeClient(config);
    const server = new InProcessToolRegistry();
    registerDispatcherTools(server, bridgeClient);
    pass("mcp in-process registry");

    assertExactTools(server.listTools().tools);
    pass("tool registration", EXPECTED_TOOLS.join(", "));

    const status = parseToolPayload(
      await server.callTool({ name: "dispatcher_status", arguments: {} }),
      "dispatcher_status"
    );
    assertStatus(status);
    pass("dispatcher_status", `taskState=${status.taskState ?? "unknown"}`);

    const latest = parseToolPayload(
      await server.callTool({ name: "dispatcher_latest_result", arguments: {} }),
      "dispatcher_latest_result"
    );
    pass("dispatcher_latest_result", assertLatestResult(latest));

    if (typeof latest.taskId === "string" && latest.taskId.length > 0) {
      const run = parseToolPayload(
        await server.callTool({ name: "dispatcher_get_run", arguments: { taskId: latest.taskId } }),
        "dispatcher_get_run"
      );
      assertRunStatusFields(run, "dispatcher_get_run");
      pass("dispatcher_get_run", `taskId=${run.taskId}`);
    }
    pass("mcp smoke complete");
  } catch (error) {
    fail("mcp smoke", error?.message || "unknown failure");
    process.exitCode = 1;
  }
}

class InProcessToolRegistry {
  constructor() {
    this.tools = new Map();
  }

  registerTool(name, config, handler) {
    this.tools.set(name, { name, config, handler });
  }

  listTools() {
    return {
      tools: [...this.tools.values()].map((tool) => ({
        name: tool.name,
        description: tool.config.description
      }))
    };
  }

  callTool({ name, arguments: args }) {
    const tool = this.tools.get(name);
    if (!tool) {
      throw new Error(`tool not registered: ${name}`);
    }
    return tool.handler(args);
  }
}

await main();
