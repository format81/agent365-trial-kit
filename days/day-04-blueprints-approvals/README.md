# Day 4 — Blueprints and approvals: governance that ships with the agent

**Govern** · Published 24 Jul · [Read the LinkedIn post](https://www.linkedin.com/posts/antonioformato_11daysofagent365-agent365-aisecurity-ugcPost-7486328753166565376-a0VW/)

> Part of [11 Days of Agent 365](../../README.md). Personal project, tested on my own
> tenant — not official Microsoft content. Preview features may change.

## Walkthrough (2m18)
▶️ [Watch on LinkedIn](POST_URL_PLACEHOLDER) · [Download the recording](assets/agent365-policy-template-approval.mp4)

## The problem
Side-door publishing. A maker builds something useful, publishes it, and then the DLP
policy, the access restrictions and the logging get added afterwards — if anyone
remembers. The agent is already live, already reading data and already acting on the
business before any control is wrapped around it. Governance applied after the fact
arrives after the incident: by the time the policy catches up, the exposure has already
happened.

## What Agent 365 does about it
Governance becomes a property of the object, not a later checklist. Two distinct objects
carry it, and they are easy to confuse:

- **Agent identity blueprint (Microsoft Entra)** — the mould for a family of agents. It
  holds credentials, authentication settings and inheritable permissions. It can perform
  exactly one operation in the tenant: create or delete agent identities. A blueprint
  can't act independently to access resources; the actual work is always done by the
  agent identity it produces.
- **Agent 365 template (Microsoft 365 admin center › Agents › Settings › Templates)** —
  a collection of predefined governance and security policies that bundles Microsoft
  Entra, Purview, SharePoint Online and Defender protections. It's selected from a
  dropdown when an agent is activated. Templates standardize governance and reduce manual
  configuration.

The gate is the point. A user requests an agent and it does **not** go live — it lands in
the **Requests** queue. Developers must declare the Microsoft Graph permissions in the
blueprint; when an admin activates it, the portal reviews those declared permissions and
prompts the admin to consent. Only an **AI Administrator** or **Global Administrator** can
approve requests or assign ownership.

## Try it yourself
1. In the **Microsoft 365 admin center**, go to **Agents › Settings › Templates** and
   review which Entra, Purview, SharePoint and Defender policies a template bundles.
2. As a **non-admin maker**, request an agent from the Teams or Microsoft 365 store.
3. As **AI Administrator**, open **Agents › Overview** and find the **"Pending requests
   for agents"** card; select **Manage requests** to reach **All agents › Requests**.
4. Review the pending request — capabilities, connected tools, data sources and
   permissions.
5. **Consent** to the blueprint's Microsoft Graph permissions when prompted.
6. **Activate**, choosing a template from the dropdown (custom templates and Microsoft
   defaults both appear).
7. Open the resulting agent and check the **inherited policies** on its blade.
8. **Delete the demo agent** afterwards — it goes live on approval.

## Watch-outs
- **Template changes are not retroactive.** An updated template applies to new activations
  only; agents already approved keep the old rules. The governance baseline drifts over
  time, so plan a separate re-attestation (access reviews) — the template alone isn't
  enough.
- **Custom policies aren't supported yet.** Adding a new template shows it as locked and
  blocks creating another. Applying Entra custom policies requires an Agent 365 license.
- **AI template scenarios are PREVIEW** and available only to **Frontier** tenants.
- **Permission inheritance isn't automatic.** Permissions cascade only when the resource
  is explicitly marked inheritable, and Required Resource Access on a blueprint is a
  request list, not a grant.
- **A blueprint-scoped policy covers agent identities, not agent user accounts** — those
  need separate scoping. (More on this on Day 7.)
- **Sponsors on a blueprint** can be users, dynamic membership groups or Microsoft 365
  groups; security groups and role-assignable groups are not supported.
- **The agent goes live on approval** — clean up demo agents or they pollute the registry.

## What's in this folder
- `assets/agent365-policy-template-approval.mp4` — 2m18 walkthrough: template contents,
  the request, the admin review and Microsoft Graph permission consent, activation with
  template selection, and the inherited policies on the resulting agent.

## References
- [Agent templates](https://learn.microsoft.com/microsoft-agent-365/admin/agent-template)
- [Create an agent identity blueprint](https://learn.microsoft.com/entra/agent-id/create-blueprint)
- [Agent overview in the Microsoft 365 admin center](https://learn.microsoft.com/microsoft-365/admin/manage/agent-365-overview)
- [Set up an agent blueprint (developer registration)](https://learn.microsoft.com/microsoft-agent-365/developer/registration)
