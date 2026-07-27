# Day 10 — technical: deploy a BYO MCP server and govern it with Agent 365

Everything you need to stand up the **PRISM Employee Directory** remote MCP
server on Azure, register it with **Microsoft Agent 365**, run the demo, and
clean up. Designed to be reproducible by **anyone with an Azure subscription
and an Agent 365 tenant**.

> [!IMPORTANT]
> Unofficial, community content — **not** an official Microsoft project. The
> Agent 365 **BYO MCP server** feature and the **Agent 365 CLI** are in
> **PREVIEW** and can change or break. Test in a non-production
> tenant/subscription. The deployed server is **NoAuth** and serves only
> fictional data.

## What's in this folder

```
technical/
├─ README.md                    # you are here
├─ prism-employee-mcp/          # the MCP server (Node + TS + Docker)
│  ├─ src/server.ts             # Express + MCP Streamable HTTP (stateless)
│  ├─ src/employees.ts          # fictional directory data
│  ├─ Dockerfile                # multi-stage build (compiles TS in-image)
│  ├─ .dockerignore
│  ├─ package.json
│  ├─ tsconfig.json
│  └─ README.md                 # local dev + tool reference
└─ scripts/
   ├─ Common.ps1                # shared helpers
   ├─ Deploy-McpToAca.ps1       # build in ACR + deploy to Container Apps
   └─ Cleanup-McpAca.ps1        # delete the Azure resources
```

## Architecture

```
 Copilot Studio / VS Code / Claude Code / Copilot CLI
                    │  (approved tool)
                    ▼
        Agent 365 Tooling Gateway  ──►  Defender advanced hunting
                    │                    (ExecuteToolByGateway)
                    ▼
   Azure Container Apps (external HTTPS ingress, /mcp)
                    │
        PRISM Employee Directory MCP server (Node 20)
```

The agent never talks to your server directly — it goes through the **Agent 365
Tooling Gateway**, which is what gives admins approval/block control and gives
security teams telemetry.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Azure subscription** | Contributor on a resource group |
| **Azure CLI** (`az`) | The deploy script auto-installs the `containerapp` extension |
| **Agent 365 CLI** (`a365`) | Version **1.1.165-preview or greater** for BYO MCP |
| **.NET SDK 8.0+** | Required by the Agent 365 CLI |
| **Agent 365 service principal** | appId `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` provisioned in your tenant |
| **Admin (for approval)** | **AI Administrator** or **Global Administrator** to approve + consent |

Install the Agent 365 CLI:

```powershell
dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli
# or update:
dotnet tool update --global Microsoft.Agents.A365.DevTools.Cli
a365 --version   # must be >= 1.1.165-preview
```

## The end-to-end flow at a glance

> [!IMPORTANT]
> **Azure deploy and Agent 365 registration are two separate steps** — by
> design. The deploy script uses the **Azure CLI (`az`)** to create resources.
> Registration uses the **Agent 365 CLI (`a365`)**: a different tool, a
> different login, different roles, and it needs the `/mcp` URL that only exists
> *after* the deploy. Approval is then a **manual admin action** in the
> Microsoft 365 admin center. The only link between the two is
> `scripts/last-deploy.json` (written by deploy, read by cleanup). The deploy
> script prints the ready-to-paste `a365` command for you at the end.

```
[1] Deploy-McpToAca.ps1  --(az)-->  public https://<fqdn>/mcp
         │
[2] a365 develop-mcp register-external-mcp-server  --(a365, separate)-->  pending request
         │
[3] Approve in M365 admin center  (manual, admin)
         │
[4] Use in Copilot Studio / VS Code / Claude Code / Copilot CLI
         │
[5] Cleanup-McpAca.ps1 (Azure)  +  Block in admin center
```

## 1. Deploy to Azure

From the repo root:

```powershell
cd days/day-10-byo-mcp/technical/scripts
az login                      # once, if not already signed in
./Deploy-McpToAca.ps1 -ResourceGroup "rg-prism-mcp" -Location "swedencentral"
```

With an explicit subscription (if you have more than one):

```powershell
./Deploy-McpToAca.ps1 `
  -ResourceGroup "rg-prism-mcp" `
  -Location "swedencentral" `
  -SubscriptionId "<sub-guid>"
