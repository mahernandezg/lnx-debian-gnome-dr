#!/usr/bin/env bash
set -Eeuo pipefail

required_files=(
  README.md
  VERSION
  CHANGELOG.md
  config/default.conf
  templates/machine-readme.md
  templates/manifest.md
  templates/history.md
  docs/architecture.md
  docs/backup-format.md
  docs/restore-guide.md
  docs/roadmap.md
  scripts/backup.sh
  scripts/inventory.sh
  scripts/restore.sh
  scripts/verify.sh
  scripts/install.sh
  scripts/uninstall.sh
  tests/backup.sh
  systemd/lnx-debian-gnome-dr.service
  systemd/lnx-debian-gnome-dr.timer
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "FAIL: missing $file"
    exit 1
  fi
done

echo "PASS: repository structure is complete"
