#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";

const CONFIG_PATH = path.join("dispatcher", "config.local.json");
const RUNS_DIR = path.join("dispatcher", "runs");
const TASK_ID_PATTERN = /^[0-9]{8}-[0-9]{6}-[A-Za-z0-9_-]+$/;

async function main() {
  try {
    const latest = await readLatestRun();
    printReviewChecklist(latest);
  } catch (error) {
    console.error(`FAIL review latest run - ${error?.message || "unknown error"}`);
    process.exitCode = 1;
  }
}

async function readLatestRun() {
  const bridgeResult = await readLatestFromBridge();
  if (bridgeResult) {
    return bridgeResult;
  }

  return readLatestFromArtifacts();
}

async function readLatestFromBridge() {
  let config;
  try {
    config = await loadBridgeConfig();
  } catch {
    return null;
  }

  try {
    const headers = {};
    if (config.requireToken) {
      headers["X-Dispatcher-Token"] = config.token;
    }

    const response = await fetch(`${config.baseUrl}/runs/latest`, {
      method: "GET",
      headers,
      signal: AbortSignal.timeout(5000)
    });

    if (!response.ok) {
      return null;
    }

    const result = await response.json();
    return enrichRunResult(result, "bridge");
  } catch {
    return null;
  }
}

async function loadBridgeConfig() {
  const raw = await fs.readFile(CONFIG_PATH, "utf8");
  const config = JSON.parse(raw);
  const bridge = config?.bridge;

  if (!bridge || bridge.enabled !== true || bridge.host !== "127.0.0.1") {
    throw new Error("local bridge configuration is unavailable");
  }

  const requireToken = bridge.requireToken === true;
  const envToken = typeof process.env.JJ_DISPATCHER_BRIDGE_TOKEN === "string"
    ? process.env.JJ_DISPATCHER_BRIDGE_TOKEN.trim()
    : "";
  const configToken = typeof bridge.token === "string" ? bridge.token.trim() : "";
  const token = envToken || configToken;

  if (requireToken && !token) {
    throw new Error("bridge token is required but unavailable");
  }

  return {
    baseUrl: `http://127.0.0.1:${bridge.port}`,
    requireToken,
    token
  };
}

async function readLatestFromArtifacts() {
  const entries = await fs.readdir(RUNS_DIR, { withFileTypes: true }).catch(() => []);
  const taskIds = entries
    .filter((entry) => entry.isDirectory() && TASK_ID_PATTERN.test(entry.name))
    .map((entry) => entry.name)
    .sort();

  if (taskIds.length === 0) {
    throw new Error("no dispatcher run artifacts found");
  }

  for (const taskId of taskIds.reverse()) {
    try {
      const resultPath = path.join(RUNS_DIR, taskId, "result.json");
      const result = JSON.parse(await fs.readFile(resultPath, "utf8"));
      return enrichRunResult(result, "artifact");
    } catch {
      continue;
    }
  }

  throw new Error("no readable dispatcher result.json artifact found");
}

async function enrichRunResult(result, source) {
  if (!result || typeof result !== "object") {
    throw new Error("latest run result is not an object");
  }

  result = normalizeRunResult(result);

  const taskId = String(result.taskId || "");
  if (!TASK_ID_PATTERN.test(taskId)) {
    throw new Error("latest run result has an invalid taskId");
  }

  const summaryPath = path.join(RUNS_DIR, taskId, "summary.md");
  const summaryText = await fs.readFile(summaryPath, "utf8").catch(() => "");

  return {
    source,
    result,
    summaryText
  };
}

