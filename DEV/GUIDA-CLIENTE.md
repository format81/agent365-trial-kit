# Guida cliente — Realizzare i due use case Agent 365 in un resource group Azure dedicato

Guida operativa passo-passo per simulare un cliente che, su una macchina di test pulita,
realizza i due use case documentati nel kit:

1. **Onboarding di un agente third-party (LangChain + Azure OpenAI) via Agent 365 SDK.**
2. **Lifecycle end-to-end via Agent 365 CLI:** blueprint (`a365 setup all`) → deploy → publish
   nell'admin center → cleanup.

> [!IMPORTANT]
> Microsoft Agent 365 (SDK + CLI) ed Entra Agent ID sono in **PREVIEW**: nomi pacchetti,
> comandi e opzioni possono cambiare. Testa in un tenant/subscription **non di produzione**.
> Verifica le opzioni con `a365 <comando> -h` per la tua versione installata.

---

## Parte 0 — Clone del repository sulla macchina di test

Il repo contiene video (`days/*/assets/*.mp4`) che lo rendono voluminoso. Per gli use case
serve solo la cartella `DEV/`: usa uno **sparse checkout** per scaricare esclusivamente quella,
saltando i binari pesanti.

```powershell
# 1. Posizionati dove vuoi clonare (es. C:\_F0rm4tC0de)
cd C:\
mkdir _F0rm4tC0de -Force
cd _F0rm4tC0de

# 2. Clona senza checkout dei file e senza scaricare i blob (li prende on-demand)
git clone --filter=blob:none --no-checkout https://github.com/format81/agent365-trial-kit.git
cd agent365-trial-kit

# 3. Attiva sparse-checkout (modalità cone) e prendi solo DEV/
git sparse-checkout init --cone
git sparse-checkout set DEV

# 4. Materializza i file ed entra nella cartella di lavoro
git checkout main
cd DEV
```

> Risultato: sul disco compaiono solo la root essenziale + `DEV/`; i `.mp4` sotto
> `days/*/assets/` non vengono mai scaricati.
>
> Se in seguito ti servisse anche altro (es. le query KQL): `git sparse-checkout set DEV kql`.
>
> Verifica branch, allineamento e che i video non siano presenti:
> ```powershell
> git status
> git rev-parse --abbrev-ref HEAD
> git sparse-checkout list
> Get-ChildItem -Recurse -Filter *.mp4   # non deve restituire nulla
> ```
>
> Il blobless clone (`--filter=blob:none`) richiede Git ≥ 2.19 e un server con supporto
> partial clone (GitHub lo supporta).

---

## Parte 1 — Prerequisiti (una volta sola, validi per entrambi gli use case)

**Cosa serve installato:** Python 3.10+, Azure CLI (`az`), .NET SDK 8+, Agent 365 CLI.

```powershell
# Dalla cartella DEV
.\scripts\00-Prerequisites.ps1 -Install
```

Questo verifica/installa `az`, `dotnet`, la Agent 365 CLI
(`dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli`) e le dipendenze Python.

> [!TIP]
> **PATH stantìo dopo un'installazione.** Se dopo aver installato `az`, `dotnet` o `a365`
> lo script continua a dire *not found*, la sessione PowerShell aperta ha il PATH vecchio.
> Apri una **nuova finestra** oppure ricarica il PATH nella sessione corrente:
> ```powershell
> $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
>             [System.Environment]::GetEnvironmentVariable("Path","User")
> ```
>
> **.NET: serve l'SDK, non solo il runtime.** Se `dotnet --list-sdks` è vuoto
> (`No SDKs were found`), installa l'SDK 8: `winget install --exact --id Microsoft.DotNet.SDK.8`.
>
> **Agent 365 CLI (`a365`) non trovata** anche dopo l'install: i global tool .NET stanno in
> `%USERPROFILE%\.dotnet\tools`. Installala e aggiungi quella cartella al PATH:
> ```powershell
> dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli
> $env:Path += ";$env:USERPROFILE\.dotnet\tools"
> a365 --version
> ```

**Ruoli Entra/Azure necessari sul tenant del cliente:**

| Ruolo | Serve per |
|-------|-----------|
| *Agent ID Developer* | creare il blueprint |
| *Global Administrator* | admin consent + upload manifest nell'admin center (altrimenti la CLI stampa un hand-off per il GA) |
| *Contributor* (subscription) | provisioning App Service |

**Configura le variabili dell'agente (Azure OpenAI):**

