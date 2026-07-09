# LangChain Agent → Azure App Service → Microsoft Agent 365 (PREVIEW)

A reusable, end‑to‑end sample that shows how to:

1. **Build** an AI agent with **LangChain** + **Azure OpenAI**.
2. **Instantiate** it on **Azure App Service** in a **subscription** and **resource group** *you select* (nothing hard‑coded — tenant included).
3. **Onboard** it via the **Microsoft Agent 365 CLI/SDK** so it becomes a **first‑class tenant citizen** (Entra Agent ID, governance, observability). The **registration progress is shown live in your shell**.
4. Optionally, create **only** an **Entra Agent ID blueprint** with an explicit, transparent step so you can see how it works.

> [!IMPORTANT]
> **Unofficial community content — not a Microsoft product and not affiliated
> with Microsoft.** Microsoft Agent 365 (SDK + CLI) and Entra Agent ID are in
> **PREVIEW**: package names, CLI commands and options can change or break.
> Provided **"as is", without warranty**; use **at your own risk** and test in a
> non-production tenant/subscription first. Verify command options with
> `a365 <command> -h` for your installed version. See the root
> [README](../README.md) and [LICENSE](../LICENSE).

---

## Architecture

| Layer | Technology | Where |
|-------|-----------|-------|
| Enterprise capabilities (identity, observability, tooling) | **Agent 365 SDK / CLI** | `microsoft-agents-a365`, `a365` CLI |
| Agent logic (prompts, tools, reasoning) | **Your code** | [src/agent.py](src/agent.py) |
| LLM orchestrator runtime | **LangChain** | [src/agent.py](src/agent.py) |
| Web host (messaging endpoint) | **FastAPI + Uvicorn** | [src/app.py](src/app.py) |
| Hosting | **Azure App Service (Linux, Python)** | provisioned by [scripts/03-Deploy-AndOnboard.ps1](scripts/03-Deploy-AndOnboard.ps1) |

---

## Folder layout

```
DEV/
├─ Invoke-Agent365Trial.ps1      # top-level interactive menu
├─ requirements.txt              # Python deps (LangChain, FastAPI, A365 SDK preview)
├─ .env.example                  # copy to .env and fill in Azure OpenAI + A365 values
├─ a365.config.template.json     # template for the Agent 365 CLI config
├─ src/
│  ├─ agent.py                   # LangChain tool-calling agent (Azure OpenAI)
│  ├─ app.py                     # FastAPI host (/health, /api/chat, /api/messages)
│  ├─ config.py                  # env-based configuration
│  └─ observability.py           # optional Agent 365 OpenTelemetry wiring (preview)
└─ scripts/
   ├─ Common.ps1                    # shared helpers
   ├─ 00-Prerequisites.ps1          # check/install az, dotnet, a365 CLI, python deps
   ├─ 01-Select-AzureContext.ps1    # pick tenant, subscription, resource group
   ├─ 02-New-AgentBlueprint.ps1     # EXPLICIT: create Entra Agent ID blueprint via a365
   ├─ 03-Deploy-AndOnboard.ps1      # deploy to App Service + register + publish (automated)
   ├─ 04-Cleanup.ps1                # remove Agent 365 blueprint/instance + App Service
   ├─ 05-Grant-OpenAIAccess.ps1     # grant keyless Azure OpenAI role (user + Managed Identity)
   ├─ 06-Grant-BlueprintPermissions.ps1  # grant + consent AgentIdentityBlueprint.ReadWrite.All
   └─ Add-WidsClaim.ps1             # add the 'wids' optional claim the CLI needs
```

> Generated at runtime (git-ignored, never committed): `.env`, `a365.config.json`,
> `a365.generated.config.json` (contains the blueprint **client secret**), and the
> `manifest/` folder produced by `a365 publish`.

---

## Prerequisites

- **Python 3.10+**
- **Azure CLI** (`az`)
- **.NET SDK 8.0+** (required by the Agent 365 CLI)
- **Agent 365 CLI** — `dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli`
- **Azure OpenAI** resource + a chat model deployment (e.g. `gpt-4o` / `gpt-4.1`)
- **Entra roles**: *Agent ID Developer* (blueprint) and, for admin consent, *Global Administrator* (otherwise the CLI prints a hand‑off for a GA). Azure *Contributor* for App Service provisioning.
- An **Azure OpenAI** endpoint (no API key needed — keyless Entra auth is the default).

