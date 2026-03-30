<!-- Source: https://langfuse.com/docs/evaluation/core-concepts -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Core Concepts - LLM Evaluation in Langfuse

## The Evaluation Loop

Langfuse supports continuous testing and monitoring through two complementary approaches:

**Offline evaluation** uses fixed datasets to test applications before deployment. In Langfuse, this happens through experiments where you test new prompts or models against predefined test cases, review results, iterate, and then deploy.

**Online evaluation** scores live production traces to identify real-world issues. When edge cases emerge, they're added back to datasets for future experiment coverage.

### Example Workflow

A customer support chatbot scenario illustrates the cycle: updating prompts, running experiments on existing test data, refining based on results, deploying changes, monitoring production, discovering new edge cases (like French language queries), and expanding the dataset to prevent future regressions.

## Evaluation Methods

Langfuse provides four primary approaches for scoring traces and observations:

| Method | Purpose | Best For |
|--------|---------|----------|
| LLM-as-a-Judge | LLM-driven evaluation against custom criteria | Subjective assessments at scale (tone, accuracy, helpfulness) |
| UI Scoring | Manual score assignment within Langfuse interface | Quick quality checks on individual traces |
| Annotation Queues | Structured human review with customizable workflows | Ground truth building and team collaboration |
| API/SDK Scores | Programmatic score integration | Custom pipelines and deterministic checks |

Score Analytics tools help validate the scoring methods you implement.

## Experiments

Experiments test applications against datasets and evaluate outputs before production deployment.

### Key Components

- **Dataset**: Collection of test cases for consistent performance measurement
- **Dataset Item**: Individual test case with input and optional expected output
- **Task**: Application code being tested, executed on each dataset item
- **Evaluation Method**: Scoring function producing numeric, categorical, or boolean results
- **Experiment Run**: Single execution of tasks against all dataset items

### Execution Methods

Two approaches exist:

1. **SDK-based**: Full control over task logic and evaluation, supporting both Langfuse and local datasets
2. **UI-based**: Quick prompt iteration without coding, requires Langfuse datasets

Langfuse recommends managing datasets within the platform to enable in-UI comparisons and iterative improvement based on production traces.

## Online Evaluation

For production monitoring, Langfuse currently supports LLM-as-a-Judge and human annotation for automated trace scoring, with deterministic checks planned for future release.

Real-time dashboards enable performance monitoring and score tracking across your application.
