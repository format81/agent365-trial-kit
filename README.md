# Agent 365 Trial — LangChain agent onboarding & Entra Agent ID toolkit

Hands-on, reusable scripts and a sample agent that show how to build an AI agent,
host it on Azure, and onboard it to **Microsoft Agent 365** so it becomes a
first-class, governed tenant citizen — plus a small **Entra Agent ID** security
utility. Everything is scripted and automated as far as the platform allows, so
you can reproduce the whole flow for **testing, demos, or PoCs**.

> [!IMPORTANT]
> **Unofficial, community content.** This repository is **not** an official
> Microsoft project and is **not** endorsed by or affiliated with Microsoft.
> Several capabilities it uses (Microsoft **Agent 365 SDK/CLI**, **Entra Agent
> ID**, the Graph **riskyAgents** API) are in **PREVIEW** and can change or break
> at any time. Provided **"as is", without warranty of any kind**; you use it
> **at your own risk**. Review every script before running it and always test in
> a non-production tenant/subscription first. See [LICENSE](LICENSE).

---

## Why this exists

Microsoft Agent 365 turns fragmented AI-agent experimentation into governed,
enterprise-grade operations: a single control plane where agents are visible,
identity-backed (Entra Agent ID), observable (OpenTelemetry), data-protected
(Purview) and threat-monitored (Defender).

This repo gives you a **working, end-to-end reference** for that lifecycle so you
don't have to piece it together from docs:

- Build an agent (LangChain + Azure OpenAI).
- Host it on Azure App Service — in a subscription/resource group **you select**.
- Onboard/register it in Agent 365 via the **Agent 365 CLI**, creating a governed
  **Entra Agent ID blueprint**.
- See, step by step, how a blueprint and its inheritable permissions are created.
- Separately, flag a risky **Agent Identity** as *admin-confirmed compromised*.

## Objectives

- ✅ **Reproducible**: nothing hard-coded — you pick tenant, subscription,
  resource group, and Azure OpenAI resource interactively.
- ✅ **Keyless by default**: authenticates to Azure OpenAI with Microsoft Entra ID
  (works when API keys are disabled by policy).