Install everything with:

```powershell
.\scripts\00-Prerequisites.ps1 -Install
```

---

## Quick start

```powershell
# 0. From the DEV folder
cd Agent365-Trial\DEV

# 1. Configure Azure OpenAI + agent metadata
Copy-Item .env.example .env
# edit .env  ->  AZURE_OPENAI_ENDPOINT / AZURE_OPENAI_DEPLOYMENT
# auth defaults to keyless Entra ID (AZURE_OPENAI_AUTH_MODE=entra)

# 2. Interactive menu (recommended)
.\Invoke-Agent365Trial.ps1
```

Or run the steps directly:

```powershell
.\scripts\00-Prerequisites.ps1 -Install
.\scripts\01-Select-AzureContext.ps1          # select tenant / subscription / RG
.\scripts\02-New-AgentBlueprint.ps1           # (optional) blueprint only
.\scripts\03-Deploy-AndOnboard.ps1            # deploy + register in Agent 365
```

### Run locally first (dev loop)

```powershell
python -m pip install -r requirements.txt
python -m uvicorn src.app:app --reload --port 8000
# POST http://localhost:8000/api/chat  {"message":"What time is it in UTC?"}
```

---

## Authentication to Azure OpenAI (keyless)

By default the agent uses **keyless Microsoft Entra ID auth** (`AZURE_OPENAI_AUTH_MODE=entra`), so it works even when **API keys are disabled** by policy on your Azure OpenAI resource. It uses `DefaultAzureCredential`:

- **Locally**: your `az login` session.
- **On Azure App Service**: the app's **Managed Identity**.

One-time setup — grant your identity the data-plane role on the Azure OpenAI resource:

```powershell
# Your signed-in user (local dev)
$me = az ad signed-in-user show --query id -o tsv
$scope = az cognitiveservices account show -n <aoai-name> -g <rg> --query id -o tsv
az role assignment create --assignee $me `
  --role "Cognitive Services OpenAI User" --scope $scope
```

For App Service, enable a system-assigned Managed Identity and assign it the same role:
```powershell
az webapp identity assign -n <app-name> -g <rg>
$mi = az webapp identity show -n <app-name> -g <rg> --query principalId -o tsv
az role assignment create --assignee $mi `
  --role "Cognitive Services OpenAI User" --scope $scope
```

Prefer API keys instead? Set `AZURE_OPENAI_AUTH_MODE=key` and `AZURE_OPENAI_API_KEY=...` in `.env`.

---

## What each step does

### 1. Select Azure context — [scripts/01-Select-AzureContext.ps1](scripts/01-Select-AzureContext.ps1)
Signs you in, lets you **pick the tenant, subscription and resource group** (or create a new RG), and writes `a365.config.json` from the template. Nothing is hard‑coded.

### 2. Explicit Entra Agent ID blueprint — [scripts/02-New-AgentBlueprint.ps1](scripts/02-New-AgentBlueprint.ps1)
Runs the real CLI and **echoes every command** so you see how it works:

```powershell
a365 setup requirements     # optional prerequisite check
a365 setup blueprint        # creates the Entra Agent ID blueprint
```

A blueprint is the IT‑approved definition of the agent. Creating it provisions a **first‑class Entra Agent ID** — the anchor for Entra governance, Purview and Defender. Use `-DryRun` to preview without changes.

### 3. Deploy + onboard — [scripts/03-Deploy-AndOnboard.ps1](scripts/03-Deploy-AndOnboard.ps1)
Fully automated, in this order (so the messaging endpoint already exists at
registration time and nothing is deferred):
- Provisions an **App Service Plan + Web App (Python 3.11)** with the Oryx build
  enabled, deploys the code, and sets the Uvicorn startup command.
- Configures **keyless Managed Identity** access to Azure OpenAI (app settings +
  role assignment via [scripts/05-Grant-OpenAIAccess.ps1](scripts/05-Grant-OpenAIAccess.ps1)).
