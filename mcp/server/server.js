import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

import { loadConfig } from "../config/loadConfig.js";
import { registerDispatcherTools } from "../tools/index.js";
import { BridgeClient } from "./bridgeClient.js";

export async function createServer() {
  const config = await loadConfig();
  const bridgeClient = new BridgeClient(config);
  const server = new McpServer({
    name: "jj-ai-dispatcher",
    version: "0.1.0"
  });

  registerDispatcherTools(server, bridgeClient);

  return server;
}
