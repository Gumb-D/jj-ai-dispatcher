#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createServer } from "./server.js";

async function main() {
  const server = await createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  const message = error?.message || "MCP server failed to start";
  process.stderr.write(`MCP server failed to start: ${message}\n`);
  process.exit(1);
});