- Runs `a365 setup all --m365 --messaging-endpoint <url>` — **blueprint →
  permissions → agent identity SP → registration** — non-interactively.
- Runs `a365 setup permissions bot` and `a365 publish` (creates `manifest/manifest.zip`).

Run it with your Azure OpenAI resource so the Managed Identity is granted automatically:
```powershell
.\scripts\03-Deploy-AndOnboard.ps1 -OpenAIName <aoai-name> -OpenAIResourceGroup <aoai-rg>
```
Useful switches: `-DryRun`, `-SkipInfra`, `-SkipOnboard`, `-SkipBotPermissions`,
`-SkipPublish`, `-ConfigureMcpPermissions`.

### Helper scripts you may need
- [scripts/06-Grant-BlueprintPermissions.ps1](scripts/06-Grant-BlueprintPermissions.ps1) —
  grants + admin-consents `AgentIdentityBlueprint.ReadWrite.All` on the client app
  and re-runs blueprint setup, so **inheritable permissions** apply to agent
  instances. Needed if `setup blueprint` reports *Insufficient privileges*.
- [scripts/Add-WidsClaim.ps1](scripts/Add-WidsClaim.ps1) — adds the `wids` optional
  claim the CLI needs to detect the Global Administrator role. Run it (then
  `az logout; az login --use-device-code`) if requirements reports the `wids` claim missing.

> Tip: after granting new consent, refresh your token with
> `az logout; az login --use-device-code` so the next CLI call carries it.

---

## Manual governance steps (by design)

The scripts automate everything the platform allows — **up to and including
`a365 publish`**, which produces `manifest/manifest.zip`. The remaining steps are
**manual governance/approval gates** with no supported automation:

1. **Upload `manifest.zip`** — Microsoft 365 admin center → *Agents → Upload
   custom agent* (**Global Administrator**).
2. **Configure the blueprint** in the Teams Developer Portal
   (Agent Type = *API Based*, Notification URL = your `/api/messages` endpoint).
3. **Create an agent instance** from Teams → admin approves. This creates the
   **Agent Identity**, so a freshly created blueprint shows *Agent identities: 0*
   until an instance exists. Requires the tenant enrolled in **Frontier**.

References: [Publish agent](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/publish) ·
[Create agent instances](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/create-instance).

---

## Observability (optional, preview)

Once `a365 setup all` completes, the CLI writes the `A365_*` values (config sync). Set `A365_OBSERVABILITY_ENABLED=true` and install the preview packages in [requirements.txt](requirements.txt) to emit OpenTelemetry traces to Agent 365. Wiring lives in [src/observability.py](src/observability.py) and fails safe if the SDK isn't present.

---

## Clean up

Use the cleanup script — [scripts/04-Cleanup.ps1](scripts/04-Cleanup.ps1) — which wraps the CLI and also removes the App Service resources this trial created:

```powershell
# Interactive (from the menu): option 6
.\Invoke-Agent365Trial.ps1 -Step cleanup

# Remove everything (Agent 365 blueprint/instance + Azure) and the Web App/Plan
.\scripts\04-Cleanup.ps1 -Scope all -DeleteAppService -Force

# Only the Entra blueprint, preview first
.\scripts\04-Cleanup.ps1 -Scope blueprint -DryRun
```

Under the hood it calls the real CLI:

```powershell
a365 cleanup                 # blueprint + instance + Azure resources created by the CLI
a365 cleanup azure           # App Service, App Service Plan
a365 cleanup blueprint       # Entra ID blueprint app + service principal
a365 cleanup instance        # agent instance identity + user
```

---

## References (Microsoft Learn)

- Get started with Agent 365 development — https://learn.microsoft.com/microsoft-agent-365/developer/get-started
- Agent 365 SDK — https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-sdk
- Agent 365 CLI — https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-cli
- CLI `setup` reference — https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/setup
- Entra agent blueprint — https://learn.microsoft.com/entra/agent-id/identity-platform/agent-blueprint
- Observability — https://learn.microsoft.com/microsoft-agent-365/developer/observability

---

## License / contributions

This scaffold is intended to be shared on GitHub. Adapt the tools, prompts and hosting to your needs. PRs welcome. Provided “as is”, without warranty; validate against the current Agent 365 preview before production use.
