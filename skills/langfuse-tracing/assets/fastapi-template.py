"""Langfuse v4 + FastAPI integration template."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from langfuse import Langfuse, get_client, observe, propagate_attributes


# Initialize Langfuse singleton at module level
Langfuse()


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    # Flush all pending traces on shutdown
    get_client().shutdown()


app = FastAPI(lifespan=lifespan)


@app.post("/chat")
async def chat(request: Request):
    body = await request.json()
    query = body.get("query", "")
    user_id = body.get("user_id", "anonymous")
    session_id = body.get("session_id")

    # Propagate user/session to all nested traces
    with propagate_attributes(user_id=user_id, session_id=session_id):
        result = await process_query(query)

    return {"response": result}


@observe()
async def process_query(query: str) -> str:
    """Traced as a span. Nested @observe calls become child spans."""
    context = await retrieve(query)
    return await generate(query, context)


@observe()
async def retrieve(query: str) -> str:
    # Your retrieval logic
    return "context"


@observe(as_type="generation")
async def generate(query: str, context: str) -> str:
    # Your LLM call — generation tracks model/tokens/cost
    return "response"
