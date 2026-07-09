"""A minimal, reusable LangChain agent backed by Azure OpenAI.

The agent uses tool calling so you can extend it with your own tools. Swap in
Agent 365 Work IQ tools (Mail, Calendar, SharePoint, Teams, ...) once your
blueprint grants them - see:
https://learn.microsoft.com/microsoft-agent-365/developer/tooling
"""
from __future__ import annotations

from datetime import datetime, timezone

from langchain.agents import AgentExecutor, create_tool_calling_agent
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.tools import tool
from langchain_openai import AzureChatOpenAI

from .config import agent as agent_cfg
from .config import azure_openai as aoai_cfg


# --------------------------------------------------------------------------
# Tools - replace / extend these with real business tools or Work IQ tools.
# --------------------------------------------------------------------------
@tool
def get_utc_time() -> str:
    """Return the current UTC time in ISO 8601 format."""
    return datetime.now(timezone.utc).isoformat()


@tool
def echo(text: str) -> str:
    """Echo the provided text back to the caller (useful as a connectivity test)."""
    return text


DEFAULT_TOOLS = [get_utc_time, echo]


def _build_credential(source: str):
    """Return an Azure credential based on the configured source.

    - "cli"     : AzureCliCredential - uses your 'az login' user. Best for local
                  dev, and avoids picking up an ambient Managed Identity.
    - "managed" : ManagedIdentityCredential - the App Service Managed Identity.
    - "default" : DefaultAzureCredential - tries several sources in order.
    """
    source = (source or "default").lower()
    if source == "cli":
        from azure.identity import AzureCliCredential

        return AzureCliCredential()
    if source == "managed":
        from azure.identity import ManagedIdentityCredential

        return ManagedIdentityCredential()

    # "default": in local dev, exclude the ambient Managed Identity so the token
    # comes from your az login session; on App Service, MI is used explicitly
    # by setting AZURE_OPENAI_CREDENTIAL=managed.
    from azure.identity import DefaultAzureCredential

    return DefaultAzureCredential(exclude_managed_identity_credential=True)


def build_llm() -> AzureChatOpenAI:
    """Create the Azure OpenAI chat model used by the agent.

    Uses keyless Microsoft Entra ID authentication by default (works with
    'az login' or a Managed Identity on Azure App Service). Falls back to
    API-key auth when AZURE_OPENAI_AUTH_MODE=key.
    """
    aoai_cfg.validate()

    common = dict(
        azure_endpoint=aoai_cfg.endpoint,
        azure_deployment=aoai_cfg.deployment,
        api_version=aoai_cfg.api_version,
        temperature=0.2,
    )

    if aoai_cfg.use_entra:
        # Keyless: acquire Entra ID bearer tokens for Azure OpenAI (Cognitive
        # Services scope). The credential source is selectable so local dev can
        # force 'az login' (your user) while App Service uses Managed Identity.
        from azure.identity import get_bearer_token_provider

        token_provider = get_bearer_token_provider(
            _build_credential(aoai_cfg.credential_source),
            "https://cognitiveservices.azure.com/.default",
        )
        return AzureChatOpenAI(azure_ad_token_provider=token_provider, **common)

    # Classic API-key auth (only when explicitly requested).
    return AzureChatOpenAI(api_key=aoai_cfg.api_key, **common)


def build_agent(tools=None) -> AgentExecutor:
    """Build a reusable LangChain tool-calling agent executor."""
    tools = tools if tools is not None else DEFAULT_TOOLS

    prompt = ChatPromptTemplate.from_messages(
        [
            ("system", agent_cfg.instructions),
            ("placeholder", "{chat_history}"),
            ("human", "{input}"),
            ("placeholder", "{agent_scratchpad}"),
        ]
    )

    llm = build_llm()
    agent = create_tool_calling_agent(llm, tools, prompt)
    return AgentExecutor(agent=agent, tools=tools, verbose=False)


def run_once(message: str, chat_history=None) -> str:
    """Convenience helper: run the agent for a single user message."""
    executor = build_agent()
    result = executor.invoke({"input": message, "chat_history": chat_history or []})
    return result.get("output", "")


if __name__ == "__main__":
    # Simple local smoke test: python -m src.agent
    print(run_once("What time is it in UTC right now?"))
