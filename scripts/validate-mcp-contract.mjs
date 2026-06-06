#!/usr/bin/env node
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";

import { BridgeClient } from "../mcp/server/bridgeClient.js";
import { loadConfig } from "../mcp/config/loadConfig.js";
import { registerDispatcherTools } from "../mcp/tools/index.js";

const EXPECTED_TOOLS = [
  "dispatcher_status",
  "dispatcher_dispatch",
  "dispatcher_latest_result",
  "dispatcher_get_run"
];

const FORBIDDEN_TOOL_TERMS = [
  "shell",
  "command",
  "file_read",
  "file_write",
  "delete",
  "push",
  "tunnel",
  "remote_exec",
  "credential",
  "config_write"
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function parseToolResult(result) {
  assert(result?.structuredContent && typeof result.structuredContent === "object", "tool result missing structuredContent");
  const text = result.content?.find((item) => item.type === "text")?.text;
  assert(text, "tool result missing text content");
  assert(JSON.stringify(JSON.parse(text)) === JSON.stringify(result.structuredContent), "text and structuredContent diverged");
  return result.structuredContent;
}

class InProcessToolRegistry {
  constructor() {
    this.tools = new Map();
  }

  registerTool(name, config, handler) {
    this.tools.set(name, { name, config, handler });
  }

  names() {
    return [...this.tools.keys()].sort();
  }

  call(name, input) {
    const tool = this.tools.get(name);
    assert(tool, `tool not registered: ${name}`);
    return tool.handler(input);
  }
}

function makeValidDispatch(overrides = {}) {
  return {
    repo: "self",
    worker: "codex",
    task: "Add focused test coverage.",
    commitMessage: "test: mcp contract",
    scope: ["tests/**", "scripts/**"],
    blocked: ["No real remote push"],
    validation: ["npm test"],
    expectedOutput: ["coverage matrix"],
    ...overrides
  };
}

async function withHttpServer(handler, callback) {
  const server = http.createServer(handler);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address();
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function testToolRegistrationAndSafety() {
  const calls = [];
  const registry = new InProcessToolRegistry();
  registerDispatcherTools(registry, {
    status: () => ({ status: "ok", bridgeEnabled: true, taskState: "idle", autoPush: false }),
    dispatch: (payload) => {
      calls.push(payload);
      return { accepted: true, status: "running", worker: "codex", taskState: "running", processId: 123 };
    },
    latestResult: () => ({ status: "error", errorType: "bridge_error", message: "No run results found.", retryable: false, bridgeStatus: 404 }),
    getRun: () => ({ taskId: "20260607-010000-contract", status: "success" })
  });

  assert(JSON.stringify(registry.names()) === JSON.stringify([...EXPECTED_TOOLS].sort()), "MCP tool registration changed");
  assert(registry.names().every((name) => !FORBIDDEN_TOOL_TERMS.some((term) => name.includes(term))), "arbitrary shell/file/git API registered");

  const requiredMissing = parseToolResult(await registry.call("dispatcher_dispatch", makeValidDispatch({ scope: undefined })));
  assert(requiredMissing.status === "error" && requiredMissing.errorType === "validation_error", "missing safety field was not rejected");

  const emptyTask = parseToolResult(await registry.call("dispatcher_dispatch", makeValidDispatch({ task: "   " })));
  assert(emptyTask.status === "error" && emptyTask.errorType === "validation_error", "empty task was not rejected");

  const invalidWorker = parseToolResult(await registry.call("dispatcher_dispatch", makeValidDispatch({ worker: "openclaw" })));
  assert(invalidWorker.status === "error" && invalidWorker.errorType === "validation_error", "invalid worker was not rejected");

  const unsafe = parseToolResult(await registry.call("dispatcher_dispatch", makeValidDispatch({ task: "Please run shell commands directly." })));
  assert(unsafe.status === "error" && unsafe.errorType === "validation_error", "unsafe dispatch was not rejected");

  const accepted = parseToolResult(await registry.call("dispatcher_dispatch", makeValidDispatch()));
  assert(accepted.accepted === true && calls.length === 1, "valid dispatch was not forwarded");
  assert(calls[0].repo === "self" && calls[0].worker === "codex", "dispatch bridge payload changed");
  assert(calls[0].task.includes("MCP safety fields:"), "dispatch envelope omitted MCP safety fields");
  assert(calls[0].task.includes("- scope:\n  - tests/**"), "dispatch envelope formatting changed");
  assert(calls[0].commitMessage === "test: mcp contract", "commit message was not forwarded separately");
}

async function testSafeErrorConversion() {
  const registry = new InProcessToolRegistry();
  registerDispatcherTools(registry, {
    status: () => {
      throw new Error("low-level failure with sensitive detail");
    }
  });

  const error = parseToolResult(await registry.call("dispatcher_status", {}));
  assert(error.status === "error", "safe error conversion did not return error status");
  assert(error.errorType === "bridge_error", "unexpected generic error type");
  assert(error.message === "dispatcher bridge request failed", "unsafe error detail leaked");
}

async function testAuthAndTokenBehavior() {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "jj-dispatcher-mcp-contract-"));
  try {
    const dispatcherDir = path.join(tempRoot, "dispatcher");
    await fs.mkdir(dispatcherDir);
    await fs.writeFile(path.join(dispatcherDir, "config.local.json"), JSON.stringify({
      bridge: {
        enabled: true,
        host: "127.0.0.1",
        port: 12345,
        requireToken: true,
        token: "config-token"
      }
    }), "utf8");

    const fromConfig = await loadConfig({ cwd: tempRoot, env: {} });
    assert(fromConfig.bridge.token === "config-token", "config token was not loaded");
    const fromEnv = await loadConfig({ cwd: tempRoot, env: { JJ_DISPATCHER_BRIDGE_TOKEN: "env-token" } });
    assert(fromEnv.bridge.token === "env-token", "environment token did not override config token");

    await fs.writeFile(path.join(dispatcherDir, "config.local.json"), JSON.stringify({
      bridge: {
        enabled: true,
        host: "127.0.0.1",
        port: 12345,
        requireToken: true,
        token: ""
      }
    }), "utf8");

    let missingRejected = false;
    try {
      await loadConfig({ cwd: tempRoot, env: {} });
    } catch (error) {
      missingRejected = error?.errorType === "config_error" && error.message === "bridge token missing";
    }
    assert(missingRejected, "missing required token was not rejected");
  } finally {
    await fs.rm(tempRoot, { recursive: true, force: true });
  }

  await withHttpServer((request, response) => {
    assert(request.headers["x-dispatcher-token"] === "expected-token", "BridgeClient did not send token header");
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify({ status: "ok" }));
  }, async (baseUrl) => {
    const client = new BridgeClient({ bridge: { baseUrl, requireToken: true, token: "expected-token" } });
    const status = await client.status();
    assert(status.status === "ok", "token-authenticated status failed");
  });

  await withHttpServer((_request, response) => {
    response.writeHead(403, { "Content-Type": "application/json" });
    response.end(JSON.stringify({ error: "X-Dispatcher-Token did not match." }));
  }, async (baseUrl) => {
    const client = new BridgeClient({ bridge: { baseUrl, requireToken: true, token: "bad-token" } });
    let rejected = false;
    try {
      await client.status();
    } catch (error) {
      rejected = error?.errorType === "authentication_error" && error.message === "bridge authentication failed";
    }
    assert(rejected, "bridge authentication failure was not converted safely");
  });
}

async function main() {
  await testToolRegistrationAndSafety();
  console.log("PASS MCP registration, required safety fields, unsafe dispatch rejection, and no arbitrary shell API");

  await testSafeErrorConversion();
  console.log("PASS safe error conversion");

  await testAuthAndTokenBehavior();
  console.log("PASS config/token behavior with isolated localhost auth checks");
}

await main().catch((error) => {
  console.error(`FAIL MCP contract validation - ${error?.message || "unknown error"}`);
  process.exitCode = 1;
});
