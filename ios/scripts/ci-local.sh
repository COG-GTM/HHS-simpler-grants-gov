#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$IOS_DIR"
./scripts/lint-localization.sh --self-test
./scripts/lint-localization.sh
./scripts/ci-swift-packages.sh
bundle exec fastlane test
bundle exec fastlane ui_test
bundle exec fastlane build_sim
bundle exec fastlane archive_unsigned
