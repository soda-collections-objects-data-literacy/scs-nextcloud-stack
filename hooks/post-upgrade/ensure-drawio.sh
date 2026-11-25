#!/bin/bash

set -euo pipefail

# Nextcloud upgrades can drop or disable the Draw.io app; reinstall and reconfigure it.
exec /docker-entrypoint-hooks.d/post-installation/install-drawio.sh
