"""Report local LedgerLens prerequisites without printing secret values."""
from __future__ import annotations

import importlib.util
import os
import shutil
import sys


def main() -> int:
    print(f"Python: {sys.version.split()[0]}")
    python_ok = sys.version_info >= (3, 11)
    print(f"Python >= 3.11: {'available' if python_ok else 'missing'}")

    for module in ("flask", "oracledb", "dotenv"):
        print(f"Python module {module}: {'installed' if importlib.util.find_spec(module) else 'not installed'}")

    sql_tools = [tool for tool in ("sql", "sqlplus") if shutil.which(tool)]
    print("Oracle command-line tool: " + (", ".join(sql_tools) if sql_tools else "not found"))

    configured = [key for key in ("ORACLE_USER", "ORACLE_PASSWORD", "ORACLE_DSN") if os.getenv(key)]
    print(f"Oracle connection variables configured: {len(configured)}/3 (values hidden)")
    print("The Oracle schema/test suite still requires a reachable Oracle Database 19c+ instance.")
    return 0 if python_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
