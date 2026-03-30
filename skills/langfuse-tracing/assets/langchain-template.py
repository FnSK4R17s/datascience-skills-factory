"""Langfuse v4 + LangChain/LangGraph integration template."""

from langfuse import Langfuse, get_client, observe, propagate_attributes
from langfuse.langchain import CallbackHandler
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage

# Initialize Langfuse singleton
Langfuse()


def get_handler() -> CallbackHandler:
    """Create a callback handler that inherits the current trace context."""
    return CallbackHandler()


# --- Pattern 1: Simple LangChain chain ---

@observe()
def ask_question(question: str) -> str:
    """Wrapping in @observe groups all LangChain calls under one trace."""
    llm = ChatOpenAI(model="gpt-4o")
    handler = get_handler()

    response = llm.invoke(
        [HumanMessage(content=question)],
        config={"callbacks": [handler]},
    )
    return response.content


# --- Pattern 2: LangGraph agent with user/session tracking ---

@observe()
def run_agent(query: str, user_id: str, session_id: str) -> str:
    """LangGraph agent with full trace metadata."""
    from langgraph.prebuilt import create_react_agent

    llm = ChatOpenAI(model="gpt-4o")
    agent = create_react_agent(llm, tools=[])
    handler = get_handler()

    with propagate_attributes(user_id=user_id, session_id=session_id):
        result = agent.invoke(
            {"messages": [HumanMessage(content=query)]},
            config={"callbacks": [handler]},
        )

    messages = result.get("messages", [])
    return messages[-1].content if messages else ""


# --- Pattern 3: Multiple LangChain calls in one trace ---

@observe()
def multi_step(topic: str) -> str:
    """Multiple LLM calls grouped under one trace."""
    llm = ChatOpenAI(model="gpt-4o")
    handler = get_handler()

    # Step 1: generate outline
    outline = llm.invoke(
        [HumanMessage(content=f"Create an outline about {topic}")],
        config={"callbacks": [handler]},
    ).content

    # Step 2: expand each section
    expanded = llm.invoke(
        [HumanMessage(content=f"Expand this outline:\n{outline}")],
        config={"callbacks": [handler]},
    ).content

    return expanded


if __name__ == "__main__":
    result = ask_question("What is observability?")
    print(result)
    get_client().flush()
