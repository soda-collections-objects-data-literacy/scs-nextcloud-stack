#!/bin/bash

set -euo pipefail

echo "Configuring user_oidc for Bearer token validation..."

# Wait for Nextcloud to be ready (cron.php must run as www-data).
until runuser -u www-data -- php -f /var/www/html/cron.php > /dev/null 2>&1; do
    echo "Waiting for Nextcloud..."
    sleep 5
done

run_occ() {
    runuser -u www-data -- php /var/www/html/occ --no-warnings "$@"
}

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

# 2. Configure user_oidc provider (Keycloak client = Drive SSO).
#    Prefer sociallogin bootstrap config when present; fall back to container env.
echo "Configuring user_oidc provider (${USER_OIDC_PROVIDER_ID})..."
php -r "
\$providerId = getenv('USER_OIDC_PROVIDER_ID') ?: 'SCS SSO Login';
\$clientId = null;
\$clientSecret = null;
\$discovery = null;

\$json = shell_exec('runuser -u www-data -- php /var/www/html/occ config:app:get sociallogin custom_providers 2>/dev/null');
if (\$json) {
    \$data = json_decode(\$json, true);
    \$p = \$data['custom_oidc'][0] ?? null;
    if (\$p && !empty(\$p['clientId']) && !empty(\$p['clientSecret'])) {
        \$base = preg_replace('#/protocol/openid-connect/.*#', '', \$p['tokenUrl'] ?? '');
        \$discovery = \$base . '/.well-known/openid-configuration';
        \$clientId = \$p['clientId'];
        \$clientSecret = \$p['clientSecret'];
    }
}

if (!\$clientId || !\$clientSecret) {
    \$kcDomain = getenv('KC_DOMAIN') ?: '';
    \$kcRealm = getenv('SOCIALLOGIN_KEYCLOAK_REALM') ?: getenv('KC_REALM') ?: '';
    \$clientId = getenv('SOCIALLOGIN_KEYCLOAK_CLIENT_ID') ?: getenv('NEXTCLOUD_CLIENT_ID') ?: '';
    \$clientSecret = getenv('SOCIALLOGIN_KEYCLOAK_CLIENT_SECRET') ?: getenv('NEXTCLOUD_CLIENT_SECRET') ?: '';
    if (\$kcDomain && \$kcRealm) {
        \$discovery = 'https://' . \$kcDomain . '/realms/' . \$kcRealm . '/.well-known/openid-configuration';
    }
}

if (!\$clientId || !\$clientSecret || !\$discovery) {
    echo \"Keycloak provider settings incomplete, skipping user_oidc.\n\";
    exit(0);
}
\$postLogoutUri = rtrim(\$clientId, '/') . '/';

passthru('runuser -u www-data -- php /var/www/html/occ user_oidc:provider:delete Keycloak --force --no-warnings -n 2>/dev/null');

\$cmd = sprintf(
    'runuser -u www-data -- php /var/www/html/occ user_oidc:provider %s --clientid %s --clientsecret %s --discoveryuri %s --postlogouturi %s --send-id-token-hint=1 --check-bearer=1 --bearer-provisioning=1 --mapping-display-name=preferred_username --unique-uid=0 --no-warnings -n',
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
run_occ config:app:set user_oidc id4me_enabled --value=0 -n

# 4. SSO-only web login (replaces sociallogin hide_default_login).
#    hide_login_form: hide username/password form; emergency bypass: /login?direct=1
#    allow_multiple_user_backends=0: auto-redirect /login to the single Keycloak provider
echo "Enforcing SSO-only Drive login (hide password form, single OIDC backend)..."
run_occ config:system:set hide_login_form --type=boolean --value=true -n
run_occ config:system:set lost_password_link --value=disabled -n
run_occ config:app:set user_oidc allow_multiple_user_backends --value=0 -n

# 5. Remove sociallogin — user_oidc handles web login and Bearer validation.
if run_occ app:list 2>/dev/null | grep -q sociallogin; then
    echo "Removing sociallogin (login handled by user_oidc)..."
    run_occ app:enable sociallogin -n 2>/dev/null || true
    run_occ app:remove sociallogin -n 2>/dev/null || run_occ app:disable sociallogin -n
fi

echo "user_oidc Bearer token configuration done!"
