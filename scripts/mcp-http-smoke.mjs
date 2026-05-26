#!/usr/bin/env node
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import net from "node:net";
import path from "node:path";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

import { loadConfig } from "../mcp/config/loadConfig.js";

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

function pass(name, detail = "") {
  console.log(`PASS ${name}${detail ? ` - ${detail}` : ""}`);
}

function fail(name, detail = "") {
  console.error(`FAIL ${name}${detail ? ` - ${detail}` : ""}`);
}

function runBuild() {
  return new Promise((resolve, reject) => {
    const npmCli = findNpmCli();
    const child = spawn(process.execPath, [npmCli, "run", "build"], {
      cwd: process.cwd(),
      stdio: "pipe"
    });

    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      output += chunk.toString();
    });
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`npm run build failed\n${output}`));
      }
    });
  });
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

async function findOpenPort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = address?.port;
      server.close(() => {
        if (Number.isInteger(port)) {
          resolve(port);
        } else {
          reject(new Error("could not allocate a local port"));
        }
      });
    });
  });
}

function startHttpAdapter(port) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["mcp/server/http.js"], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        JJ_DISPATCHER_MCP_HTTP_HOST: "127.0.0.1",
        JJ_DISPATCHER_MCP_HTTP_PORT: String(port)
      },
      stdio: ["ignore", "pipe", "pipe"]
    });

    let output = "";
    let settled = false;
    const timeout = setTimeout(() => {
      if (!settled) {
        settled = true;
        child.kill();
        reject(new Error(`MCP HTTP adapter did not start\n${output}`));
      }
    }, 10000);

    function onData(chunk) {
      output += chunk.toString();
      if (!settled && output.includes("JJ Dispatcher MCP HTTP adapter listening")) {
        settled = true;
        clearTimeout(timeout);
        resolve({ child, output });
      }
    }

    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.on("exit", (code) => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        reject(new Error(`MCP HTTP adapter exited with code ${code}\n${output}`));
      }
    });
  });
}

async function stopHttpAdapter(child) {
  if (!child || child.killed) {
    return;
  }

  await new Promise((resolve) => {
    child.once("exit", resolve);
    child.kill();
    setTimeout(resolve, 3000);
  });
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

function assertDispatchGuard(result) {
  const textItem = result?.content?.find((item) => item.type === "text");
  const text = textItem?.text || "";

  if (result?.isError === true && text.includes("Invalid arguments for tool dispatcher_dispatch")) {
    return;
  }

  const payload = parseToolPayload(result, "dispatcher_dispatch");
  if (payload?.status === "error" && payload.errorType === "validation_error") {
    return;
  }

  throw new Error("dispatcher_dispatch did not reject an invalid non-explicit payload");
}

async function assertBridgeTokenRequired() {
  const config = await loadConfig();
  if (config.bridge.requireToken !== true) {
    throw new Error("bridge token protection is not required by local config");
  }
}

async function main() {
  let client;
  let serverProcess;

  try {
    await runBuild();
    pass("npm build");

    await assertBridgeTokenRequired();
    pass("bridge token/local config required");

    const port = await findOpenPort();
    const started = await startHttpAdapter(port);
    serverProcess = started.child;
    const localUrl = `http://127.0.0.1:${port}/mcp`;
    pass("mcp http adapter start", localUrl);

    client = new Client({ name: "jj-ai-dispatcher-mcp-http-smoke", version: "1.0.0" }, { capabilities: {} });
    const transport = new StreamableHTTPClientTransport(new URL(localUrl));
    await client.connect(transport);
    pass("mcp streamable http connect");

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

    const dispatchGuard = await client.callTool({ name: "dispatcher_dispatch", arguments: {} });
    assertDispatchGuard(dispatchGuard);
    pass("dispatcher_dispatch guard", "invalid non-explicit payload rejected");

    await client.close();
    pass("mcp http smoke complete");
  } catch (error) {
    fail("mcp http smoke", error?.message || "unknown failure");
    if (client) {
      await client.close().catch(() => {});
    }
    process.exitCode = 1;
  } finally {
    await stopHttpAdapter(serverProcess);
  }
}

await main();