```

Run with no parameters to accept every default (`rg-prism-mcp` / `westeurope`).

### Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `-ResourceGroup` | `rg-prism-mcp` | Resource group to create/use |
| `-Location` | `westeurope` | Azure region (e.g. `swedencentral`, `eastus`) |
| `-SubscriptionId` | current `az` context | Subscription to target |
| `-AcrName` | auto-generated unique | ACR name — leave it to auto-generate |
| `-EnvName` | `cae-prism-mcp` | Container Apps environment name |
| `-AppName` | `ca-prism-employee-mcp` | Container App name |
| `-ImageTag` | `v1` | Image tag to build/deploy |

The script:

1. Ensures the `containerapp` CLI extension and logs in if needed.
2. Registers `Microsoft.App`, `Microsoft.OperationalInsights`,
   `Microsoft.ContainerRegistry`.
3. Creates the resource group + a uniquely-named **Basic ACR** (admin-enabled).
4. Builds the image **remotely** with `az acr build` (no local Docker/Node).
5. Creates a **Container Apps environment** and the **Container App** with
   external ingress on port 3000.
6. Prints the public **MCP endpoint** and writes `scripts/last-deploy.json`
   (used by cleanup).

When it finishes you'll get:

```
Health : https://ca-prism-employee-mcp.<region>.azurecontainerapps.io/health
MCP    : https://ca-prism-employee-mcp.<region>.azurecontainerapps.io/mcp
```

Verify:

```powershell
curl https://<fqdn>/health   # -> {"status":"ok"}
```

## 2. Register with Agent 365 (developer) — separate step

This is **not** part of the deploy script. Run it yourself after the deploy,
using the URL the script printed. First sign in with the Agent 365 CLI (this is
a different login from `az`):

```powershell
a365 login
a365 --version   # must be >= 1.1.165-preview
```

The PRISM server is **NoAuth**, so use the `NoAuth` registration. Replace
`<fqdn>` with your deployed endpoint (the script printed the full command):

```powershell
a365 develop-mcp register-external-mcp-server `
  --server-name "PRISM-EmployeeDirectory" `
  --server-url "https://<fqdn>/mcp" `
  --publisher "Prism Industries" `
  --description "Internal employee lookup service for Prism agents" `
  --auth-type "NoAuth" `
  --tools "get_employee,list_by_department"
```

Prefer a file? `a365 develop-mcp register-external-mcp-server -f register.json`:

```json
{
  "serverName": "PRISM-EmployeeDirectory",
  "serverUrl": "https://<fqdn>/mcp",
  "authType": "NoAuth",
  "description": "Internal employee lookup service for Prism agents",
  "publisherName": "Prism Industries",
  "tools": [
    { "name": "get_employee",       "description": "Look up a Prism employee by ID, name, or email" },
    { "name": "list_by_department", "description": "List all employees in a department" }
  ],
  "remoteScopes": null,
  "externalOAuth": null,
  "apiKey": null
}
```

> [!TIP]
> Score your tool schemas before registering:
> `a365 develop-mcp evaluate --server-url "https://<fqdn>/mcp"`

## 3. Approve (admin)

1. Sign in to the [Microsoft 365 admin center](https://admin.cloud.microsoft/).
2. **Agents** → **Tools** → **Requests**.
3. Select **PRISM-EmployeeDirectory**, review the declared tools, **Approve**.
4. **Consent** to the Microsoft Entra permissions when prompted.

> It can take **up to 30 minutes** for the server to appear in all Copilot
> Studio environments after approval + consent.

## 4. Use it (demo)

In **Copilot Studio**: create/open an agent → **Tools** → **MCP Server** →
select **PRISM-EmployeeDirectory** → prompt it, e.g.:

- *"Who is E001 in the Prism directory?"*
- *"List everyone in the Sales department."*

Also supported: **VS Code**, **Claude Code**, **GitHub Copilot CLI**.

## 5. Monitor (security)

In **Microsoft Defender** advanced hunting:

```kusto
CloudAppEvents
| where ActionType == "ExecuteToolByGateway"
| where RawEventData contains "get_employee" or RawEventData contains "list_by_department"
```

Returns agent name, MCP server name, and invocation metadata.

## 6. Cleanup

**Azure resources:**

```powershell
# Targeted delete (reads scripts/last-deploy.json):
./Cleanup-McpAca.ps1

# Or nuke the whole resource group:
./Cleanup-McpAca.ps1 -DeleteResourceGroup -Force
```

**Agent 365 registration:** Microsoft **does not currently support deleting** a
BYO MCP server. To retire it, go to **Microsoft 365 admin center → Agents →
Tools → Registry**, select the server, and choose **Block**. Blocked servers
can't be invoked at runtime on any client surface.

## Watch-outs

- **Preview surface.** `a365 develop-mcp` requires CLI ≥ 1.1.165-preview; run
  `a365 develop-mcp register-external-mcp-server -h` to confirm option names.
- **Service principal.** If registration fails, confirm appId
  `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` is provisioned in your tenant.
- **NoAuth is demo-only.** For real data, register with `APIKey`, `EntraOAuth`,
  or `ExternalOAuth` and secure the endpoint accordingly.
- **No delete for registrations.** Plan for **Block**, not delete.
- **ACR name is global.** The script generates a unique name; override with
  `-AcrName` only if you know it's free.

## References

- [BYO MCP server — Microsoft 365 admin center](https://learn.microsoft.com/microsoft-365/admin/manage/manage-tools-for-agent?view=o365-worldwide#bring-your-own-byo-mcp-server)
- [Agent 365 CLI](https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-cli)
- [`a365 develop-mcp` reference](https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/develop-mcp)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
