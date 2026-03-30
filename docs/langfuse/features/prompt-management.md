<!-- Source: https://langfuse.com/docs/prompt-management/get-started -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Get Started with Prompt Management

## Overview

This guide walks you through creating and using a prompt with Langfuse. For foundational understanding, see the Prompt Management Overview and Core Concepts documentation.

## Manual Installation

### Get API Keys

1. Create a Langfuse account or self-host
2. Create new API credentials in project settings

### Create a Prompt

**Via Langfuse UI:**

Select your prompt type (text or chat -- cannot change afterward). Use the visual interface to create or update prompts.

**Using Python SDK:**

```bash
pip install langfuse
```

Set environment variables:

```bash
LANGFUSE_SECRET_KEY = "sk-lf-..."
LANGFUSE_PUBLIC_KEY = "pk-lf-..."
LANGFUSE_BASE_URL = "https://cloud.langfuse.com" # EU
# LANGFUSE_BASE_URL = "https://us.cloud.langfuse.com" # US
```

Create prompts:

```python
# Text prompt
langfuse.create_prompt(
    name="movie-critic",
    type="text",
    prompt="As a {{criticlevel}} movie critic, do you like {{movie}}?",
    labels=["production"]
)

# Chat prompt
langfuse.create_prompt(
    name="movie-critic-chat",
    type="chat",
    prompt=[
      { "role": "system", "content": "You are an {{criticlevel}} movie critic" },
      { "role": "user", "content": "Do you like {{movie}}?" },
    ],
    labels=["production"]
)
```

Prompts with duplicate names automatically create new versions.

**Using JavaScript/TypeScript SDK:**

```bash
npm i @langfuse/client
```

```typescript
import { LangfuseClient } from "@langfuse/client";
const langfuse = new LangfuseClient();

// Text prompt
await langfuse.prompt.create({
  name: "movie-critic",
  type: "text",
  prompt: "As a {{criticlevel}} critic, do you like {{movie}}?",
  labels: ["production"]
});

// Chat prompt
await langfuse.prompt.create({
  name: "movie-critic-chat",
  type: "chat",
  prompt: [
    { role: "system", content: "You are an {{criticlevel}} movie critic" },
    { role: "user", content: "Do you like {{movie}}?" },
  ],
  labels: ["production"]
});
```

**Using Public API:**

```bash
curl -X POST "https://cloud.langfuse.com/api/public/v2/prompts" \
  -u "your-public-key:your-secret-key" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "chat",
    "name": "movie-critic",
    "prompt": [
      { "role": "system", "content": "You are an {{criticlevel}} movie critic" },
      { "role": "user", "content": "Do you like {{movie}}?" }
    ]
  }'
```

### Use the Prompt in Your Code

Fetch prompts at runtime, preferring the `production` label for deployed versions.

**Python SDK:**

```python
from langfuse import get_client
langfuse = get_client()

# Text prompt
prompt = langfuse.get_prompt("movie-critic")
compiled_prompt = prompt.compile(criticlevel="expert", movie="Dune 2")
# -> "As an expert movie critic, do you like Dune 2?"

# Chat prompt
chat_prompt = langfuse.get_prompt("movie-critic-chat", type="chat")
compiled_chat_prompt = chat_prompt.compile(criticlevel="expert", movie="Dune 2")
```

**JavaScript/TypeScript SDK:**

```typescript
import { LangfuseClient } from "@langfuse/client";
const langfuse = new LangfuseClient();

// Text prompt
const prompt = await langfuse.prompt.get("movie-critic");
const compiledPrompt = prompt.compile({
  criticlevel: "expert",
  movie: "Dune 2",
});

// Chat prompt
const chatPrompt = await langfuse.prompt.get("movie-critic-chat", {
  type: "chat",
});
const compiledChatPrompt = chatPrompt.compile({
  criticlevel: "expert",
  movie: "Dune 2",
});
```

**Public API:**

```bash
# By label (default: production)
curl "https://cloud.langfuse.com/api/public/v2/prompts/movie-critic?label=production" \
  -u "your-public-key:your-secret-key"

# By specific version
curl "https://cloud.langfuse.com/api/public/v2/prompts/movie-critic?version=1" \
  -u "your-public-key:your-secret-key"
```

### With OpenAI (Python)

```python
import openai
from langfuse import get_client

langfuse = get_client()

# Text prompt
prompt = langfuse.get_prompt("movie-critic")
compiled_prompt = prompt.compile(criticlevel="expert", movie="Dune 2")

completion = openai.chat.completions.create(
  model="gpt-4o",
  messages=[{"role": "user", "content": compiled_prompt}]
)

# Chat prompt
chat_prompt = langfuse.get_prompt("movie-critic-chat", type="chat")
compiled_chat_prompt = chat_prompt.compile(criticlevel="expert", movie="Dune 2")

completion = openai.chat.completions.create(
  model="gpt-4o",
  messages=compiled_chat_prompt
)
```

### With LangChain (Python)

```python
from langfuse import Langfuse
from langchain_core.prompts import ChatPromptTemplate

langfuse = Langfuse()

# Text prompt
langfuse_prompt = langfuse.get_prompt("movie-critic")
langchain_prompt = ChatPromptTemplate.from_template(langfuse_prompt.get_langchain_prompt())

# Chat prompt
langfuse_prompt = langfuse.get_prompt("movie-critic-chat", type="chat")
langchain_prompt = ChatPromptTemplate.from_messages(langfuse_prompt.get_langchain_prompt())
```

### With LangChain (JavaScript/TypeScript)

```typescript
import { LangfuseClient } from "@langfuse/client";
import { ChatPromptTemplate } from "@langchain/core/prompts";

const langfuse = new LangfuseClient();

// Text prompt
const langfusePrompt = await langfuse.prompt.get("movie-critic");
const promptTemplate = PromptTemplate.fromTemplate(
  langfusePrompt.getLangchainPrompt()
);

// Chat prompt
const langfusePrompt = await langfuse.prompt.get(
  "movie-critic-chat",
  { type: "chat" }
);
const promptTemplate = ChatPromptTemplate.fromMessages(
  langfusePrompt.getLangchainPrompt().map((msg) => [msg.role, msg.content])
);
```

## Caching Note

If you don't see your latest version, check the prompt caching behavior documentation.

## Next Steps

- Link prompts to traces to analyze performance by version
- Use version control and labels to manage deployments across environments
- Explore feature guides for specific topics
