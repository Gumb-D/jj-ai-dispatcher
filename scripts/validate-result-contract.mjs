#!/usr/bin/env node
import http from "node:http";

import { BridgeClient, normalizeRunResult } from "../mcp/server/bridgeClient.js";

const oldSuccess = {
  taskId: "20260606-120000-oldsuccess",
  status: "success",
  repo: "D:/dev/projects/jj-ai-dispatcher",
  worker: "codex",
  filesChanged: [],
  commit: "abc1234",
  commitMessage: "test: old success",
  pushed: false,
  workingTreeClean: true,
  summary: "Old success artifact.",
  needsReview: false,
  reviewHints: []
};

const pendingSuccess = {
  taskId: "20260606-120001-pending",
  status: "success",
  executionStatus: "success",
  deliveryStatus: "pending",
  deliveryChannel: "browser_postback",
  deliveryRequired: false,
  repo: "D:/dev/projects/jj-ai-dispatcher",
  worker: "codex",
  filesChanged: ["dispatcher/run.ps1"],
  commit: "def5678",
  commitMessage: "test: pending success",
  pushed: false,
  workingTreeClean: true,
  summary: "Success with pending optional delivery.",
  needsReview: false,
  reviewHints: []
};

const deliveredSuccess = {
  taskId: "20260606-120003-delivered",
  status: "success",
  executionStatus: "success",
  deliveryStatus: "delivered",
  deliveryChannel: "browser_postback",
  deliveryRequired: false,
  repo: "D:/dev/projects/jj-ai-dispatcher",
  worker: "codex",
  filesChanged: ["dispatcher/bridge.ps1"],
  commit: "123abcd",
  commitMessage: "test: delivered success",
  pushed: false,
  workingTreeClean: true,
  summary: "Success with delivered optional postback.",
  needsReview: false,
  reviewHints: []
};

const timeoutSuccess = {
  taskId: "20260606-120004-timeout",
  status: "success",
  executionStatus: "success",
  deliveryStatus: "timeout",
  deliveryChannel: "browser_postback",
  deliveryRequired: false,
  repo: "D:/dev/projects/jj-ai-dispatcher",
  worker: "codex",
  filesChanged: ["dispatcher/bridge.ps1"],
  commit: "456abcd",
  commitMessage: "test: timeout success",
  pushed: false,
  workingTreeClean: true,
  summary: "Success with timed out optional postback.",
  needsReview: false,
  reviewHints: []
};

const unavailableSuccess = {
  taskId: "20260606-120005-unavail",
  status: "success",
  executionStatus: "success",
  deliveryStatus: "unavailable",
  deliveryChannel: "browser_postback",
  deliveryRequired: false,
  repo: "D:/dev/projects/jj-ai-dispatcher",
  worker: "codex",
  filesChanged: ["dispatcher/run.ps1"],
  commit: "789abcd",
  commitMessage: "test: unavailable success",
  pushed: false,
  workingTreeClean: true,
  summary: "Success with unavailable optional postback.",
  needsReview: false,
  reviewHints: []
};

const failedDeliveryFailure = {
  taskId: "20260606-120002-failed",
  status: "failed",
  executionStatus: "failed",
  deliveryStatus: "failed",
  deliveryChannel: "browser_postback",
  deliveryRequired: false,
  repo: "D:/dev/projects/jj-ai-dispatcher",
  worker: "codex",
  filesChanged: [],
  commit: null,
  commitMessage: "test: failed execution",
  pushed: false,
  workingTreeClean: false,
  summary: "Execution failed and optional delivery also failed.",
  needsReview: true,
  reviewHints: ["failure"]
};

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertRunShape(result, expected) {
  assert(result.status === expected.status, `${expected.label} status was ${result.status}`);
  assert(result.executionStatus === expected.executionStatus, `${expected.label} executionStatus was ${result.executionStatus}`);
  assert(result.deliveryStatus === expected.deliveryStatus, `${expected.label} deliveryStatus was ${result.deliveryStatus}`);
  assert(result.deliveryRequired === expected.deliveryRequired, `${expected.label} deliveryRequired was ${result.deliveryRequired}`);
  assert(result.artifacts?.result === `dispatcher/runs/${result.taskId}/result.json`, `${expected.label} result artifact path missing`);
  assert(Array.isArray(result.validationSummary), `${expected.label} validationSummary missing`);
  assert(Array.isArray(result.errors), `${expected.label} errors missing`);
  assert(typeof result.recovery === "string" && result.recovery.length > 0, `${expected.label} recovery guidance missing`);
}

async function withServer(handler, callback) {
  const server = http.createServer(handler);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address();
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function main() {
  assertRunShape(normalizeRunResult(oldSuccess), {
    label: "old success",
    status: "success",
    executionStatus: "success",
    deliveryStatus: "not_requested",
    deliveryRequired: false
  });
  console.log("PASS old result artifact compatibility defaults");

  assertRunShape(normalizeRunResult(pendingSuccess), {
    label: "pending success",
    status: "success",
    executionStatus: "success",
    deliveryStatus: "pending",
    deliveryRequired: false
  });
  console.log("PASS success execution remains success with pending delivery");

  assertRunShape(normalizeRunResult(deliveredSuccess), {
    label: "delivered success",
    status: "success",
    executionStatus: "success",
    deliveryStatus: "delivered",
    deliveryRequired: false
  });
  console.log("PASS success execution remains success with delivered delivery");

  assertRunShape(normalizeRunResult(timeoutSuccess), {
    label: "timeout success",
    status: "success",
    executionStatus: "success",
    deliveryStatus: "timeout",
    deliveryRequired: false
  });
  console.log("PASS success execution remains success with timed out delivery");

  assertRunShape(normalizeRunResult(unavailableSuccess), {
    label: "unavailable success",
    status: "success",
    executionStatus: "success",
    deliveryStatus: "unavailable",
    deliveryRequired: false
  });
  console.log("PASS success execution remains success with unavailable delivery");

  assertRunShape(normalizeRunResult(failedDeliveryFailure), {
    label: "failed execution",
    status: "failed",
    executionStatus: "failed",
    deliveryStatus: "failed",
    deliveryRequired: false
  });
  console.log("PASS failed execution is not overwritten by delivery outcome");

  await withServer((request, response) => {
    const body = request.url === "/runs/latest" ? timeoutSuccess : deliveredSuccess;
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify(body));
  }, async (baseUrl) => {
    const client = new BridgeClient({
      bridge: {
        baseUrl,
        requireToken: false,
        token: ""
      }
    });

    const latest = await client.latestResult();
    assertRunShape(latest, {
      label: "dispatcher_latest_result",
      status: "success",
      executionStatus: "success",
      deliveryStatus: "timeout",
      deliveryRequired: false
    });
    console.log("PASS dispatcher_latest_result exposes final timeout delivery state");

    const run = await client.getRun("20260606-120003-delivered");
    assertRunShape(run, {
      label: "dispatcher_get_run",
      status: "success",
      executionStatus: "success",
      deliveryStatus: "delivered",
      deliveryRequired: false
    });
    console.log("PASS dispatcher_get_run exposes final delivered delivery state");
  });
}

await main().catch((error) => {
  console.error(`FAIL result contract validation - ${error?.message || "unknown error"}`);
  process.exitCode = 1;
});