function printReviewChecklist({ source, result, summaryText }) {
  const filesChanged = Array.isArray(result.filesChanged) ? result.filesChanged : [];
  const validationHints = collectValidationHints(result, summaryText);
  const classification = suggestClassification(result);

  console.log("# Latest Dispatcher Run Review Checklist");
  console.log("");
  console.log(`Data source: ${source}`);
  console.log(`Task ID: ${valueOrNone(result.taskId)}`);
  console.log(`Status: ${valueOrNone(result.status)}`);
  console.log(`Execution status: ${valueOrNone(result.executionStatus)}`);
  console.log(`Delivery status: ${valueOrNone(result.deliveryStatus)}`);
  console.log(`Delivery channel: ${valueOrNone(result.deliveryChannel)}`);
  console.log(`Delivery required: ${valueOrNone(result.deliveryRequired)}`);
  console.log(`Repo: ${valueOrNone(result.repo)}`);
  console.log(`Worker: ${valueOrNone(result.worker)}`);
  console.log(`Commit: ${valueOrNone(result.commit)}`);
  console.log(`Commit message: ${valueOrNone(result.commitMessage)}`);
  console.log(`Pushed: ${valueOrNone(result.pushed)}`);
  console.log(`Working tree clean: ${valueOrNone(result.workingTreeClean)}`);
  console.log("");

  console.log("## Summary");
  console.log(valueOrNone(result.summary));
  console.log("");

  console.log("## Changed Files");
  printList(filesChanged);
  console.log("");

  console.log("## Validation Hints");
  printList(validationHints);
  console.log("");

  console.log("## Manual Review Checklist");
  console.log("");
  console.log("### Objective");
  console.log("- [ ] Task objective satisfied.");
  console.log("- [ ] Result contract and summary are consistent.");
  console.log("");
  console.log("### Scope");
  console.log("- [ ] Approved scope respected.");
  console.log("- [ ] Forbidden areas untouched.");
  console.log("");
  console.log("### Changed Files");
  console.log("- [ ] Every changed file reviewed.");
  console.log("- [ ] Commit metadata reviewed.");
  console.log("");
  console.log("### Validation");
  console.log("- [ ] Required validations passed or are explicitly justified.");
  console.log("- [ ] `git status --short` reviewed.");
  console.log("");
  console.log("### Safety Boundary");
  console.log("- [ ] No secret, token, credential, or private config exposure.");
  console.log("- [ ] No forbidden MCP tool exposure.");
  console.log("- [ ] No tunnel, remote bridge, public listener, queue, scheduler, or auto-chain behavior.");
  console.log("- [ ] No arbitrary shell, arbitrary file read/write, direct Git MCP tool, or editor control added.");
  console.log("");
  console.log("### Classification Decision");
  console.log("- [ ] accepted");
  console.log("- [ ] rejected");
  console.log("- [ ] needs_followup");
  console.log("");
  console.log(`Suggested classification: ${classification}`);
  console.log("Advisory only: this helper does not persist classification or trigger follow-up dispatch.");
}

function collectValidationHints(result, summaryText) {
  const hints = [];

  if (result.workingTreeClean === true) {
    hints.push("Result contract reports workingTreeClean=true.");
  } else if (result.workingTreeClean === false) {
    hints.push("Result contract reports workingTreeClean=false.");
  }

  if (result.needsReview === true) {
    hints.push("Result contract reports needsReview=true.");
  }

  if (Array.isArray(result.reviewHints) && result.reviewHints.length > 0) {
    hints.push(...result.reviewHints.map((hint) => `Review hint: ${String(hint)}`));
  }

  hints.push(...extractSummarySectionLines(summaryText, "Validation"));

  return [...new Set(hints)];
}

function extractSummarySectionLines(summaryText, heading) {
  const lines = summaryText.split(/\r?\n/);
  const sectionLines = [];
  let inSection = false;

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith("## ")) {
      inSection = trimmed === `## ${heading}`;
      continue;
    }
    if (inSection && trimmed) {
      sectionLines.push(trimmed.replace(/^-+\s*/, ""));
    }
  }

  return sectionLines;
}

function suggestClassification(result) {
  if (result.status !== "success") {
    return "needs_followup";
  }
  if (result.workingTreeClean === false || result.needsReview === true) {
    return "needs_followup";
  }
  return "accepted";
}

const EXECUTION_STATUSES = new Set(["queued", "running", "success", "failed", "cancelled"]);
const DELIVERY_STATUSES = new Set(["not_requested", "pending", "delivered", "timeout", "failed", "skipped", "unavailable"]);

function normalizeRunResult(result) {
  const executionStatus = EXECUTION_STATUSES.has(result.executionStatus)
    ? result.executionStatus
    : EXECUTION_STATUSES.has(result.status)
      ? result.status
      : "failed";
  const deliveryStatus = DELIVERY_STATUSES.has(result.deliveryStatus)
    ? result.deliveryStatus
    : "not_requested";

  return {
    ...result,
    status: executionStatus,
    executionStatus,
    deliveryStatus,
    deliveryChannel: Object.prototype.hasOwnProperty.call(result, "deliveryChannel") ? result.deliveryChannel : null,
    deliveryRequired: Object.prototype.hasOwnProperty.call(result, "deliveryRequired") ? Boolean(result.deliveryRequired) : false
  };
}

function valueOrNone(value) {
  if (value === null || value === undefined || value === "") {
    return "(none)";
  }
  return String(value);
}

function printList(items) {
  if (!Array.isArray(items) || items.length === 0) {
    console.log("- (none)");
    return;
  }

  for (const item of items) {
    console.log(`- ${item}`);
  }
}

await main();
