#!/usr/bin/env python3
"""Query recent Langfuse traces and generate a cost summary report.

Usage:
    python trace_cost_report.py                    # last 24 hours
    python trace_cost_report.py --hours 168        # last 7 days
    python trace_cost_report.py --trace-name "qa"  # filter by name
"""

import argparse
import os
from datetime import datetime, timedelta, timezone


def main():
    parser = argparse.ArgumentParser(description="Langfuse cost report")
    parser.add_argument("--hours", type=int, default=24, help="Lookback period in hours")
    parser.add_argument("--trace-name", type=str, default=None, help="Filter by trace name")
    parser.add_argument("--limit", type=int, default=100, help="Max traces to fetch")
    args = parser.parse_args()

    try:
        from langfuse import Langfuse
    except ImportError:
        print("ERROR: langfuse not installed. Run: pip install langfuse")
        return

    langfuse = Langfuse()
    since = datetime.now(timezone.utc) - timedelta(hours=args.hours)

    print(f"Langfuse Cost Report — last {args.hours} hours")
    print(f"Since: {since.isoformat()}")
    print("=" * 60)

    try:
        # Fetch traces via the public API
        traces = langfuse.api.traces.list(
            limit=args.limit,
            order_by="timestamp",
        )
    except Exception as e:
        print(f"ERROR fetching traces: {e}")
        print("Ensure LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_BASE_URL are set.")
        return

    if not traces.data:
        print("No traces found in the specified period.")
        return

    # Aggregate by model
    model_costs: dict[str, dict] = {}
    total_cost = 0.0
    total_tokens = 0
    trace_count = 0

    for trace in traces.data:
        if trace.timestamp and trace.timestamp < since:
            continue
        if args.trace_name and args.trace_name not in (trace.name or ""):
            continue

        trace_count += 1
        observations = langfuse.api.observations.list(trace_id=trace.id)

        for obs in observations.data:
            if obs.type != "GENERATION":
                continue

            model = obs.model or "unknown"
            cost = 0.0
            tokens = 0

            if obs.calculated_total_cost is not None:
                cost = obs.calculated_total_cost
            if obs.usage:
                tokens = (obs.usage.input or 0) + (obs.usage.output or 0)

            if model not in model_costs:
                model_costs[model] = {"cost": 0.0, "tokens": 0, "calls": 0}
            model_costs[model]["cost"] += cost
            model_costs[model]["tokens"] += tokens
            model_costs[model]["calls"] += 1
            total_cost += cost
            total_tokens += tokens

    # Print report
    print(f"\nTraces analyzed: {trace_count}")
    print(f"Total cost: ${total_cost:.4f}")
    print(f"Total tokens: {total_tokens:,}")
    print()

    if model_costs:
        print(f"{'Model':<30} {'Calls':>6} {'Tokens':>12} {'Cost (USD)':>12}")
        print("-" * 62)
        for model, data in sorted(model_costs.items(), key=lambda x: x[1]["cost"], reverse=True):
            print(f"{model:<30} {data['calls']:>6} {data['tokens']:>12,} ${data['cost']:>11.4f}")

    langfuse.shutdown()


if __name__ == "__main__":
    main()
