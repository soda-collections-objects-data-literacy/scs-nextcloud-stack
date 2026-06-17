#!/bin/bash

set -euo pipefail

echo "Configuring user_oidc for Bearer token validation..."

# Wait for Nextcloud to be ready.
until php -f /var/www/html/cron.php > /dev/null 2>&1; do
    echo "Waiting for Nextcloud..."
    sleep 5
done

CONFIG_FILE="/var/www/html/config/config.php"
USER_OIDC_PROVIDER_ID="${USER_OIDC_PROVIDER_ID:-SCS SSO Login}"

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

# 2. Configure user_oidc provider from sociallogin Keycloak settings (same client as Drive SSO).
#    Web login uses this single provider; sociallogin is disabled below to avoid duplicate buttons.
echo "Configuring user_oidc provider (${USER_OIDC_PROVIDER_ID}) from sociallogin config..."
php -r "
\$providerId = getenv('USER_OIDC_PROVIDER_ID') ?: 'SCS SSO Login';
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
\$postLogoutUri = rtrim(\$clientId, '/') . '/';

// Remove legacy provider identifier from earlier installs.
passthru('php /var/www/html/occ user_oidc:provider:delete Keycloak --force --no-warnings -n 2>/dev/null');

\$cmd = sprintf(
    'php /var/www/html/occ user_oidc:provider %s --clientid %s --clientsecret %s --discoveryuri %s --postlogouturi %s --send-id-token-hint=1 --check-bearer=1 --bearer-provisioning=1 --mapping-display-name=preferred_username --unique-uid=0 --no-warnings -n',
    escapeshellarg(\$providerId),
    escapeshellarg(\$clientId),
    escapeshellarg(\$clientSecret),
    escapeshellarg(\$discovery),
    escapeshellarg(\$postLogoutUri)
);
passthru(\$cmd);
echo \"user_oidc provider configured.\n\";
"

# 3. Disable ID4me — domain-based dynamic OIDC; not used with central Keycloak SSO.
#    When enabled, user_oidc adds a second "ID4ME" login button on the Drive login page.
echo "Disabling user_oidc ID4me (login via fixed Keycloak provider only)..."
php /var/www/html/occ config:app:set user_oidc id4me_enabled --value=0 --no-warnings -n

# 4. SSO-only web login (replaces sociallogin hide_default_login, which no longer applies when sociallogin is disabled).
#    hide_login_form: hide username/password form; emergency bypass: /login?direct=1
#    allow_multiple_user_backends=0: auto-redirect /login to the single Keycloak provider
echo "Enforcing SSO-only Drive login (hide password form, single OIDC backend)..."
php /var/www/html/occ config:system:set hide_login_form --type=boolean --value=true --no-warnings -n
php /var/www/html/occ config:system:set lost_password_link --value=disabled --no-warnings -n
php /var/www/html/occ config:app:set user_oidc allow_multiple_user_backends --value=0 --no-warnings -n

# 5. Disable sociallogin — it duplicated the Drive SSO button alongside user_oidc.
#    user_oidc handles web login and Bearer validation with one provider.
if php /var/www/html/occ app:list --enabled 2>/dev/null | grep -q sociallogin; then
    echo "Disabling sociallogin (login handled by user_oidc)..."
    php /var/www/html/occ app:disable sociallogin --no-warnings -n
fi

echo "user_oidc Bearer token configuration done!"
