#!/bin/bash

set -euo pipefail

echo "Configuring user_oidc for Bearer token validation..."

# Wait for Nextcloud to be ready.
until php -f /var/www/html/cron.php > /dev/null 2>&1; do
    echo "Waiting for Nextcloud..."
    sleep 5
done

CONFIG_FILE="/var/www/html/config/config.php"

# 1. Add oidc_provider_bearer_validation and bearer_validation_azp_check to config.php
#    bearer_validation_azp_check=false allows cross-client tokens (SCS Manager -> Nextcloud)
php -r "
\$configPath = '${CONFIG_FILE}';
if (!file_exists(\$configPath)) {
    echo \"Config file not found.\n\";
    exit(1);
}
\$CONFIG = [];
include \$configPath;
\$config = \$GLOBALS['CONFIG'] ?? [];
if (empty(\$config)) {
    echo \"Could not load config.\n\";
    exit(1);
}
\$config['user_oidc'] = \$config['user_oidc'] ?? [];
\$config['user_oidc']['oidc_provider_bearer_validation'] = true;
\$config['user_oidc']['bearer_validation_azp_check'] = false;
\$content = '<?php' . PHP_EOL . '\$CONFIG = ' . var_export(\$config, true) . ';' . PHP_EOL;
if (file_put_contents(\$configPath, \$content) === false) {
    echo \"Failed to write config.\n\";
    exit(1);
}
echo \"oidc_provider_bearer_validation enabled.\n\";
"

# 2. Add Keycloak provider to user_oidc from sociallogin config (same Keycloak as web login)
#    Uses --check-bearer=1 so API requests with Bearer token are validated.
echo "Adding user_oidc Keycloak provider from sociallogin config..."
php -r "
\$json = shell_exec('php /var/www/html/occ config:app:get sociallogin custom_providers 2>/dev/null');
if (!\$json) { echo \"No sociallogin config found.\n\"; exit(0); }
\$data = json_decode(\$json, true);
\$p = \$data['custom_oidc'][0] ?? null;
if (!\$p || empty(\$p['clientId']) || empty(\$p['clientSecret'])) {
    echo \"Sociallogin provider incomplete, skipping user_oidc.\n\";
    exit(0);
}
\$base = preg_replace('#/protocol/openid-connect/.*#', '', \$p['tokenUrl'] ?? '');
\$discovery = \$base . '/.well-known/openid-configuration';
\$clientId = \$p['clientId'];
\$clientSecret = \$p['clientSecret'];
\$cmd = sprintf(
    'php /var/www/html/occ user_oidc:provider Keycloak --clientid %s --clientsecret %s --discoveryuri %s --check-bearer=1 --bearer-provisioning=1 --mapping-display-name=preferred_username --unique-uid=0 --no-warnings -n 2>/dev/null',
    escapeshellarg(\$clientId),
    escapeshellarg(\$clientSecret),
    escapeshellarg(\$discovery)
);
passthru(\$cmd);
echo \"user_oidc provider configured.\n\";
"

echo "user_oidc Bearer token configuration done!"
