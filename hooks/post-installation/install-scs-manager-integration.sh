#!/bin/bash

set -euo pipefail

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

# related_resources passes numeric group IDs (project groups are 10001, …) to
# Circles as int and fails with 500 in the sharing sidebar of Team Folder files.
php /var/www/html/occ --no-warnings app:disable related_resources -n 2>/dev/null || true
echo "Related Resources disabled."

echo "Enabling SCS Manager Integration app..."
# Remove legacy app id if still present from earlier deployments.
php /var/www/html/occ --no-warnings app:disable scs_project_feeds -n 2>/dev/null || true
php /var/www/html/occ --no-warnings app:remove scs_project_feeds -n 2>/dev/null || true

php /var/www/html/occ --no-warnings app:enable scs_manager_integration
echo "SCS Manager Integration enabled."
