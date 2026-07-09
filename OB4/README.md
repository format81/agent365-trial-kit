# OB4 — Confirm an Entra Agent Identity as compromised

A small, self-contained PowerShell utility that marks one or more Microsoft
**Entra Agent Identities** as **"Admin confirmed agent compromised"** using the
Microsoft Graph **`riskyAgents: confirmCompromised`** action (Entra ID
Protection), or verifies their current risk state read-only.

> [!IMPORTANT]
> **Unofficial community content — not affiliated with Microsoft.** The
> `riskyAgents` API is in **PREVIEW** (`/beta`) and may change. Provided
> **"as is", without warranty**; use **at your own risk** and test in a
> non-production tenant first.

## What it does

- **Confirm mode (default)** — `POST /beta/identityProtection/riskyAgents/confirmCompromised`
  → sets the agent's `riskState = confirmedCompromised` and `riskLevel = high`.
- **Check-only mode (`-CheckOnly`)** — read-only `GET` that reports the current
  `riskState` / `riskLevel` without changing anything (idempotent).

It authenticates with the **device code flow**, so it works in VS Code and remote
sessions without a browser pop-up.

## Requirements

- Microsoft Graph permission **`IdentityRiskyAgent.ReadWrite.All`** (admin
  consented on the app used as `-ClientId`).
- Entra role: **Security Administrator** (minimum, for the write action).
- **Microsoft Entra ID Protection (P2)** license.
- Global commercial cloud (the API is `/beta`, not available in national clouds).

## Usage

```powershell
# Show help
.\Confirm-AgentCompromised.ps1 -Help

# Fully interactive (prompts for tenant id + agent id)
.\Confirm-AgentCompromised.ps1

# Verify only, no changes
.\Confirm-AgentCompromised.ps1 -CheckOnly

# Non-interactive
.\Confirm-AgentCompromised.ps1 -TenantId <guid> -AgentId <guid>
.\Confirm-AgentCompromised.ps1 -TenantId <guid> -AgentId <guid> -CheckOnly
```

| Parameter | Description |
|-----------|-------------|
| `-TenantId` | Entra tenant ID (GUID). Prompted if omitted. |
| `-ClientId` | App (client) ID used to authenticate. Defaults to the public Microsoft Azure PowerShell first-party app. |
| `-AgentId` | One or more Agent Identity object ids (comma-separated). Prompted if omitted. |
| `-CheckOnly` | Read-only: report risk state, make no changes. |
| `-Help` | Print usage and exit. |

## How to get the Agent Identity object id

List risky agents in your tenant and copy the `id` you want to act on:

```
GET https://graph.microsoft.com/beta/identityProtection/riskyAgents
```

The `-AgentId` you pass is the **object id** of that `riskyAgent`.

## Verifying the result

After confirming, the script (and a manual `GET`) will show:

```
riskState = confirmedCompromised
riskLevel = high
```

Reference: [riskyAgent: confirmCompromised](https://learn.microsoft.com/en-us/graph/api/riskyagent-confirmcompromised?view=graph-rest-beta)
