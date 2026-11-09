<?php
declare(strict_types=1);

require_once __DIR__ . '/_cli.php';
if ($argc > 2) {
    fwrite(STDERR, "Usage: php maintenance.php [ABSOLUTE_PRIVATE_CONFIG_PATH]\n");
    exit(2);
}
try {
    $result = dreamstore_cli_app($argv[1] ?? null)->maintenance();
    fwrite(STDOUT, json_encode($result, JSON_THROW_ON_ERROR) . PHP_EOL);
} catch (Throwable $error) {
    fwrite(STDERR, "Maintenance failed. Check private configuration and database access.\n");
    exit(1);
}