```powershell
Copy-Item .env.example .env
# Modifica .env:
#   AZURE_OPENAI_ENDPOINT   = https://<tuo-aoai>.openai.azure.com/
#   AZURE_OPENAI_DEPLOYMENT = gpt-4o   (o il tuo deployment chat)
#   AZURE_OPENAI_AUTH_MODE  = entra    (keyless, default — nessuna API key)
```

**(Opzionale) Crea in anticipo il resource group dedicato del cliente:**

```powershell
az group create -n rg-agent365-demo -l westeurope
```

**Seleziona il contesto Azure (tenant / subscription / resource group specifico):**

```powershell
.\scripts\01-Select-AzureContext.ps1
# Ti fa scegliere il tenant, la subscription e il RESOURCE GROUP (o ne crei uno nuovo).
# Scrive a365.config.json (nulla è hard-coded).
```

---

## Parte 2 — Use case 1: Onboarding agente third-party (LangChain + Azure OpenAI) via Agent 365 SDK

Obiettivo: prendere un agente LangChain già scritto e renderlo **cittadino di prima classe del
tenant** (Entra Agent ID + governance), in modalità keyless.

### 2.1 — Prova in locale (dev loop, opzionale ma consigliato)

```powershell
python -m pip install -r requirements.txt
python -m uvicorn src.app:app --reload --port 8000
# In un'altra shell, invia una richiesta:
#   POST http://localhost:8000/api/chat   body: {"message":"What time is it in UTC?"}
```

Codice agente: `src/agent.py` · host FastAPI: `src/app.py`.

### 2.2 — Concedi l'accesso keyless ad Azure OpenAI

Assegna il ruolo *Cognitive Services OpenAI User* al tuo utente (e alla Managed Identity):

```powershell
.\scripts\05-Grant-OpenAIAccess.ps1 -OpenAIName <nome-aoai> -GrantUser
```

### 2.3 — Deploy + onboarding automatico

Provisiona l'App Service nel resource group selezionato e registra l'agente in Agent 365:

```powershell
.\scripts\03-Deploy-AndOnboard.ps1 -OpenAIName <nome-aoai> -OpenAIResourceGroup <rg-aoai>
```

Cosa fa, in ordine:

1. Crea **App Service Plan + Web App (Python 3.11)** nel resource group scelto e deploya il codice.
2. Configura **Managed Identity keyless** verso Azure OpenAI (app settings + role assignment).
3. Esegue `a365 setup all --m365 --messaging-endpoint <url>` → **blueprint → permissions →
   agent identity → registrazione** (progresso live nella shell).
4. Esegue `a365 setup permissions bot` e `a365 publish` → genera `manifest/manifest.zip`.

Switch utili: `-DryRun` (anteprima), `-SkipInfra` (salta provisioning **e** deploy del codice),
`-SkipOnboard`, `-SkipPublish`.

> [!IMPORTANT]
> **Avvio lento su App Service B1.** Il primo import di LangChain è pesante e può superare il
> timeout di avvio del container (default 230s), causando
> *"Deployment failed because the site failed to start within 10 mins"*. Prima del deploy alza
> il limite e abilita Always On (le `az ... create` di plan/webapp sono idempotenti):
> ```powershell
> az webapp config appsettings set -n <app-name> -g <rg> `
>   --settings WEBSITES_CONTAINER_START_TIME_LIMIT=1800 SCM_DO_BUILD_DURING_DEPLOYMENT=true ENABLE_ORYX_BUILD=true `
>   --only-show-errors
> az webapp config set -n <app-name> -g <rg> --always-on true --only-show-errors
> ```
> Poi ridispiega ripetendo `03-Deploy-AndOnboard.ps1` **senza** `-SkipInfra`. Se il log runtime
> (`az webapp log tail -n <app-name> -g <rg>`) mostra invece un `Traceback`/`ModuleNotFoundError`,
> è un problema di build/deps, non di timeout.

**Se `setup blueprint` restituisce "Insufficient privileges":**

```powershell
.\scripts\06-Grant-BlueprintPermissions.ps1   # grant + admin-consent AgentIdentityBlueprint.ReadWrite.All
# Se manca il claim 'wids':
.\scripts\Add-WidsClaim.ps1
az logout; az login --use-device-code          # rinfresca il token con i nuovi consensi
```

### 2.4 — Gate di governance manuali (by design, non automatizzabili)

1. **Microsoft 365 admin center** → *Agents → Upload custom agent* → carica `manifest/manifest.zip`
   (serve *Global Administrator*).
2. **Teams Developer Portal** → configura il blueprint: Agent Type = *API Based*,
   **Notification URL = `/api/messages`** (⚠️ non `/api/chat`).
