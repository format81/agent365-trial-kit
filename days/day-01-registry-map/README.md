# Day 1 — One registry, and the map of what agents touch

**Observe** · Published Tue 21 Jul · [Read the LinkedIn post](https://www.linkedin.com/posts/antonioformato_11daysofagent365-agent365-aisecurity-ugcPost-7485242937346424833-nh3R/)

> Part of [11 Days of Agent 365](../../README.md). Personal project, tested on my own
> tenant — not official Microsoft content. Preview features may change.

## Walkthrough (2m30)
▶️ [Watch on LinkedIn](https://www.linkedin.com/posts/antonioformato_11daysofagent365-agent365-aisecurity-ugcPost-7485242937346424833-nh3R/) · [Download the recording](assets/walkthrough.mp4)

## The problem
Agent inventory is scattered across portals and spreadsheets. Copilot Studio has its
list, third-party platforms have theirs, and someone's manually maintained tracker is
already out of date. You can't govern what you can't see — and right now there's no
single place that shows every agent, who owns it, and whether it's managed.

## What Agent 365 does about it
Agent 365 gives you **one unified registry** — every agent under a single metadata
model, continuously updated. At the top, three counters frame the estate at a glance:
**total agents**, **agents without owners**, and **unmanaged agents**. Filters let you
slice the list, and the **agent details pane** shows the full picture for any single
agent — including third-party agents such as **Salesforce Agentforce (PREVIEW)** sitting
right alongside native Microsoft agents. From there, **Agent Map** traces an agent out
to the people, tools, and data it touches, and lets you drill any node down to its
config and logs. The registry is the single, continuously updated source of truth for
your agent estate.

## Try it yourself
1. Open the **Microsoft 365 admin center** and go to **Agents › All agents › Registry**.
2. Read the three counters at the top: **Total**, **Without owners**, **Unmanaged**.
3. Use the **filters** to narrow the list (owner, management state, source platform).
4. Open an agent's **details pane** to inspect its metadata, owner, and source.
5. Open **Agent Map** and **drill a node** down to its config and logs.
6. Select an agent and **Assign owner**.
7. Try **Block agent** — then **cancel at the confirmation** (don't actually block it).
8. **Export to CSV** for offline review or a point-in-time snapshot.

## Watch-outs
- **Seed 24–48h of activity from several users first** — otherwise Agent Map looks empty
  because there are no interactions to graph.
- **Draft agents currently show only from Copilot Studio.** Drafts created elsewhere may
  not appear yet.
- **Filters don't change the Total counter** — Total always reflects the whole estate,
  even when the list below is filtered.
- **Registry-sync** and **third-party-agent** surfaces (e.g. Salesforce Agentforce) are
  **PREVIEW** and may change or break.

## What's in this folder
- `assets/walkthrough.mp4` — 2m30 screen recording of the registry, counters, filters,
  details pane, and Agent Map walkthrough (also on LinkedIn, linked above).
- `assets/.gitkeep` — placeholder so the assets folder is tracked by git.
- `technical/` — scripts, KQL, configs supporting this scenario.

## References
- [Manage agent registry in the Microsoft 365 admin center](https://learn.microsoft.com/en-us/microsoft-agent-365/)
- [Agent Registry convergence with Microsoft Agent 365](https://learn.microsoft.com/en-us/microsoft-agent-365/)
- [Use Agent Map in the Microsoft 365 admin center](https://learn.microsoft.com/en-us/microsoft-agent-365/)
