#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_PACKAGES=(SGModels SGAsk SGForms SGSampleData)
PACKAGES=("$@")
if (("${#PACKAGES[@]}" == 0)); then
  PACKAGES=("${DEFAULT_PACKAGES[@]}")
fi

passed=()
failed=()
for package in "${PACKAGES[@]}"; do
  package_dir="$IOS_DIR/Packages/$package"
  if [[ ! -d "$package_dir" ]]; then
    printf 'Package directory not found: %s\n' "$package_dir" >&2
    failed+=("$package")
    continue
  fi

  printf '\n==> %s\n' "$package"
  if [[ -d "$package_dir/Tests" ]]; then
    if (cd "$package_dir" && swift test); then
      passed+=("$package (tested)")
    else
      failed+=("$package")
    fi
  else
    if (cd "$package_dir" && swift build); then
      printf '%s: no test target yet — built only\n' "$package"
      passed+=("$package (build only)")
    else
      failed+=("$package")
    fi
  fi
done

printf '\nSwift package summary:\n'
for package in "${passed[@]}"; do
  printf '  PASS %s\n' "$package"
done
for package in "${failed[@]}"; do
  printf '  FAIL %s\n' "$package"
done
if (("${#failed[@]}" > 0)); then
  exit 1
fi
