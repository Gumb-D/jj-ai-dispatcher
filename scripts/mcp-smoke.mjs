#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

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

function runBuild() {
  const npmCli = findNpmCli();
  const result = spawnSync(process.execPath, [npmCli, "run", "build"], {
    cwd: process.cwd(),
    stdio: "pipe",
    encoding: "utf8"
  });

  if (result.status !== 0) {
    throw new Error("npm run build failed");
  }
}

function findNpmCli() {
  const candidates = [
    process.env.npm_execpath,
    path.join(path.dirname(process.execPath), "node_modules", "npm", "bin", "npm-cli.js")
  ].filter(Boolean);

  const npmCli = candidates.find((candidate) => existsSync(candidate));
  if (!npmCli) {
    throw new Error("npm CLI could not be located");
  }
  return npmCli;
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
    return "latest run present";
  }
  if (payload.status === "error" && payload.errorType === "bridge_error" && payload.bridgeStatus === 404) {
    return "no latest run available";
  }
  throw new Error("dispatcher_latest_result did not return a run or expected no-run state");
}

async function main() {
  let client;

  try {
    runBuild();
    pass("npm build");

    client = new Client({ name: "jj-ai-dispatcher-mcp-smoke", version: "1.0.0" }, { capabilities: {} });
    const transport = new StdioClientTransport({
      command: "node",
      args: ["mcp/server/index.js"],
      cwd: process.cwd(),
      stderr: "pipe"
    });

    await client.connect(transport);
    pass("mcp stdio connect");

    const listed = await client.listTools();
    assertExactTools(listed.tools);
    pass("tool registration", EXPECTED_TOOLS.join(", "));

    const status = parseToolPayload(
      await client.callTool({ name: "dispatcher_status", arguments: {} }),
      "dispatcher_status"
    );
    assertStatus(status);
    pass("dispatcher_status", `taskState=${status.taskState ?? "unknown"}`);

    const latest = parseToolPayload(
      await client.callTool({ name: "dispatcher_latest_result", arguments: {} }),
      "dispatcher_latest_result"
    );
    pass("dispatcher_latest_result", assertLatestResult(latest));

    await client.close();
    pass("mcp smoke complete");
  } catch (error) {
    fail("mcp smoke", error?.message || "unknown failure");
    if (client) {
      await client.close().catch(() => {});
    }
    process.exitCode = 1;
  }
}

await main();