3. **Teams** → crea un'istanza dell'agente → un admin la approva. Solo ora nasce l'**Agent Identity**
   (prima il blueprint mostra *Agent identities: 0* — è normale). Richiede tenant iscritto al
   programma **Frontier**.

### 2.5 — Verifica

L'agente compare nel registry con il suo **Entra Agent ID** (identities 0 → 1).

---

## Parte 3 — Use case 2: Lifecycle end-to-end via Agent 365 CLI

Stesso kit, ma con vista sui **comandi CLI reali**: blueprint → deploy → publish → cleanup.

### 3.1 — (Opzionale) Solo blueprint, per vederlo esplicitamente

```powershell
.\scripts\02-New-AgentBlueprint.ps1            # aggiungi -DryRun per l'anteprima
# Sotto il cofano esegue:
#   a365 setup requirements     # check prerequisiti
#   a365 setup blueprint        # crea l'Entra Agent ID blueprint
```

### 3.2 — Blueprint completo + deploy (`a365 setup all`)

```powershell
.\scripts\03-Deploy-AndOnboard.ps1 -OpenAIName <nome-aoai> -OpenAIResourceGroup <rg-aoai>
# Esegue: a365 setup all --m365 --messaging-endpoint <url>
#         a365 setup permissions bot
```

Parametri: `-AuthMode obo|s2s|both` (default `obo` = delegato, senza ruoli app).

### 3.3 — Publish (genera il manifest)

Già incluso nello step precedente; per rieseguirlo isolato la CLI usa:

```powershell
a365 publish        # crea manifest/manifest.zip
```

Poi il manifest si carica **nell'admin center** (vedi Parte 2, step 2.4 punto 1).

### 3.4 — Cleanup end-to-end

Rimuove blueprint/istanza + App Service creati dal trial:

```powershell
# Anteprima non distruttiva
.\scripts\04-Cleanup.ps1 -Scope blueprint -DryRun

# Rimozione completa (Agent 365 + Azure) senza prompt
.\scripts\04-Cleanup.ps1 -Scope all -DeleteAppService -Force
```

Sotto il cofano richiama i comandi CLI reali:

```text
a365 cleanup            # blueprint + istanza + risorse Azure create dalla CLI
a365 cleanup azure      # App Service + App Service Plan
a365 cleanup blueprint  # app blueprint Entra + service principal
a365 cleanup instance   # identità/utente dell'istanza agente
```

---

## Scorciatoia: menu interattivo (copre entrambi gli use case)

```powershell
.\Invoke-Agent365Trial.ps1
# oppure salta a un singolo step:
.\Invoke-Agent365Trial.ps1 -Step prereqs      # 00
.\Invoke-Agent365Trial.ps1 -Step context      # 01 (tenant/sub/RG)
.\Invoke-Agent365Trial.ps1 -Step grant-openai # 05
.\Invoke-Agent365Trial.ps1 -Step blueprint    # 02
.\Invoke-Agent365Trial.ps1 -Step deploy       # 03
.\Invoke-Agent365Trial.ps1 -Step cleanup      # 04
```

---

## Watch-out da tenere presente

- Il broker **WAM può bloccarsi** → `$env:MSAL_DISABLE_BROKER=1` + `az login --use-device-code`.
- Notification URL deve essere `/api/messages`, **non** `/api/chat`.
- Il keyless richiede il ruolo **Cognitive Services OpenAI User** sull'Azure OpenAI
  (lo assegnano gli script 05 / 03).
- La creazione dell'istanza richiede il tenant iscritto a **Frontier**.
- Un **token cache CLI stantìo** può causare falsi `403` → pulisci e ri-esegui il login.
- Agent 365 (SDK + CLI) ed Entra Agent ID sono in **PREVIEW**: verifica le opzioni con
  `a365 <comando> -h`.
- File generati e git-ignored (mai committati): `.env`, `a365.config.json`,
  `a365.generated.config.json` (contiene il **client secret** del blueprint), cartella `manifest/`.

---

## Riferimenti

- Get started con Agent 365 — <https://learn.microsoft.com/microsoft-agent-365/developer/get-started>
- Agent 365 SDK — <https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-sdk>
- Agent 365 CLI — <https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-cli>
- CLI `setup` reference — <https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/setup>
- Publish agent — <https://learn.microsoft.com/microsoft-agent-365/developer/publish>
- Create agent instances — <https://learn.microsoft.com/microsoft-agent-365/developer/create-instance>
- Entra agent blueprint — <https://learn.microsoft.com/entra/agent-id/identity-platform/agent-blueprint>
