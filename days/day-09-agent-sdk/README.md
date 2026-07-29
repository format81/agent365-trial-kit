# Day 9 — Agent 365 SDK: onboarding a LangChain agent

**Dev** · Published 29 Jul · [Read the LinkedIn post](https://www.linkedin.com/posts/antonioformato_11daysofagent365-agentsdk-langchain-ugcPost-7488118729382248449-tv2e/)

> Part of [11 Days of Agent 365](../../README.md). Personal project, tested on my own
> tenant — not official Microsoft content. Preview features may change.

## Walkthrough (4 min)
▶️ [Watch on LinkedIn](https://www.linkedin.com/posts/antonioformato_11daysofagent365-agentsdk-langchain-ugcPost-7488118729382248449-tv2e/) · [Download the recording](assets/agent365-langchain-onboard.mp4)

🛠️ **The full agent, scripts and onboarding flow live in [DEV/](../../DEV/) at the repo root.**

## The problem
Teams build genuinely capable agents in LangChain, the OpenAI SDK, n8n and a dozen other
frameworks — and then those agents live *outside* enterprise governance. There's no managed
identity behind them, no policy inheritance, no place in the tenant's agent estate. They run
on someone's API key, they're invisible to the admins who are accountable for them, and they
can't be governed the way every other identity in the tenant is. The framework you build in
shouldn't decide whether the agent is governable.

## What Agent 365 does about it
The Agent 365 SDK doesn't build or host your agent — it **governs the one you already built**,
in any framework. In this day's demo I take a LangChain agent running on Azure OpenAI (hosted
by FastAPI) and onboard it end to end:

- **Keyless by design.** The agent authenticates to Azure OpenAI with Microsoft Entra ID
  locally and a Managed Identity in the cloud — **no API keys**, so it works even where key
  auth is disabled by policy.
- **One onboarding flow through the Agent 365 CLI.** blueprint → permissions → agent identity
  → registration → publish, with the registration progress shown live in the shell.
- **A first-class tenant citizen at the end.** The agent lands with its own **Entra Agent ID**
  and inherits the blueprint's policies — governed like any other identity in the tenant.

<!-- SCREENSHOT (demo order 1): the LangChain agent running locally (uvicorn / a /api/chat response).
     Place assets/<file>.png here with a one-line italic caption. -->

The full implementation — agent code, PowerShell scripts and the whole flow — is in
[DEV/](../../DEV/) at the repo root. This page links to it rather than restating the code.

<!-- SCREENSHOT (demo order 2): the deploy + onboard script showing live registration progress in the shell.
     Place assets/<file>.png here with a one-line italic caption. -->

## Try it yourself
The real, runnable steps live in [DEV/](../../DEV/) — see [DEV/README.md](../../DEV/README.md).
Summarized:

1. **Prereqs** — Python 3.10+, Azure CLI, .NET SDK 8, and the Agent 365 CLI.
2. **Configure `.env`** — Azure OpenAI endpoint + deployment; keyless Entra auth is the default.
3. **Run the deploy + onboard script** — provisions the host, registers and publishes the agent
   (see [DEV/README.md](../../DEV/README.md)).
4. **Complete the three manual governance gates:**
   - Upload the manifest in the **Microsoft 365 admin center**.
   - Configure the blueprint in the **Teams Developer Portal** — Notification URL = `/api/messages`.
   - Create an instance from **Teams** and have an admin approve it.
5. **Confirm the agent in the registry** with its **Entra Agent ID**.

Full commands and scripts: [DEV/](../../DEV/).

<!-- SCREENSHOT (demo order 3, BEFORE): a fresh blueprint showing "Agent identities: 0".
     Place assets/<file>.png here with a one-line italic caption. Pair with the AFTER shot below. -->

<!-- SCREENSHOT (demo order 4): the manual governance gates (manifest upload / blueprint config / instance approval).
     Place assets/<file>.png here with a one-line italic caption. -->

<!-- SCREENSHOT (demo order 5, AFTER): the agent in the registry with its Entra Agent ID (identities 0 -> 1).
     Place assets/<file>.png here with a one-line italic caption. Pair with the BEFORE shot above. -->

## Watch-outs
- The SDK **governs an agent you already built** — it does **not** build or host it, and it is
  **not** the Microsoft 365 Agents SDK (that's a different layer).
- A fresh blueprint shows **"Agent identities: 0"** until an instance is created and an admin
  approves it. That's expected, not broken — the identity is created **on approval**.
- The three manual steps (manifest upload, blueprint config, instance approval) are **governance
  gates by design**, not automatable — your CI/CD stops at that door.
- Creating an instance requires the tenant to be enrolled in the **Frontier** program.
- The Notification URL must be `/api/messages`, **not** `/api/chat`.
- Keyless needs the **Cognitive Services OpenAI User** role on the Azure OpenAI resource. The
  deploy script grants it; assign it manually if you're testing locally first.
- One-time setup prerequisites that can bite:
  - The **WAM broker can hang** — set `MSAL_DISABLE_BROKER=1` and use `az login --use-device-code`.
  - The Agent 365 CLI app needs the **`wids` optional access-token claim**.
  - **Tenant-wide admin consent** must be granted with the portal **"Grant admin consent"**
    button — the `adminconsent` URL grants per-user consent only.
  - A **stale CLI token cache** can cause false `403`s — clear it and re-login.
- **Preview:** the CLI and flow will change.

## What's in this folder
- `assets/agent365-langchain-onboard.mp4` — the 4-minute walkthrough recording.
- `assets/` — screenshots from the post *(to be added)*.

The agent code, scripts and full onboarding flow are in [DEV/](../../DEV/) at the repo root.

## References
- [Microsoft Agent 365 SDK overview](https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-sdk)
- [Get started with Agent 365 development](https://learn.microsoft.com/microsoft-agent-365/developer/get-started)
- [Agent 365 CLI setup guide](https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-cli)
- [Create an agent identity blueprint](https://learn.microsoft.com/entra/agent-id/create-blueprint)