- ✅ **Automated to the maximum the platform allows** (see
  [Manual governance steps](#manual-governance-steps-by-design)).
- ✅ **Transparent**: each script echoes the real CLI/Graph commands it runs.
- ✅ **Shareable**: safe `.gitignore`, templates instead of secrets, MIT license.

---

## Repository layout

```
Agent365-Trial/
├─ README.md                     # you are here (overview + publishing guide)
├─ LICENSE                       # MIT
├─ .gitignore                    # protects secrets & generated artifacts
│
├─ DEV/                          # Build → host → onboard a LangChain agent
│  ├─ README.md                  # detailed developer guide (start here to build)
│  ├─ Invoke-Agent365Trial.ps1   # interactive menu / single entry point
│  ├─ requirements.txt
│  ├─ .env.example               # copy to .env (never commit .env)
│  ├─ a365.config.template.json  # template the scripts fill in
│  ├─ src/                       # LangChain agent + FastAPI host + config
│  └─ scripts/                   # numbered PowerShell automation (00 → 06)
│
└─ OB4/                          # Entra Agent ID security utility
   ├─ README.md
   └─ Confirm-AgentCompromised.ps1   # mark an Agent Identity as compromised
```

Two independent tracks — use either or both:

| Track | What it does | Start at |
|-------|--------------|----------|
| **DEV** | Build a LangChain agent, deploy to Azure App Service, onboard to Agent 365 (blueprint, permissions, registration, publish). | [DEV/README.md](DEV/README.md) |
| **OB4** | Confirm one or more Entra **Agent Identities** as *compromised* via the Microsoft Graph `riskyAgents` API (Entra ID Protection). | [OB4/README.md](OB4/README.md) |

---

## Prerequisites

- **Python 3.10+**
- **Azure CLI** (`az`)
- **.NET SDK 8.0+** (required by the Agent 365 CLI)
- **Agent 365 CLI**: `dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli`
- An **Azure OpenAI** resource + a chat model deployment (e.g. `gpt-4o` / `gpt-4.1`)
- **Entra roles**: *Agent ID Developer* (blueprint) and, for admin consent,
  *Global Administrator*; Azure *Contributor* for App Service provisioning
- For the OB4 utility: **Entra ID Protection (P2)** + *Security Administrator*

The `00-Prerequisites.ps1` script checks and can install most of these.

---

## Quick start (DEV track)

```powershell
cd DEV

# 1. Configure the agent (endpoint + deployment; keyless Entra auth by default)
Copy-Item .env.example .env
#   set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT in .env

# 2. Run the guided menu
.\Invoke-Agent365Trial.ps1
```

Menu order: **1** prerequisites → **2** select Azure context → **3** grant keyless
Azure OpenAI access → **4** create blueprint (optional) → **5** deploy + onboard →
**6** run locally → **7** cleanup.

Prefer the discrete steps? See the full walkthrough in [DEV/README.md](DEV/README.md).

---

## Manual governance steps (by design)

The automation covers the entire lifecycle **up to and including packaging**
(`a365 publish` creates `manifest/manifest.zip`). The final steps are **manual by
design** — they are Microsoft's governance/approval gates and are **not**
exposed as automatable APIs in the supported Agent 365 flow:

1. **Upload `manifest.zip`** in the Microsoft 365 admin center
   (*Agents → Upload custom agent*) — requires a **Global Administrator**.
2. **Configure the blueprint** in the Teams Developer Portal
   (Agent Type = *API Based*, Notification URL = your `/api/messages` endpoint).
3. **Create an agent instance** from Teams → admin approves it. This is the step
   that actually creates the **Agent Identity** (so "Agent identities: 0" on the
   blueprint is expected until then). Requires the tenant to be enrolled in the
   **Frontier** program.

References: [Publish agent](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/publish) ·
[Create agent instances](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/create-instance).

---

## Publishing this to your own GitHub

See the step-by-step in [How to publish to GitHub](#how-to-publish-to-github)
below. In short: this folder is already a self-contained repo root with a safe
`.gitignore`.

### Suggested repository names

- **`agent365-trial-kit`** *(this repo)*
- `agent365-langchain-lab`
- `entra-agent-id-langchain-poc`

### How to publish to GitHub

> Do this **from the `Agent365-Trial` folder** so it becomes the repo root.
> Contribution guidelines live in [CONTRIBUTING.md](CONTRIBUTING.md).

1. **Confirm no secrets will be committed.** The `.gitignore` already excludes
   `.env`, `a365.config.json`, `a365.generated.config.json`, and `manifest/`.
   Double-check:
   ```powershell
   cd C:\_F0rm4tC0de\MCPLabs\Agent365-Trial
   git init
   git add -A
   git status            # verify .env / *.config.json / manifest/ are NOT listed
   ```
   If you ever see a secret staged, run `git rm --cached <file>` before committing.

2. **First commit:**
   ```powershell
   git commit -m "Initial commit: Agent 365 LangChain onboarding toolkit"
   git branch -M main
   ```

3. **Create the empty repo on GitHub and push:**
   ```powershell
   # Option A - GitHub CLI (if installed):
   gh repo create agent365-trial-kit --public --source . --remote origin --push

   # Option B - manual: create the repo on github.com (no README), then:
   git remote add origin https://github.com/format81/agent365-trial-kit.git
   git push -u origin main
   ```

4. **Rotate the demo secret.** If you ever ran the DEV flow, a blueprint client
   secret was generated locally. It is git-ignored, but if you suspect it was
   exposed, rotate it: `a365 setup blueprint --show-secret` to view / regenerate.

---

## Cleanup (avoid ongoing Azure costs)

The DEV flow provisions a **B1 App Service Plan** (billed while it exists):

```powershell
cd DEV
.\scripts\04-Cleanup.ps1 -Scope all -DeleteAppService -Force
```

---

## Contributing & disclaimer

Contributions welcome via issues/PRs. This is unofficial community content, not a
Microsoft product. Preview features may change; validate against current Agent 365
documentation before any production use. No warranty; use at your own risk.
