# RAG and Retrieval

Source: `docs/rag.md`, `docs/retrieval.md`, `docs/knowledge-base.md`

## Overview

Retrieval-Augmented Generation (RAG) enhances LLM responses with context-specific information
fetched at query time. LangChain provides the full pipeline: document loading, text splitting,
embedding, vector storage, retrieval, and generation.

## Indexing pipeline

```python
from langchain_community.document_loaders import WebBaseLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
# vector_store is a VectorStore instance (e.g. InMemoryVectorStore, Chroma, Pinecone)

# 1. Load documents
loader = WebBaseLoader(web_paths=("https://example.com/docs",))
docs = loader.load()

# 2. Split into chunks
splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
chunks = splitter.split_documents(docs)

# 3. Embed and index
vector_store.add_documents(chunks)
```

## RAG agent pattern (agentic RAG)

Wrap the vector store as a retrieval tool so the agent decides when to retrieve:

```python
from langchain.tools import tool
from langchain.agents import create_agent

@tool(response_format="content_and_artifact")
def retrieve_context(query: str):
    """Retrieve relevant information to answer a query."""
    retrieved_docs = vector_store.similarity_search(query, k=3)
    serialized = "\n\n".join(
        f"Source: {doc.metadata}\nContent: {doc.page_content}"
        for doc in retrieved_docs
    )
    return serialized, retrieved_docs  # text goes to model, docs accessible as artifact

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[retrieve_context],
    system_prompt=(
        "You have access to a retrieval tool. "
        "Use it to find relevant information before answering. "
        "If retrieved context doesn't help, say you don't know."
    ),
)
```

`response_format="content_and_artifact"` returns a tuple: the first element (str) goes to
the model as `ToolMessage.content`; the second is stored in `ToolMessage.artifact` for
programmatic access downstream.

## Two-step RAG chain (non-agentic)

For simple queries, skip the full agent loop with a direct chain:

```python
from langchain.chat_models import init_chat_model
from langchain.messages import HumanMessage, SystemMessage

model = init_chat_model("openai:gpt-5.4")

def rag_chain(question: str) -> str:
    docs = vector_store.similarity_search(question, k=3)
    context = "\n\n".join(d.page_content for d in docs)
    response = model.invoke([
        SystemMessage(f"Answer using this context:\n{context}"),
        HumanMessage(question),
    ])
    return response.text
```

## Building blocks

- **Document loaders** — ingest from Google Drive, Notion, Slack, PDFs, web pages, etc.
  (see `/oss/python/integrations/document_loaders`)
- **Text splitters** — `RecursiveCharacterTextSplitter`, `MarkdownTextSplitter`, etc.
  (see `/oss/python/integrations/splitters`)
- **Embedding models** — `OpenAIEmbeddings`, `HuggingFaceEmbeddings`, etc.
  (see `/oss/python/integrations/embeddings`)
- **Vector stores** — Chroma, Pinecone, FAISS, `InMemoryVectorStore`, etc.
  (see `/oss/python/integrations/vectorstores`)
- **Retrievers** — wrap vector stores and other backends with a uniform interface
  (see `/oss/python/integrations/retrievers`)

## Multi-agent RAG (router pattern)

For multiple data sources, use the router multi-agent pattern to query each source in
parallel and synthesise results (see `docs/multi-agent__router-knowledge-base.md` and
`references/multi-agent.md`).

## SQL agent pattern

Build an agent that queries SQL databases with automatic schema exploration,
query generation, and error correction (see `docs/sql-agent.md`):

1. Agent fetches available tables and their schemas as tools.
2. Generates SQL queries from natural language questions.
3. Validates and corrects queries based on database engine feedback.

For progressive disclosure of table schemas across many tables, combine with
the skills pattern (`docs/multi-agent__skills-sql-assistant.md`).
