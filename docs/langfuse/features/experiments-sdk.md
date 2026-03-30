<!-- Source: https://langfuse.com/docs/evaluation/experiments/experiments-via-sdk -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Experiments via SDK

## Overview

The Langfuse SDK enables programmatic experimentation by looping applications through datasets and applying evaluation methods. Users can leverage either Langfuse-hosted or local datasets as their foundation.

## Key Advantages

- Full flexibility to use your own application logic
- Custom scoring mechanisms for individual and aggregate results
- Parallel execution of multiple experiments on identical datasets
- Seamless integration with existing evaluation systems

## Experiment Runner Capabilities

The high-level abstraction automatically manages:

- Concurrent task execution with configurable limits
- Automatic trace generation for observability
- Item-level and aggregate evaluators
- Failure isolation preventing cascade errors
- Dataset integration for tracking and comparison

## Basic Implementation

### Python

```python
langfuse.run_experiment(
    name="Geography Quiz",
    data=local_data,
    task=my_task,
)
```

### JavaScript/TypeScript

Requires OpenTelemetry setup before initiating:

```typescript
await langfuse.experiment.run({
    name="Geography Quiz",
    data: localData,
    task: myTask,
});
```

## Evaluation Framework

The SDK supports evaluator functions that assess quality across dimensions:

- Individual item evaluation with custom metrics
- Aggregate run-level scoring across all items
- Asynchronous evaluator support
- Integration with the AutoEvals library

## Advanced Features

**Configuration Options** include concurrency limits, custom metadata attachment, and run naming.

**CI Integration** leverages test frameworks like Pytest and Vitest to enforce accuracy thresholds.

**Dataset Integration** automatically generates dataset runs in Langfuse UI for comparison.

## Low-Level API Alternative

For granular control, developers can manually iterate dataset items, execute application logic, link traces to items, and attach custom scores without the experiment runner abstraction.
