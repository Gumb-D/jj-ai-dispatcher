import { SafeMcpError } from "./errors.js";

const DEFAULT_TIMEOUT_MS = 30000;

export class BridgeClient {
  constructor(config) {
    this.baseUrl = config.bridge.baseUrl;
    this.requireToken = config.bridge.requireToken;
    this.token = config.bridge.token;
  }

  status() {
    return this.#request("GET", "/status");
  }

  dispatch(payload) {
    return this.#request("POST", "/dispatch", payload);
  }

  latestResult() {
    return this.#request("GET", "/runs/latest").then(normalizeRunResult);
  }

  getRun(taskId) {
    return this.#request("GET", `/runs/${encodeURIComponent(taskId)}`).then(normalizeRunResult);
  }

  async #request(method, pathname, payload) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

    try {
      const headers = {};
      if (this.requireToken) {
        headers["X-Dispatcher-Token"] = this.token;
      }
      if (payload !== undefined) {
        headers["Content-Type"] = "application/json";
      }

      const response = await fetch(`${this.baseUrl}${pathname}`, {
        method,
        headers,
        body: payload === undefined ? undefined : JSON.stringify(payload),
        signal: controller.signal
      });

      const text = await response.text();
      const body = text ? parseJson(text) : {};

      if (response.status === 401 || response.status === 403) {
        throw new SafeMcpError("authentication_error", "bridge authentication failed", false);
      }

      if (!response.ok) {
        return {
          status: "error",
          errorType: "bridge_error",
          message: sanitizeBridgeMessage(body?.error) || "dispatcher bridge returned an error",
          retryable: response.status >= 500,
          bridgeStatus: response.status
        };
      }

      return body;
    } catch (error) {
      if (error instanceof SafeMcpError) {
        throw error;
      }
      if (error?.name === "AbortError") {
        throw new SafeMcpError("timeout", "dispatcher bridge request timed out", true);
      }
      if (error instanceof SyntaxError) {
        throw new SafeMcpError("malformed_response", "dispatcher bridge returned an unexpected response", false);
      }
      throw new SafeMcpError("bridge_unavailable", "dispatcher bridge is unavailable", true);
    } finally {
      clearTimeout(timeout);
    }
  }
}

function parseJson(text) {
  return JSON.parse(text);
}

function sanitizeBridgeMessage(message) {
  if (typeof message !== "string" || !message.trim()) {
    return "";
  }
  return message.replace(/X-Dispatcher-Token/gi, "bridge token header").trim();
}

const EXECUTION_STATUSES = new Set(["queued", "running", "success", "failed", "cancelled"]);
const DELIVERY_STATUSES = new Set(["not_requested", "pending", "delivered", "timeout", "failed", "skipped", "unavailable"]);

export function normalizeRunResult(result) {
  if (!result || typeof result !== "object" || typeof result.taskId !== "string") {
    return result;
  }

  const executionStatus = EXECUTION_STATUSES.has(result.executionStatus)
    ? result.executionStatus
    : EXECUTION_STATUSES.has(result.status)
      ? result.status
      : "failed";
  const deliveryStatus = DELIVERY_STATUSES.has(result.deliveryStatus)
    ? result.deliveryStatus
    : "not_requested";

  const normalized = {
    ...result,
    status: executionStatus,
    executionStatus,
    deliveryStatus,
    deliveryChannel: Object.prototype.hasOwnProperty.call(result, "deliveryChannel") ? result.deliveryChannel : null,
    deliveryRequired: Object.prototype.hasOwnProperty.call(result, "deliveryRequired") ? Boolean(result.deliveryRequired) : false
  };

  if (!Object.prototype.hasOwnProperty.call(normalized, "artifacts")) {
    normalized.artifacts = buildArtifactPaths(normalized);
  }
  if (!Object.prototype.hasOwnProperty.call(normalized, "validationSummary")) {
    normalized.validationSummary = buildValidationSummary(normalized);
  }
  if (!Object.prototype.hasOwnProperty.call(normalized, "errors")) {
    normalized.errors = buildErrors(normalized);
  }
  if (!Object.prototype.hasOwnProperty.call(normalized, "recovery")) {
    normalized.recovery = buildRecoveryMessage(normalized);
  }

  return normalized;
}

function buildArtifactPaths(result) {
  const base = `dispatcher/runs/${result.taskId}`;
  const artifacts = {
    runDir: base,
    task: `${base}/task.json`,
    result: `${base}/result.json`,
    summary: `${base}/summary.md`
  };

  if (result.logs && typeof result.logs === "object") {
    if (typeof result.logs.stdout === "string" && result.logs.stdout.trim()) {
      artifacts.stdout = result.logs.stdout;
    }
    if (typeof result.logs.stderr === "string" && result.logs.stderr.trim()) {
      artifacts.stderr = result.logs.stderr;
    }
    if (typeof result.logs.diff === "string" && result.logs.diff.trim()) {
      artifacts.diff = result.logs.diff;
    }
  }

  return artifacts;
}

function buildValidationSummary(result) {
  const items = [];
  if (typeof result.workingTreeClean === "boolean") {
    items.push(result.workingTreeClean ? "git status --short clean" : "git status --short not clean or unavailable");
  }
  items.push(`deliveryStatus=${result.deliveryStatus}`);
  return items;
}

function buildErrors(result) {
  const errors = [];
  if (typeof result.error === "string" && result.error.trim()) {
    errors.push(result.error.trim());
  }
  if (result.executionStatus !== "success" && Array.isArray(result.reviewHints)) {
    for (const hint of result.reviewHints) {
      if (typeof hint === "string" && hint.trim() && !errors.includes(hint.trim())) {
        errors.push(hint.trim());
      }
    }
  }
  return errors;
}

function buildRecoveryMessage(result) {
  if (result.deliveryStatus === "delivered") {
    return "Browser postback delivered. Persistent result remains available through dispatcher_latest_result and dispatcher_get_run.";
  }
  if (result.deliveryStatus === "pending") {
    return "Browser postback pending. If browser delivery does not complete, retrieve the persisted result through dispatcher_latest_result or dispatcher_get_run.";
  }
  if (result.deliveryStatus === "timeout") {
    return "Browser postback timed out. Execution result remains authoritative through dispatcher_latest_result and dispatcher_get_run.";
  }
  if (result.deliveryStatus === "failed") {
    return "Browser postback failed. Execution result remains authoritative through dispatcher_latest_result and dispatcher_get_run.";
  }
  if (result.deliveryStatus === "skipped") {
    return "Browser postback skipped. Persistent result is available through dispatcher_latest_result and dispatcher_get_run.";
  }
  if (result.deliveryStatus === "unavailable") {
    return "Browser postback unavailable. Persistent result is available through dispatcher_latest_result and dispatcher_get_run.";
  }
  return "Persistent result is available through dispatcher_latest_result and dispatcher_get_run.";
}
