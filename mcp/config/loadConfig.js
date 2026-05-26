import fs from "node:fs/promises";
import path from "node:path";

import { ConfigError } from "../server/errors.js";

const CONFIG_PATH = path.join("dispatcher", "config.local.json");

export async function loadConfig({ cwd = process.cwd(), env = process.env } = {}) {
  let raw;
  const configPath = path.join(cwd, CONFIG_PATH);

  try {
    raw = await fs.readFile(configPath, "utf8");
  } catch (error) {
    if (error && error.code === "ENOENT") {
      throw new ConfigError("dispatcher/config.local.json missing");
    }
    throw new ConfigError("dispatcher config could not be read");
  }

  let config;
  try {
    config = JSON.parse(raw);
  } catch {
    throw new ConfigError("dispatcher/config.local.json is malformed");
  }

  const bridge = config?.bridge;
  if (!bridge || typeof bridge !== "object") {
    throw new ConfigError("bridge configuration missing");
  }

  if (bridge.enabled !== true) {
    throw new ConfigError("bridge is disabled");
  }

  if (bridge.host !== "127.0.0.1") {
    throw new ConfigError("bridge host must be 127.0.0.1");
  }

  if (!Number.isInteger(bridge.port) || bridge.port < 1 || bridge.port > 65535) {
    throw new ConfigError("bridge port is invalid");
  }

  const requireToken = bridge.requireToken === true;
  const envToken = typeof env.JJ_DISPATCHER_BRIDGE_TOKEN === "string"
    ? env.JJ_DISPATCHER_BRIDGE_TOKEN.trim()
    : "";
  const configToken = typeof bridge.token === "string" ? bridge.token.trim() : "";
  const token = envToken || configToken;

  if (requireToken && !token) {
    throw new ConfigError("bridge token missing");
  }

  return {
    bridge: {
      baseUrl: `http://127.0.0.1:${bridge.port}`,
      requireToken,
      token
    }
  };
}
