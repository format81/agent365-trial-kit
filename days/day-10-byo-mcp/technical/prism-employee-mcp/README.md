# PRISM Employee Directory — remote MCP server

A tiny, self-contained **remote MCP server** exposing a fictional employee
directory for *Prism Industries*. It's the payload for the Day 10 demo:
**bring your own (BYO) MCP server, kept governed by Microsoft Agent 365**.

All data is synthetic. The server runs **NoAuth** on purpose — it's a demo.

## Stack

- **Runtime:** Node.js 20 + Express
- **MCP SDK:** `@modelcontextprotocol/sdk` v1 (Streamable HTTP transport, stateless)
- **Language:** TypeScript

## Tools exposed

| Tool | Description | Input |
|------|-------------|-------|
| `get_employee` | Look up a single employee by ID, name, or email | `query: string` |
| `list_by_department` | List employees in a department (partial match) | `department: string` |

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/mcp` | MCP Streamable HTTP endpoint (stateless) |
| `GET`  | `/health` | Liveness probe (`{ "status": "ok" }`) |

## Run locally

```powershell
npm install
npm run build
npm start
# -> PRISM Employee Directory MCP server listening on port 3000
```

Smoke-test it:

```powershell
curl http://localhost:3000/health

# Inspect the tools interactively:
npx @modelcontextprotocol/inspector
# then connect (Streamable HTTP) to http://localhost:3000/mcp
```

Or list tools with a raw JSON-RPC call:

```powershell
curl -X POST http://localhost:3000/mcp `
  -H "Content-Type: application/json" `
  -H "Accept: application/json, text/event-stream" `
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## Deploy to Azure + register with Agent 365

Don't build by hand — use the scripts. The image builds remotely in ACR, so
you don't need Docker or Node locally:

```powershell
../scripts/Deploy-McpToAca.ps1
```

Full walkthrough (deploy → register → demo → cleanup) is in
[../README.md](../README.md) and the day overview in
[../../README.md](../../README.md).

## Notes

- **Stateless transport:** a fresh MCP server + transport is created per
  request. This is the simplest topology behind Container Apps ingress and the
  Agent 365 Tooling Gateway — no sticky sessions required.
- **NoAuth:** never put real data behind a NoAuth server. For real workloads use
  `APIKey`, `EntraOAuth`, or `ExternalOAuth` when registering with Agent 365.
