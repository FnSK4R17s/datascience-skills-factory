#!/usr/bin/env python3
"""Verify Langfuse SDK installation, credentials, and connectivity."""

import os
import sys


def check():
    errors = []
    warnings = []

    # 1. Check SDK installed
    try:
        import langfuse
        print(f"  SDK version: {langfuse.__version__}")
    except ImportError:
        errors.append("langfuse not installed. Run: pip install langfuse")
        print("\n".join(f"  ERROR: {e}" for e in errors))
        return False

    # 2. Check env vars
    public_key = os.environ.get("LANGFUSE_PUBLIC_KEY", "")
    secret_key = os.environ.get("LANGFUSE_SECRET_KEY", "")
    base_url = os.environ.get("LANGFUSE_BASE_URL", "https://cloud.langfuse.com")

    if not public_key:
        errors.append("LANGFUSE_PUBLIC_KEY not set")
    elif not public_key.startswith("pk-lf-"):
        warnings.append(f"LANGFUSE_PUBLIC_KEY doesn't start with 'pk-lf-': {public_key[:10]}...")

    if not secret_key:
        errors.append("LANGFUSE_SECRET_KEY not set")
    elif not secret_key.startswith("sk-lf-"):
        warnings.append(f"LANGFUSE_SECRET_KEY doesn't start with 'sk-lf-': {secret_key[:10]}...")

    print(f"  Base URL: {base_url}")
    print(f"  Public key: {'set' if public_key else 'MISSING'}")
    print(f"  Secret key: {'set' if secret_key else 'MISSING'}")

    # 3. Check common misconfigurations
    if "us.cloud.langfuse.com" in base_url:
        print("  Region: US")
    elif "eu.cloud.langfuse.com" in base_url or base_url == "https://cloud.langfuse.com":
        print("  Region: EU (default)")
    else:
        print(f"  Region: Self-hosted ({base_url})")

    # 4. Check Pydantic version
    try:
        import pydantic
        major = int(pydantic.__version__.split(".")[0])
        if major < 2:
            errors.append(f"Pydantic v{pydantic.__version__} detected. Langfuse v4 requires Pydantic v2+")
        else:
            print(f"  Pydantic: v{pydantic.__version__}")
    except ImportError:
        warnings.append("pydantic not found")

    # 5. Check Python version
    if sys.version_info < (3, 10):
        errors.append(f"Python {sys.version_info.major}.{sys.version_info.minor} detected. Langfuse v4 requires 3.10+")
    else:
        print(f"  Python: {sys.version.split()[0]}")

    # 6. Connectivity check
    if public_key and secret_key:
        try:
            from langfuse import Langfuse
            lf = Langfuse()
            lf.auth_check()
            print("  Auth check: OK")
        except Exception as e:
            errors.append(f"Auth check failed: {e}")

    # 7. Check for OTEL collisions
    otel_packages = []
    for pkg in ["sentry_sdk", "ddtrace", "logfire"]:
        try:
            __import__(pkg)
            otel_packages.append(pkg)
        except ImportError:
            pass
    if otel_packages:
        warnings.append(
            f"Other OTEL-based packages detected: {', '.join(otel_packages)}. "
            "Consider using an isolated TracerProvider to prevent span leaking."
        )

    # Report
    if warnings:
        print()
        for w in warnings:
            print(f"  WARNING: {w}")
    if errors:
        print()
        for e in errors:
            print(f"  ERROR: {e}")
        return False

    print("\n  All checks passed.")
    return True


if __name__ == "__main__":
    print("Langfuse Setup Check")
    print("=" * 40)
    ok = check()
    sys.exit(0 if ok else 1)
