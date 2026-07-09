"""Optional Microsoft Agent 365 observability wiring (PREVIEW).

Agent 365 provides OpenTelemetry-based observability that makes every agent
interaction visible in the Microsoft 365 admin center and connected security
tools (Entra, Purview, Defender). For agents built on OpenAI, LangChain or the
Microsoft Agent Framework, auto-instrumentation is available.

This module isolates that dependency so the agent still runs when the preview
SDK isn't installed yet. Enable it by:
  1. installing the preview packages (see requirements.txt), and
  2. setting A365_OBSERVABILITY_ENABLED=true after 'a365 setup all' has filled
     in the A365_* environment variables.

Docs: https://learn.microsoft.com/microsoft-agent-365/developer/observability
"""
from __future__ import annotations

import logging

from .config import agent365

logger = logging.getLogger("agent365.observability")


def try_enable_observability() -> bool:
    """Best-effort initialization of Agent 365 observability.

    Returns True if instrumentation was enabled, False otherwise. Never raises,
    so a missing preview package can't take the agent down.
    """
    if not agent365.observability_enabled:
        logger.info("Agent 365 observability disabled (A365_OBSERVABILITY_ENABLED != true).")
        return False

    try:
        # PREVIEW imports. The exact module surface may change between SDK
        # versions; this mirrors the current Agent 365 SDK guidance.
        from microsoft_agents_a365.observability.core import BaggageBuilder  # type: ignore

        # Attach tenant/agent identifiers to every telemetry span so admins can
        # correlate this agent's activity in Agent 365.
        BaggageBuilder().tenant_id(agent365.tenant_id).agent_id(agent365.agent_id).build()

        logger.info(
            "Agent 365 observability enabled for agent_id=%s (blueprint=%s).",
            agent365.agent_id or "<unset>",
            agent365.blueprint_id or "<unset>",
        )
        return True
    except ImportError:
        logger.warning(
            "Agent 365 SDK not installed. Install the preview packages in "
            "requirements.txt to enable observability."
        )
        return False
    except Exception:  # noqa: BLE001 - never fail the agent because of telemetry
        logger.exception("Failed to enable Agent 365 observability; continuing without it.")
        return False
