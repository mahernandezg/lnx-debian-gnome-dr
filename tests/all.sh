#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Manuel Alejandro Hernández Giuliani

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests=(
    smoke.sh
    inventory.sh
    applications.sh
    desktop.sh
    system.sh
    backup.sh
)

for test_name in "${tests[@]}"; do
    printf '\n=== Running %s ===\n' "$test_name"
    "${PROJECT_ROOT}/tests/${test_name}"
done

printf '\nPASS: all project tests completed successfully\n'
