# Client Guide — Deploy the LangChain agent as a container and onboard it to Microsoft Agent 365

Step-by-step guide to reproduce, on a clean test machine, the two documented use cases —
using the **container (Docker) deployment path** as the primary, reliable method:

1. **Onboard a third-party agent (LangChain + Azure OpenAI) via the Agent 365 SDK.**
2. **End-to-end lifecycle via the Agent 365 CLI:** blueprint (`a365 setup all`) → deploy →
   publish in the admin center → cleanup.

The container path builds an image server-side with `az acr build` (no local Docker needed) and
runs it on **Azure Web App for Containers**. It avoids the Oryx zip-deploy pitfalls (Windows
backslash paths → `ModuleNotFoundError: No module named 'src'`, virtualenv extraction, slow B1
cold starts). The messaging endpoint stays on `*.azurewebsites.net`, so the Agent 365 onboarding
flow is unchanged.

> [!IMPORTANT]
> Microsoft Agent 365 (SDK + CLI) and Entra Agent ID are in **PREVIEW**: package names, commands
> and options can change. Test in a **non-production** tenant/subscription. Verify options with
> `a365 <command> -h` for your installed version.

> [!TIP]
> Run the PowerShell scripts with **PowerShell 7+ (`pwsh`)** when possible. They also work on
> Windows PowerShell 5.1 (the context script handles 5.1's `ConvertFrom-Json` quirks), but 7+ is
> recommended.

---

## Part 0 — Clone the repository on the test machine

The repo contains videos (`days/*/assets/*.mp4`) that make it large. You only need the `DEV/`
folder: use a **sparse checkout** to fetch just that and skip the heavy binaries.

```powershell
# 1. Go where you want to clone (e.g. C:\code)
cd C:\
mkdir code -Force
cd code

# 2. Clone without checking out files and without downloading blobs (fetched on demand)
git clone --filter=blob:none --no-checkout https://github.com/format81/agent365-trial-kit.git
cd agent365-trial-kit

# 3. Enable sparse-checkout (cone mode) and take only DEV/
git sparse-checkout init --cone
git sparse-checkout set DEV

# 4. Materialize the files and enter the working folder
git checkout main
cd DEV
```

> Result: only the essential root + `DEV/` land on disk; the `.mp4` files under
> `days/*/assets/` are never downloaded.
>
> If you later need more (e.g. the KQL queries): `git sparse-checkout set DEV kql`.
>
> Verify branch, sync, and that no videos are present:
> ```powershell
> git status
> git rev-parse --abbrev-ref HEAD
> git sparse-checkout list
> Get-ChildItem -Recurse -Filter *.mp4   # should return nothing
> ```
>
> The blobless clone (`--filter=blob:none`) needs Git ≥ 2.19 and a server with partial-clone
> support (GitHub supports it).

---

## Part 1 — Prerequisites (once, valid for both use cases)

**Required:** Python 3.10+, Azure CLI (`az`), .NET SDK 8+, Agent 365 CLI.
For the container path you do **not** need local Docker — images are built in the cloud with
`az acr build`.

```powershell
# From the DEV folder
.\scripts\00-Prerequisites.ps1 -Install
```

This checks/installs `az`, `dotnet`, the Agent 365 CLI
(`dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli`) and the Python dependencies.

> [!TIP]
> **Stale PATH after an install.** If, after installing `az`, `dotnet` or `a365`, a script still
> says *not found*, the open PowerShell session has the old PATH. Open a **new window** or reload
> the PATH in the current session:
> ```powershell
> $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
>             [System.Environment]::GetEnvironmentVariable("Path","User")
> ```
>
> **.NET: you need the SDK, not just the runtime.** If `dotnet --list-sdks` is empty
> (`No SDKs were found`), install SDK 8: `winget install --exact --id Microsoft.DotNet.SDK.8`.
>
> **Agent 365 CLI (`a365`) not found** even after install: .NET global tools live in
> `%USERPROFILE%\.dotnet\tools`. Install it and add that folder to PATH:
> ```powershell
> dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli
> $env:Path += ";$env:USERPROFILE\.dotnet\tools"
> a365 --version
> ```

**Entra/Azure roles needed on the client tenant:**

| Role | Needed for |
|------|------------|
| *Agent ID Developer* | creating the blueprint |
| *Global Administrator* | admin consent + uploading the manifest in the admin center (otherwise the CLI prints a GA hand-off) |
| *Contributor* (subscription) | provisioning ACR / App Service |
| *Owner* or *User Access Administrator* | assigning the Azure OpenAI data-plane role (keyless) |

**Configure the agent variables (Azure OpenAI):**

```powershell
Copy-Item .env.example .env
# Edit .env:
#   AZURE_OPENAI_ENDPOINT   = https://<your-aoai>.openai.azure.com/
#   AZURE_OPENAI_DEPLOYMENT = gpt-4o   (or your chat deployment)
#   AZURE_OPENAI_AUTH_MODE  = entra    (keyless, default — no API key)
```

> `.env` is used for the **local dev loop** (2.1) only. For the deployed **container** these
> values are set as **App Settings** on the Web App by `07-Deploy-Container.ps1` (the endpoint is
> resolved from `-OpenAIName`); `.env` is never baked into the image.

**(Optional) Pre-create the dedicated resource group:**

```powershell
az group create -n rg-agent365-demo -l westeurope
```

**Select the Azure context (tenant / subscription / specific resource group):**

```powershell
.\scripts\01-Select-AzureContext.ps1
# Lets you pick the tenant, subscription and RESOURCE GROUP (or create a new one).
# Writes a365.config.json (nothing is hard-coded).
```

---

## Part 2 — Use case 1: Deploy the agent as a container and onboard it via the Agent 365 SDK

Goal: take an existing LangChain agent, run it as a container, and make it a **first-class tenant
citizen** (Entra Agent ID + governance) with keyless auth.

### 2.1 — Run locally first (optional dev loop)

```powershell
python -m pip install -r requirements.txt
python -m uvicorn src.app:app --reload --port 8000
# browser: http://localhost:8000/docs   (Swagger UI — try POST /api/chat)
```

Agent code: `src/agent.py` · FastAPI host: `src/app.py`.

### 2.2 — Deploy the container (primary path)

Builds the image in ACR and runs it on Web App for Containers, wiring keyless Azure OpenAI via
Managed Identity:

```powershell
.\scripts\07-Deploy-Container.ps1 -OpenAIName <aoai-name> -OpenAIResourceGroup <aoai-rg> -OpenAIDeployment gpt-4o
```

**How to fill in the parameters:**

| Parameter | What it is | Example |
|-----------|------------|---------|
| `-OpenAIName` | The **Azure OpenAI resource name** (the account name, *not* the endpoint URL). From endpoint `https://demomaire.openai.azure.com/` the name is `demomaire`. | `demomaire` |
| `-OpenAIResourceGroup` | The resource group **that contains that Azure OpenAI resource** (may differ from the app's RG). | `rg-agent365-demo` |
| `-OpenAIDeployment` | The **model deployment name** you created in that resource (chat model, e.g. gpt-4o). | `gpt-4o` |

Discover the exact values with:

```powershell
# List all Azure OpenAI resources you can see: name + resource group + endpoint
az cognitiveservices account list `
  --query "[?kind=='OpenAI'].{name:name, rg:resourceGroup, endpoint:properties.endpoint}" -o table

# List the model deployments on that resource (pick the chat deployment name)
az cognitiveservices account deployment list -n <aoai-name> -g <aoai-rg> `
  --query "[].{name:name, model:properties.model.name}" -o table
```

Worked example — if the portal shows an endpoint like
`https://demomaire.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=...`,
then `-OpenAIName demomaire`, `-OpenAIDeployment gpt-4o`, and `-OpenAIResourceGroup` is the RG that
`az cognitiveservices account list` reports for `demomaire`. Full command:

```powershell
.\scripts\07-Deploy-Container.ps1 -OpenAIName demomaire -OpenAIResourceGroup rg-agent365-demo -OpenAIDeployment gpt-4o
```

> If your resource is an **Azure AI Foundry** resource (endpoint `...services.ai.azure.com/...`),
> use the resource **name** for `-OpenAIName` and confirm the `.openai.azure.com` endpoint with
> `az cognitiveservices account show -n <name> -g <rg> --query properties.endpoint -o tsv`. Do not
> pass the `/api/projects/...` project URL.

What it does, in order:

1. Creates an **Azure Container Registry** (Basic, admin disabled).
2. `az acr build` builds and pushes the image from `DEV/Dockerfile` (server-side build).
3. Creates an **App Service Plan (Linux) + Web App for Containers**.
4. Enables the **system-assigned Managed Identity**, grants it **AcrPull**, and pulls the image
   with the MI (no credentials, no secrets).
5. Sets keyless app settings (`AZURE_OPENAI_ENDPOINT/DEPLOYMENT/AUTH_MODE=entra`,
   **`AZURE_OPENAI_CREDENTIAL=managed`**) and grants *Cognitive Services OpenAI User* to the MI.
6. Writes `scripts/last-container-deploy.json` for cleanup and prints the endpoints.

> [!TIP]
> `AZURE_OPENAI_CREDENTIAL=managed` is **essential**: inside the container
> `DefaultAzureCredential` excludes the Managed Identity by default, so it must be forced. The
> script sets it for you.

Useful switches: `-DryRun`, `-SkipOpenAI` (host only), `-AcrName` (reuse an ACR), `-ImageTag`.

> Where the Azure OpenAI endpoint is configured: you do **not** edit `.env` for the container.
> The script resolves `AZURE_OPENAI_ENDPOINT` from `-OpenAIName` and sets it (plus
> `AZURE_OPENAI_DEPLOYMENT`, `AZURE_OPENAI_AUTH_MODE=entra`, `AZURE_OPENAI_CREDENTIAL=managed`) as
> **App Settings** on the Web App. Change them later with
> `az webapp config appsettings set -n <app> -g <rg> --settings AZURE_OPENAI_...=...`.

### 2.3 — Test the agent

The script prints the app name/URL. Test from the browser or the terminal:

```powershell
$app = "<app-name-printed-by-the-script>"
Invoke-RestMethod "https://$app.azurewebsites.net/health"     # {"status":"healthy"}

$body = @{ message = "What time is it in UTC?" } | ConvertTo-Json
Invoke-RestMethod "https://$app.azurewebsites.net/api/chat" -Method Post -ContentType "application/json" -Body $body
# expected: { "reply": "The current time in UTC is ..." }
```

Swagger UI (interactive `POST /api/chat` from the browser): `https://<app>.azurewebsites.net/docs`.

> `/health` and `/docs` work as soon as the container starts. `/api/chat` also needs the Azure
> OpenAI app settings + the MI role (step 2.2 configures both). A **500** usually means a missing
> app setting; **401/403** from the model means the role assignment hasn't propagated yet.

### 2.4 — Onboard to Agent 365

Use the `Messaging URL` printed by the deploy script:

```powershell
a365 setup all --m365 --messaging-endpoint https://<app>.azurewebsites.net/api/messages
a365 setup permissions bot
a365 publish        # creates manifest/manifest.zip
```

**If `setup blueprint` returns "Insufficient privileges":**

```powershell
.\scripts\06-Grant-BlueprintPermissions.ps1   # grant + admin-consent AgentIdentityBlueprint.ReadWrite.All
# If the 'wids' claim is missing:
.\scripts\Add-WidsClaim.ps1
az logout; az login --use-device-code          # refresh the token with the new consent
```

### 2.5 — Manual governance gates (by design, not automatable)

1. **Microsoft 365 admin center** → *Agents → Upload custom agent* → upload `manifest/manifest.zip`
   (requires *Global Administrator*).
2. **Teams Developer Portal** → configure the blueprint: Agent Type = *API Based*,
   **Notification URL = `/api/messages`** (⚠️ not `/api/chat`).
3. **Teams** → create an agent instance → an admin approves it. Only then is the **Agent Identity**
   created (a fresh blueprint shows *Agent identities: 0* — that's expected). Requires the tenant
   enrolled in **Frontier**.

### 2.6 — Verify

The agent appears in the registry with its **Entra Agent ID** (identities 0 → 1).

---

## Part 3 — Use case 2: End-to-end lifecycle via the Agent 365 CLI

Same kit, viewed through the **real CLI commands**: blueprint → deploy → publish → cleanup.

> [!NOTE]
> This is the **same single deployment** as Part 2, seen from the CLI angle — you do **not** deploy
> a second container. If you already ran `07-Deploy-Container.ps1` in Part 2, reuse that app and
> skip 3.2's deploy line.

### 3.1 — (Optional) Blueprint only, made explicit

```powershell
.\scripts\02-New-AgentBlueprint.ps1            # add -DryRun to preview
# Under the hood:
#   a365 setup requirements     # prerequisite check
#   a365 setup blueprint        # create the Entra Agent ID blueprint
```

### 3.2 — Deploy (container) + blueprint

Skip the first line if you already deployed in Part 2 — just reuse the same app URL:

```powershell
# Only if not already deployed in Part 2:
.\scripts\07-Deploy-Container.ps1 -OpenAIName <aoai-name> -OpenAIResourceGroup <aoai-rg> -OpenAIDeployment gpt-4o

# Then, against the (already deployed) app:
a365 setup all --m365 --messaging-endpoint https://<app>.azurewebsites.net/api/messages
a365 setup permissions bot
```

### 3.3 — Publish (generate the manifest)

Included above; to run it in isolation:

```powershell
a365 publish        # creates manifest/manifest.zip
```

Then upload the manifest **in the admin center** (see Part 2.5, item 1).

### 3.4 — Cleanup

See Part 4.

---

## Part 4 — Cleanup

### 4.1 — Container resources (Web App + Plan + ACR)

```powershell
# Reads scripts/last-container-deploy.json and removes everything the deploy created
.\scripts\08-Cleanup-Container.ps1 -Force

# Preview / explicit names / keep a shared ACR
.\scripts\08-Cleanup-Container.ps1 -DryRun
.\scripts\08-Cleanup-Container.ps1 -AppName <app> -PlanName <plan> -AcrName <acr> -Force
.\scripts\08-Cleanup-Container.ps1 -KeepAcr -Force
```

> Tested end-to-end on `rg-agent365-demo`: image build+push, Web App for Containers, keyless via
> Managed Identity, `/api/chat` returns 200, and cleanup removes every resource.

### 4.2 — Agent 365 / Entra resources (blueprint, instance)

```powershell
# Preview first
.\scripts\04-Cleanup.ps1 -Scope blueprint -DryRun

# Remove the Agent 365 side
.\scripts\04-Cleanup.ps1 -Scope all -Force
```

Under the hood it calls the real CLI:

```text
a365 cleanup            # blueprint + instance + Azure resources created by the CLI
a365 cleanup blueprint  # Entra blueprint app + service principal
a365 cleanup instance   # agent instance identity + user
```

---

## How the container uses Azure OpenAI (keyless)

The agent uses `AzureChatOpenAI` with `DefaultAzureCredential`. The identity source depends on
where it runs:

| Where it runs | Identity | How |
|---------------|----------|-----|
| Local (`docker run` / uvicorn) | your `az login` | set `AZURE_OPENAI_CREDENTIAL=cli` (or use an API key with `AZURE_OPENAI_AUTH_MODE=key`) |
| Web App for Containers | the app's **Managed Identity** | `AZURE_OPENAI_CREDENTIAL=managed` (set by the deploy script) |

No secrets live in the image. The deploy script grants the MI the *Cognitive Services OpenAI User*
role on the Azure OpenAI resource, and the runtime fetches Entra tokens automatically.

---

## Appendix — Legacy zip/Oryx path (App Service, Python runtime)

The original path deploys the raw code and lets Oryx build it. It works but is more fragile than
the container path. Use `03-Deploy-AndOnboard.ps1` if you specifically need it:

```powershell
.\scripts\05-Grant-OpenAIAccess.ps1 -OpenAIName <aoai-name> -GrantUser
.\scripts\03-Deploy-AndOnboard.ps1 -OpenAIName <aoai-name> -OpenAIResourceGroup <aoai-rg>
```

Known watch-outs on this path:
- **Windows zip creates backslash paths** → the app crashes with `No module named 'src'`. Fixed in
  the kit (`New-DeploymentZip` writes forward-slash entries), but only via the script.
- **Slow B1 cold start** may exceed the container start timeout. Raise it and enable Always On:
  ```powershell
  az webapp config appsettings set -n <app> -g <rg> --settings WEBSITES_CONTAINER_START_TIME_LIMIT=1800 --only-show-errors
  az webapp config set -n <app> -g <rg> --always-on true --only-show-errors
  ```

---

## Watch-outs

- The **WAM broker can hang** → `$env:MSAL_DISABLE_BROKER=1` + `az login --use-device-code`.
- Notification URL must be `/api/messages`, **not** `/api/chat`.
- Keyless needs **Cognitive Services OpenAI User** on the Azure OpenAI resource (scripts 07 / 05 / 03
  assign it).
- Creating an instance requires the tenant enrolled in **Frontier**.
- A **stale CLI token cache** can cause false `403`s → clear it and re-login.
- If the SCM/deploy endpoint returns **403** on App Service, check `publicNetworkAccess` and SCM
  access restrictions on the site.
- Agent 365 (SDK + CLI) and Entra Agent ID are in **PREVIEW**: verify options with `a365 <command> -h`.
- Generated, git-ignored files (never committed): `.env`, `a365.config.json`,
  `a365.generated.config.json` (contains the blueprint **client secret**), `manifest/`,
  `scripts/last-container-deploy.json`.

---

## References

- Get started with Agent 365 — <https://learn.microsoft.com/microsoft-agent-365/developer/get-started>
- Agent 365 SDK — <https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-sdk>
- Agent 365 CLI — <https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-cli>
- CLI `setup` reference — <https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/setup>
- Publish agent — <https://learn.microsoft.com/microsoft-agent-365/developer/publish>
- Create agent instances — <https://learn.microsoft.com/microsoft-agent-365/developer/create-instance>
- Web App for Containers — <https://learn.microsoft.com/azure/app-service/quickstart-custom-container>
- Entra agent blueprint — <https://learn.microsoft.com/entra/agent-id/identity-platform/agent-blueprint>
