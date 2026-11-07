#!/bin/bash

set -euo pipefail

# --apps-only skips the platform Team Folder. Post-upgrade uses that so an
# upgrade does not create SCS-Share on an instance that still has the private
# skeleton folder of the same name.
APPS_ONLY=0
if [ "${1:-}" = "--apps-only" ]; then
	APPS_ONLY=1
fi

# Team Folders (app id groupfolders) is what scs_manager_integration registers
# project folders in. Without it the OCS API can be enabled and still unable
# to create a mount, and WissKI stack creation waits forever for that folder.
echo "Ensuring Team Folders (groupfolders)..."
if php /var/www/html/occ app:getpath groupfolders >/dev/null 2>&1; then
	echo "Team Folders already present."
else
	php /var/www/html/occ --no-warnings app:install groupfolders
	echo "Team Folders installed."
fi
php /var/www/html/occ --no-warnings app:enable groupfolders
echo "Team Folders enabled."

echo "Enabling SCS Manager Integration app..."
# Remove legacy app id if still present from earlier deployments.
php /var/www/html/occ --no-warnings app:disable scs_project_feeds -n 2>/dev/null || true
php /var/www/html/occ --no-warnings app:remove scs_project_feeds -n 2>/dev/null || true

php /var/www/html/occ --no-warnings app:enable scs_manager_integration
echo "SCS Manager Integration enabled."

if [ "$APPS_ONLY" = "1" ]; then
	echo "Skipping platform Team Folder (--apps-only)."
	exit 0
fi

# Register platform Team Folder (SCS-Share). Groups can be adjusted later by Manager.
ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
if php /var/www/html/occ --no-warnings group:list 2>/dev/null | grep -q "admin"; then
	php /var/www/html/occ --no-warnings scs_manager_integration:ensure-platform-share --admin="${ADMIN_USER}" -g admin || true
else
	php /var/www/html/occ --no-warnings scs_manager_integration:ensure-platform-share --admin="${ADMIN_USER}" || true
fi
