<?php
declare(strict_types=1);

require_once __DIR__ . '/_cli.php';
if ($argc < 2 || $argc > 3) {
    fwrite(STDERR, "Usage: php reset_admin_password.php ADMIN_EMAIL [ABSOLUTE_PRIVATE_CONFIG_PATH]\n");
    exit(2);
}
try {
    $app = dreamstore_cli_app($argv[2] ?? null);
    $email = \DreamStore\Security::validateEmail($argv[1]);
    $password = dreamstore_hidden_password('New password (12–72 bytes): ');
    $confirm = dreamstore_hidden_password('Confirm password: ');
    if (!hash_equals($password, $confirm)) throw new InvalidArgumentException('The passwords do not match.');
    $app->resetPassword($email, $password);
    unset($password, $confirm);
    fwrite(STDOUT, "Administrator password updated. All existing sessions for this account have been revoked.\n");
} catch (InvalidArgumentException $error) {
    fwrite(STDERR, $error->getMessage() . PHP_EOL);
    exit(1);
} catch (Throwable $error) {
    fwrite(STDERR, "Reset failed. Verify private configuration, database access, and an interactive Linux SSH terminal. No changes have been committed.\n");
    exit(1);
}
