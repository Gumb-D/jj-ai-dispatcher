#!/usr/bin/env node
import { randomUUID } from "node:crypto";

import { createMcpExpressApp } from "@modelcontextprotocol/sdk/server/express.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";

import { createServer } from "./server.js";

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 8790;
const PUBLIC_EXPOSURE_CONFIRMATION = "I_UNDERSTAND_THIS_REQUIRES_SECURITY_REVIEW";

function readHttpConfig(env = process.env) {
  const host = (env.JJ_DISPATCHER_MCP_HTTP_HOST || DEFAULT_HOST).trim();
  const portText = (env.JJ_DISPATCHER_MCP_HTTP_PORT || String(DEFAULT_PORT)).trim();
  const port = Number.parseInt(portText, 10);

  if (!host) {
    throw new Error("JJ_DISPATCHER_MCP_HTTP_HOST must not be empty");
  }

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("JJ_DISPATCHER_MCP_HTTP_PORT must be a valid TCP port");
  }

  if (!isLocalHost(host) && env.JJ_DISPATCHER_MCP_HTTP_ALLOW_PUBLIC !== PUBLIC_EXPOSURE_CONFIRMATION) {
    throw new Error(
      "public MCP HTTP binding requires explicit reviewed config; keep JJ_DISPATCHER_MCP_HTTP_HOST on localhost"
    );
  }

  return { host, port };
}

function isLocalHost(host) {
  return host === "127.0.0.1" || host === "localhost" || host === "::1";
}

async function connectTransport(transport) {
  const server = await createServer();
  await server.connect(transport);
  return server;
}

async function main() {
  const { host, port } = readHttpConfig();
  const app = createMcpExpressApp({ host });
  const transports = new Map();

  app.get("/health", (_req, res) => {
    res.json({
      status: "ok",
      transport: "mcp-http",
      endpoints: {
        streamableHttp: "/mcp",
        sse: "/sse",
        messages: "/messages"
      }
    });
  });

  app.all("/mcp", async (req, res) => {
    try {
      const sessionId = req.headers["mcp-session-id"];
      let transport;

      if (sessionId && transports.has(sessionId)) {
        const existingTransport = transports.get(sessionId);
        if (!(existingTransport instanceof StreamableHTTPServerTransport)) {
          return res.status(400).json(jsonRpcError("Session uses a different transport protocol"));
        }
        transport = existingTransport;
      } else if (!sessionId && req.method === "POST" && isInitializeRequest(req.body)) {
        transport = new StreamableHTTPServerTransport({
          sessionIdGenerator: () => randomUUID(),
          onsessioninitialized: (newSessionId) => {
            transports.set(newSessionId, transport);
          }
        });

        transport.onclose = () => {
          if (transport.sessionId) {
            transports.delete(transport.sessionId);
          }
        };

        await connectTransport(transport);
      } else {
        return res.status(400).json(jsonRpcError("No valid MCP session or initialization request"));
      }

      await transport.handleRequest(req, res, req.body);
    } catch (error) {
      writeServerError(res, error);
    }
  });

  app.get("/sse", async (_req, res) => {
    try {
      const transport = new SSEServerTransport("/messages", res);
      transports.set(transport.sessionId, transport);
      res.on("close", () => transports.delete(transport.sessionId));
      await connectTransport(transport);
    } catch (error) {
      writeServerError(res, error);
    }
  });

  app.post("/messages", async (req, res) => {
    try {
      const sessionId = req.query.sessionId;
      const transport = transports.get(sessionId);

      if (!(transport instanceof SSEServerTransport)) {
        return res.status(400).json(jsonRpcError("No SSE transport found for sessionId"));
      }

      await transport.handlePostMessage(req, res, req.body);
    } catch (error) {
      writeServerError(res, error);
    }
  });

  const httpServer = app.listen(port, host, () => {
    const baseUrl = `http://${host}:${port}`;
    console.log(`JJ Dispatcher MCP HTTP adapter listening at ${baseUrl}`);
    console.log(`Streamable HTTP MCP endpoint: ${baseUrl}/mcp`);
    console.log(`Legacy SSE MCP endpoint: ${baseUrl}/sse`);
    console.log("LOCAL FEASIBILITY ONLY: ChatGPT requires an HTTPS MCP Server URL.");
    console.log("Do not tunnel raw Dispatcher bridge.");
  });

  process.on("SIGINT", () => shutdown(httpServer, transports));
  process.on("SIGTERM", () => shutdown(httpServer, transports));
}

function jsonRpcError(message) {
  return {
    jsonrpc: "2.0",
    error: {
      code: -32000,
      message
    },
    id: null
  };
}

function writeServerError(res, error) {
  const message = error?.message || "MCP HTTP adapter error";
  console.error(`MCP HTTP adapter error: ${message}`);
  if (!res.headersSent) {
    res.status(500).json(jsonRpcError("Internal server error"));
  }
}

async function shutdown(httpServer, transports) {
  for (const transport of transports.values()) {
    await transport.close().catch(() => {});
  }
  transports.clear();
  httpServer.close(() => process.exit(0));
}

main().catch((error) => {
  const message = error?.message || "MCP HTTP adapter failed to start";
  process.stderr.write(`MCP HTTP adapter failed to start: ${message}\n`);
  process.exit(1);
});
