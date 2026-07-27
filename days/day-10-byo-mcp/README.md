# Day 10 — Bring your own remote MCP server, kept governed

**Dev** · Published Thu 30 Jul · [Read the LinkedIn post](POST_URL_PLACEHOLDER)

> Part of [11 Days of Agent 365](../../README.md). Personal project, tested on my own
> tenant — not official Microsoft content. Preview features may change.

## The problem
Enterprises are already building internal **MCP servers** to give their agents
real capabilities — look up an employee, query a system, take an action. The
trouble is where these servers live: outside any governance boundary. Admins
have no visibility into what tools are exposed, there's no policy to control how
they're invoked, and security teams get no telemetry. It's shadow tooling, and
it scales quietly with every new agent.

## What Agent 365 does about it
Agent 365's **Bring Your Own (BYO) MCP server** feature routes your remote MCP
server through the **Agent 365 Tooling Gateway**. A developer registers the
server with the `a365` CLI; an admin reviews the declared tools in the Microsoft
365 admin center and **approves or rejects** it, granting the required Entra
permissions on approval. Only then can agents in Copilot Studio, VS Code, Claude
Code, or GitHub Copilot CLI invoke it — and every call flows through the gateway,
so security teams can hunt tool invocations in Microsoft Defender. Approval,
block, tool transparency, and runtime enforcement all become admin controls.

## Try it yourself
This day ships a complete, reproducible sample: a fictional **PRISM Employee
Directory** MCP server you deploy to Azure Container Apps and register with
Agent 365.

1. **Deploy to Azure** (builds the image in ACR — no local Docker/Node needed).
   Pass your resource group and region as parameters:
   ```powershell
   cd days/day-10-byo-mcp/technical/scripts
   ./Deploy-McpToAca.ps1 -ResourceGroup "rg-prism-mcp" -Location "swedencentral"
   ```
   You get a public `https://<fqdn>/mcp` endpoint, and the script prints the
   ready-to-paste `a365` command below.
2. **Register** it with Agent 365 — a **separate step** (different CLI, needs the
   URL from step 1), developer, `a365` CLI ≥ 1.1.165-preview:
   ```powershell
   a365 develop-mcp register-external-mcp-server `
     --server-name "PRISM-EmployeeDirectory" `
     --server-url "https://<fqdn>/mcp" `
     --publisher "Prism Industries" `
     --description "Internal employee lookup service for Prism agents" `
     --auth-type "NoAuth" `
     --tools "get_employee,list_by_department"
   ```
3. **Approve** it (admin): Microsoft 365 admin center → **Agents → Tools →
   Requests** → **Approve** → consent to the Entra permissions.
4. **Use it** (Copilot Studio): add the MCP server as a tool and ask
   *"Who is E001 in the Prism directory?"* or *"List everyone in Sales."*
5. **Monitor** (security): Defender advanced hunting on
   `CloudAppEvents | where ActionType == "ExecuteToolByGateway"`.
6. **Cleanup**: `./Cleanup-McpAca.ps1` for the Azure resources; **Block** the
   registration in the admin center (deletion isn't supported yet).

Full step-by-step, prerequisites, and troubleshooting: **[technical/](technical/)**.

## Watch-outs
- **Preview.** BYO MCP and `a365 develop-mcp` are preview; the CLI must be
  **≥ 1.1.165-preview**, and option names can change.
- **Service principal.** The Agent 365 SP (appId
  `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1`) must be provisioned in your tenant or
  registration fails.
- **NoAuth is demo-only.** The sample serves fictional data with no auth. Real
  workloads should use `APIKey`, `EntraOAuth`, or `ExternalOAuth`.
- **~30 minutes** for an approved server to appear across all Copilot Studio
  environments.
- **No delete.** You can't delete a BYO MCP registration today — plan to
  **Block** it instead.

## What's in this folder
- `assets/` — screenshots and recordings from the post
- `technical/` — the MCP server source, Dockerfile, deploy/cleanup scripts, and
  the full deploy + governance guide ([technical/README.md](technical/README.md))

## References
- [Bring your own (BYO) MCP server](https://learn.microsoft.com/microsoft-365/admin/manage/manage-tools-for-agent?view=o365-worldwide#bring-your-own-byo-mcp-server)
- [Microsoft Agent 365 SDK and CLI](https://learn.microsoft.com/microsoft-agent-365/developer/)
- [Add and manage tools (developer)](https://learn.microsoft.com/microsoft-agent-365/developer/tooling)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
