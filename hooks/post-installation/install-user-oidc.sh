#!/bin/bash

set -euo pipefail

echo "Installing user_oidc app (Bearer token validation for API requests)..."
php /var/www/html/occ --no-warnings app:install user_oidc
echo "Enabling user_oidc app..."
php /var/www/html/occ --no-warnings app:enable user_oidc
echo "user_oidc installed and enabled."
