#!/bin/bash

set -euo pipefail

echo "Enabling SCS Manager Integration app..."
# Remove legacy app id if still present from earlier deployments.
php /var/www/html/occ --no-warnings app:disable scs_project_feeds -n 2>/dev/null || true
php /var/www/html/occ --no-warnings app:remove scs_project_feeds -n 2>/dev/null || true

php /var/www/html/occ --no-warnings app:enable scs_manager_integration
echo "SCS Manager Integration enabled."

# Register platform Team Folder (SCS-Share). Groups can be adjusted later by Manager.
ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
if php /var/www/html/occ --no-warnings group:list 2>/dev/null | grep -q "admin"; then
	php /var/www/html/occ --no-warnings scs_manager_integration:ensure-platform-share --admin="${ADMIN_USER}" -g admin || true
else
	php /var/www/html/occ --no-warnings scs_manager_integration:ensure-platform-share --admin="${ADMIN_USER}" || true
fi
