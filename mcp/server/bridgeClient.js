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

  return {
    ...result,
    status: executionStatus,
    executionStatus,
    deliveryStatus,
    deliveryChannel: Object.prototype.hasOwnProperty.call(result, "deliveryChannel") ? result.deliveryChannel : null,
    deliveryRequired: Object.prototype.hasOwnProperty.call(result, "deliveryRequired") ? Boolean(result.deliveryRequired) : false
  };
}
