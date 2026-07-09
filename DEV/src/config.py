"""Centralized configuration loaded from environment variables / .env file.

Keeping configuration in one module makes the agent easy to reuse and to run
both locally and on Azure App Service.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

# Load a local .env when present (no-op on App Service where env vars are set).
load_dotenv()


def _get(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


@dataclass(frozen=True)
class AzureOpenAIConfig:
    """Azure OpenAI connection settings for the LangChain agent.

    Two authentication modes are supported:
      - "entra" (default): keyless auth using Microsoft Entra ID tokens. Works
        with 'az login', Managed Identity, or any DefaultAzureCredential source.
        Use this when API-key auth is disabled by policy on your resource.
      - "key": classic API-key auth (requires AZURE_OPENAI_API_KEY).

    Set AZURE_OPENAI_AUTH_MODE=key to opt back into API-key auth.
    """

    endpoint: str = field(default_factory=lambda: _get("AZURE_OPENAI_ENDPOINT"))
    api_key: str = field(default_factory=lambda: _get("AZURE_OPENAI_API_KEY"))
    deployment: str = field(default_factory=lambda: _get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o"))
    api_version: str = field(default_factory=lambda: _get("AZURE_OPENAI_API_VERSION", "2024-10-21"))
    auth_mode: str = field(
        default_factory=lambda: (_get("AZURE_OPENAI_AUTH_MODE", "entra") or "entra").lower()
    )
    credential_source: str = field(
        default_factory=lambda: (_get("AZURE_OPENAI_CREDENTIAL", "cli") or "cli").lower()
    )

    @property
    def use_entra(self) -> bool:
        """True when using keyless Microsoft Entra ID authentication."""
        # Default to Entra unless the user explicitly asked for key auth.
        if self.auth_mode == "key":
            return False
        return True

    def validate(self) -> None:
        required = {
            "AZURE_OPENAI_ENDPOINT": self.endpoint,
            "AZURE_OPENAI_DEPLOYMENT": self.deployment,
        }
        if not self.use_entra:
            required["AZURE_OPENAI_API_KEY"] = self.api_key

        missing = [key for key, value in required.items() if not value]
        if missing:
            raise RuntimeError(
                "Missing required Azure OpenAI settings: " + ", ".join(missing)
            )


@dataclass(frozen=True)
class AgentConfig:
    """Agent metadata and behavior."""

    name: str = field(default_factory=lambda: _get("AGENT_NAME", "Sample LangChain Agent"))
    instructions: str = field(
        default_factory=lambda: _get(
            "AGENT_INSTRUCTIONS",
            "You are a helpful enterprise assistant. Be concise and accurate.",
        )
    )


@dataclass(frozen=True)
class Agent365Config:
    """Microsoft Agent 365 (PREVIEW) settings.

    These are populated by the Agent 365 CLI 'config sync' after
    'a365 setup all' completes. Until then observability stays disabled.
    """

    tenant_id: str = field(default_factory=lambda: _get("A365_TENANT_ID"))
    blueprint_id: str = field(default_factory=lambda: _get("A365_BLUEPRINT_ID"))
    agent_id: str = field(default_factory=lambda: _get("A365_AGENT_ID"))
    client_id: str = field(default_factory=lambda: _get("A365_CLIENT_ID"))
    client_secret: str = field(default_factory=lambda: _get("A365_CLIENT_SECRET"))
    observability_enabled: bool = field(
        default_factory=lambda: _get("A365_OBSERVABILITY_ENABLED", "false").lower() == "true"
    )


# Singletons imported across the app.
azure_openai = AzureOpenAIConfig()
agent = AgentConfig()
agent365 = Agent365Config()

PORT = int(_get("PORT", "8000") or "8000")
