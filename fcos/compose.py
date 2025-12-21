#!/usr/bin/env python3

import sys
import yaml
from pathlib import Path
from typing import List, Dict, Any


def merge_yaml(base: Dict[Any, Any], update: Dict[Any, Any]) -> Dict[Any, Any]:
    """Deep merge two YAML dictionaries."""
    result = base.copy()

    for key, value in update.items():
        if key in result:
            if isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = merge_yaml(result[key], value)
            elif isinstance(result[key], list) and isinstance(value, list):
                result[key] = result[key] + value
            else:
                result[key] = value
        else:
            result[key] = value

    return result


def compose_butane_files(butane_dir: Path, output_file: Path) -> None:
    """Compose multiple butane files into a single file."""

    # Define the order of files to merge
    files = [
        butane_dir / "base.bu",
        butane_dir / "network.bu",
        butane_dir / "users.bu",
        butane_dir / "storage.bu",
        butane_dir / "tailscale.bu",
        butane_dir / "containers" / "jellyfin.bu",
        butane_dir / "containers" / "adguardhome.bu",
        butane_dir / "containers" / "homepage.bu",
        butane_dir / "misc.bu",
    ]

    # Verify all files exist
    for file in files:
        if not file.exists():
            print(f"\033[0;31mERROR:\033[0m Required file not found: {file}", file=sys.stderr)
            sys.exit(1)

    print("\033[0;32m==>\033[0m Starting butane file composition")

    # Start with an empty dict
    result = {}

    # Merge each file
    for file in files:
        print(f"\033[0;32m==>\033[0m Merging {file.name}...")
        with open(file, 'r') as f:
            data = yaml.safe_load(f)
            if data:
                result = merge_yaml(result, data)

    # Write the result
    with open(output_file, 'w') as f:
        yaml.dump(result, f, default_flow_style=False, sort_keys=False, width=120)

    print("\033[0;32m==>\033[0m Composition complete!")
    print(f"\033[0;32m==>\033[0m Output file: {output_file}")

    # Display stats
    with open(output_file, 'r') as f:
        line_count = sum(1 for _ in f)

    print(f"\033[0;32m==>\033[0m Merged {len(files)} files into {line_count} lines")
    print()
    print("\033[0;32m==>\033[0m Next steps:")
    print(f"  1. Review the composed file: cat {output_file}")
    print("  2. Run the installation script from the parent directory")


if __name__ == "__main__":
    script_dir = Path(__file__).parent
    butane_dir = script_dir / "butane"
    output_file = script_dir / "homelab.bu"

    compose_butane_files(butane_dir, output_file)
