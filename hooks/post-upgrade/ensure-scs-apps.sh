#!/bin/bash

set -euo pipefail

# Nextcloud upgrades can disable groupfolders and scs_manager_integration;
# the install hook enables them again and disables related_resources.
exec /docker-entrypoint-hooks.d/post-installation/install-scs-manager-integration.sh
