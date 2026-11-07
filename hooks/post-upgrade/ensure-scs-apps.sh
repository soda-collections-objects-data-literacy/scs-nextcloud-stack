#!/bin/bash

set -euo pipefail

# Nextcloud upgrades can disable groupfolders and scs_manager_integration.
# Re-enable them without creating the platform Team Folder.
exec /docker-entrypoint-hooks.d/post-installation/install-scs-manager-integration.sh --apps-only
