<?php
declare(strict_types=1);

// Copy to $HOME/dreamstore-private/config.php. Never upload this private folder
// inside public_html. These settings are server-only, not Flutter build defines.
return [
    'database' => [
        'host' => 'localhost',
        'port' => 3306,
        'name' => 'CPANELUSER_dreamstore',
        'user' => 'CPANELUSER_dreamstore',
        'password' => 'REPLACE_WITH_DATABASE_USER_PASSWORD',
    ],
    // Generate with: php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"
    // Set to an empty string after the first administrator is created.
    'setup_token' => 'REPLACE_WITH_64_RANDOM_HEX_CHARACTERS',
    'timezone' => 'Africa/Dar_es_Salaam',
    // Empty means same-origin browser requests only. For a separately hosted
    // frontend, list exact HTTPS origins without paths or trailing slashes.
    'allowed_origins' => [],
    'allow_insecure_local' => false,
    // Do not trust forwarded HTTPS/IP headers on shared hosting. Only turn this
    // on if your host guarantees its proxy overwrites X-Forwarded-Proto.
    'trust_proxy_https' => false,
];
