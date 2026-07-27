/**
 * PRISM Employee Directory — remote MCP server.
 *
 * Exposes a fictional employee directory as two MCP tools over the
 * Streamable HTTP transport. Designed to be registered with Microsoft
 * Agent 365 as a "Bring your own (BYO) MCP server".
 *
 * Transport: stateless Streamable HTTP (a fresh server + transport per
 * request), which is the simplest topology to run behind Azure Container
 * Apps ingress and the Agent 365 Tooling Gateway.
 *
 * Auth: none (NoAuth). This is demo-only data. Register it in Agent 365
 * with --auth-type NoAuth. Do NOT put real data behind a NoAuth server.
 */
import express, { type Request, type Response } from 'express';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';
import { EMPLOYEES } from './employees.js';

const PORT = Number(process.env.PORT) || 3000;

/**
 * Builds a fresh MCP server instance with the directory tools registered.
 * A new instance is created per request in the stateless HTTP topology.
 */
function createMcpServer(): McpServer {
  const server = new McpServer({
    name: 'prism-employee-directory',
    version: '1.0.0'
  });

  server.registerTool(
    'get_employee',
    {
      title: 'Get employee',
      description: 'Look up a single Prism Industries employee by ID, full name, or email address.',
      inputSchema: {
        query: z.string().describe('Employee ID (e.g. E001), full name, or email address')
      }
    },
    async ({ query }) => {
      const q = query.trim().toLowerCase();
      const match = EMPLOYEES.find(e =>
        e.id.toLowerCase() === q ||
        e.name.toLowerCase().includes(q) ||
        e.email.toLowerCase() === q
      );
      return {
        content: [{
          type: 'text',
          text: match
            ? JSON.stringify(match, null, 2)
            : `No employee matching '${query}'.`
        }]
      };
    }
  );

  server.registerTool(
    'list_by_department',
    {
      title: 'List by department',
      description: 'List all Prism Industries employees in a given department (partial match, case-insensitive).',
      inputSchema: {
        department: z.string().describe('Department name or fragment, e.g. "Sales" or "IT"')
      }
    },
    async ({ department }) => {
      const dept = department.trim().toLowerCase();
      const list = EMPLOYEES.filter(e => e.department.toLowerCase().includes(dept));
      return {
        content: [{
          type: 'text',
          text: list.length
            ? JSON.stringify(list, null, 2)
            : `No employees found in a department matching '${department}'.`
        }]
      };
    }
  );

  return server;
}

const app = express();
app.use(express.json());

// Stateless Streamable HTTP endpoint: one server + transport per request.
app.post('/mcp', async (req: Request, res: Response) => {
  const server = createMcpServer();
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined // stateless mode
  });

  res.on('close', () => {
    void transport.close();
    void server.close();
  });

  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    console.error('Error handling MCP request:', err);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: { code: -32603, message: 'Internal server error' },
        id: null
      });
    }
  }
});

// In stateless mode there is no session to resume or terminate.
const methodNotAllowed = (_req: Request, res: Response) =>
  res.status(405).json({
    jsonrpc: '2.0',
    error: { code: -32000, message: 'Method not allowed. This server is stateless; use POST /mcp.' },
    id: null
  });
app.get('/mcp', methodNotAllowed);
app.delete('/mcp', methodNotAllowed);

// Liveness probe used by Azure Container Apps and quick manual checks.
app.get('/health', (_req: Request, res: Response) => res.json({ status: 'ok' }));

app.listen(PORT, () => {
  console.log(`PRISM Employee Directory MCP server listening on port ${PORT}`);
  console.log(`  MCP endpoint : POST /mcp`);
  console.log(`  Health probe : GET  /health`);
});
