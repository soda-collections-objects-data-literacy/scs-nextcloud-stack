#!/bin/bash

set -euo pipefail

# Idempotent: also runs as post-upgrade hook, where the app may already exist
# or may have been removed/disabled by the Nextcloud upgrade.
if php /var/www/html/occ app:getpath drawio >/dev/null 2>&1; then
    echo "Draw.io plugin already present, updating if possible..."
    php /var/www/html/occ app:update drawio || true
else
    echo "Installing Draw.io plugin..."
    php /var/www/html/occ app:install drawio
    echo "Draw.io plugin installed successfully!"
fi

echo "Activating Draw.io plugin..."
php /var/www/html/occ app:enable drawio
echo "Draw.io plugin activated successfully!"

# Global defaults for all users: CHIN CIDOC CRM shape libraries
# https://github.com/chin-rcip/diagrams.net_libraries (MIT; see repo README for attribution)
DRAWIO_CFG_FILE="$(dirname "$0")/drawio-default-config.json"
if [ -f "${DRAWIO_CFG_FILE}" ]; then
    echo "Configuring Draw.io libraries (CHIN diagrams.net_libraries)..."
    php /var/www/html/occ --no-warnings config:app:set drawio DrawioLibraries --value=yes
    php /var/www/html/occ --no-warnings config:app:set drawio DrawioUrl --value='https://embed.diagrams.net'
    DRAWIO_JSON="$(cat "${DRAWIO_CFG_FILE}")"
    php /var/www/html/occ --no-warnings config:app:set drawio DrawioConfig --value="${DRAWIO_JSON}"
    echo "Draw.io default libraries configured."
else
    echo "Warning: ${DRAWIO_CFG_FILE} not found; skipping Draw.io library defaults."
fi
