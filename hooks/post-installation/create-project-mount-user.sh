#!/bin/bash
#
# Creates the local service account that mounts project Team Folders for the
# project Jupyter servers (rclone sidecar, one mount per project). Idempotent.
#
# The SCS Manager adds the group to the Team Folder of every project that has
# Jupyter, so the account only sees those folders. It never logs in
# interactively; the sidecar authenticates with an app password.
#
# Existing deployments: run once, then store the printed app password as
# NEXTCLOUD_PROJECT_MOUNT_APP_PASSWORD in the deployment .env:
#   docker exec -u www-data -e CREATE_APP_PASSWORD=1 nextcloud--nextcloud--app \
#     bash /docker-entrypoint-hooks.d/post-installation/create-project-mount-user.sh

set -euo pipefail

OCC="php /var/www/html/occ --no-warnings"
MOUNT_USER="${NEXTCLOUD_PROJECT_MOUNT_USER:-scs-jupyter}"
MOUNT_GROUP="${NEXTCLOUD_PROJECT_MOUNT_GROUP:-scs-project-mounts}"

if ! $OCC user:info "$MOUNT_USER" >/dev/null 2>&1; then
	echo "Creating project mount service user ${MOUNT_USER}..."
	# Random login password nobody knows; access goes through app passwords only.
	OC_PASS="$(head -c 48 /dev/urandom | base64 | tr -d '\n/+=')" \
		$OCC user:add --password-from-env --display-name="SCS project mounts" "$MOUNT_USER"
fi

if ! $OCC group:list --output=json | grep -q "\"${MOUNT_GROUP}\""; then
	echo "Creating group ${MOUNT_GROUP}..."
	$OCC group:add "$MOUNT_GROUP"
fi
$OCC group:adduser "$MOUNT_GROUP" "$MOUNT_USER" 2>/dev/null || true
echo "Service user ${MOUNT_USER} is in group ${MOUNT_GROUP}."

# Every call creates another token, so only on request.
if [ "${CREATE_APP_PASSWORD:-0}" = "1" ]; then
	echo "App password for ${MOUNT_USER} (store as NEXTCLOUD_PROJECT_MOUNT_APP_PASSWORD):"
	$OCC user:add-app-password --name="scs-project-mounts" "$MOUNT_USER"
fi
