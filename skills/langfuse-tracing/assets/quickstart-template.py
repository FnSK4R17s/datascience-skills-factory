"""Langfuse v4 quickstart — minimal @observe + flush boilerplate."""

from langfuse import get_client, observe

# Env vars required: LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_BASE_URL


@observe()
def my_pipeline(query: str) -> str:
    """Top-level function becomes a trace. Nested calls become spans."""
    context = retrieve(query)
    return generate(query, context)


@observe()
def retrieve(query: str) -> str:
    """This becomes a child span under my_pipeline."""
    # Your retrieval logic here
    return "relevant context"


@observe(as_type="generation")
def generate(query: str, context: str) -> str:
    """This becomes a generation observation (tracks model, tokens, cost)."""
    # Your LLM call here
    return f"Answer based on: {context}"


if __name__ == "__main__":
    result = my_pipeline("What is Langfuse?")
    print(result)

    # CRITICAL: flush before exit in scripts/serverless
    get_client().flush()
