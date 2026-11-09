<?php
declare(strict_types=1);

// Opt-in only. Uses a NEW EMPTY database whose name ends in _test; production
// tables are never reused. The test creates/drops only its own four tables.
require_once __DIR__ . '/helpers.php';

use DreamStore\ApiError;
use DreamStore\App;
use DreamStore\Security;

$name = getenv('DREAMSTORE_TEST_DB_NAME');
if (!is_string($name) || $name === '' || getenv('DREAMSTORE_TEST_ALLOW_CREATE') !== '1') {
    fwrite(STDOUT, "SKIP MySQL integration: set DREAMSTORE_TEST_DB_NAME ending in _test, HOST, PORT, USER, PASSWORD and DREAMSTORE_TEST_ALLOW_CREATE=1 for a new empty disposable database.\n");
    exit(0);
}
if (!str_ends_with($name, '_test')) {
    fwrite(STDERR, "Refusing integration run: database name must end in _test.\n");
    exit(2);
}
$config = [
    'database' => [
        'host' => getenv('DREAMSTORE_TEST_DB_HOST') ?: 'localhost',
        'port' => (int) (getenv('DREAMSTORE_TEST_DB_PORT') ?: 3306),
        'name' => $name,
        'user' => getenv('DREAMSTORE_TEST_DB_USER') ?: '',
        'password' => getenv('DREAMSTORE_TEST_DB_PASSWORD') ?: '',
    ],
    'setup_token' => Security::token(),
    'allowed_origins' => [],
];
$app = new App($config);
$created = false;
$resultCode = 0;
$tables = ['dreamstore_sessions', 'dreamstore_inventory', 'dreamstore_rate_limits', 'dreamstore_users'];
try {
    $db = $app->db();
    test_assert($db->query('SHOW TABLES')->fetchAll() === [], 'Integration database must be entirely empty.');
    $sql = file_get_contents(dirname(__DIR__) . '/schema.sql');
    test_assert(is_string($sql), 'Schema file missing.');
    $created = true;
    foreach (explode(';', $sql) as $statement) if (trim($statement) !== '') $db->exec($statement);
    test_assert($app->getInventory() === ['version' => 0, 'data' => null], 'Initial empty version');
    $app->createAdministrator([
        'setup_token' => $config['setup_token'], 'name' => 'Test Administrator',
        'email' => 'admin@example.test', 'password' => 'test-strong-password-2026',
        'confirm_password' => 'test-strong-password-2026',
    ]);
    test_assert(!$app->setupEnabled(), 'Setup closes after first user');
    try {
        $app->createAdministrator(['setup_token' => $config['setup_token']]);
        throw new RuntimeException('Setup should not accept a second admin.');
    } catch (ApiError $error) {
        test_assert($error->status === 403, 'Second admin forbidden');
    }
    $_SERVER['REMOTE_ADDR'] = '127.0.0.1';
    $login = $app->login((object) ['email' => 'admin@example.test', 'password' => 'test-strong-password-2026']);
    test_assert(!isset($login['user']['password_hash']), 'Never return password data');
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $login['token'];
    $user = $app->authenticate();
    $stored = $db->query('SELECT token_hash FROM dreamstore_sessions LIMIT 1')->fetchColumn();
    test_assert($stored === Security::tokenHash($login['token']) && $stored !== $login['token'], 'Database stores only hashed session');
    test_assert($app->saveInventory(0, inventory_fixture(), (int) $user['id']) === 1, 'First save');
    $original = $app->getInventory();
    test_assert($original['version'] === 1 && $original['data']->products[0]->receivedAt === '2026-09-12T00:00:00.000', 'Receipt preserved');
    try {
        $app->saveInventory(0, inventory_fixture(), (int) $user['id']);
        throw new RuntimeException('Stale save should fail.');
    } catch (ApiError $error) {
        test_assert($error->status === 409, 'CAS conflict');
    }
    test_assert($app->getInventory()['version'] === 1, 'Conflict never commits');
    $app->resetPassword('admin@example.test', 'updated-strong-password-2026');
    test_assert($db->query('SELECT COUNT(*) FROM dreamstore_sessions')->fetchColumn() == 0, 'Reset revokes all sessions');
    try {
        $app->authenticate();
        throw new RuntimeException('Old token should expire.');
    } catch (ApiError $error) {
        test_assert($error->status === 401, 'Old token rejected');
    }
    try {
        $app->login((object) ['email' => 'admin@example.test', 'password' => 'test-strong-password-2026']);
        throw new RuntimeException('Old password should fail after reset.');
    } catch (ApiError $error) {
        test_assert($error->status === 401 && $error->errorCode === 'invalid_credentials', 'Reset rejects old password');
    }
    $newLogin = $app->login((object) ['email' => 'admin@example.test', 'password' => 'updated-strong-password-2026']);
    test_assert(isset($newLogin['token']), 'New password can sign in');
    test_assert($app->saveInventory(1, null, (int) $user['id']) === 2 && $app->getInventory()['data'] === null, 'Versioned clear');
    fwrite(STDOUT, "PASS MySQL bootstrap, login, hashed sessions, dated snapshot round-trip, CAS conflict rollback, password reset/session revocation/old-password rejection, and versioned clear.\n");
} catch (Throwable $error) {
    fwrite(STDERR, "FAIL MySQL integration: " . $error->getMessage() . "\n");
    $resultCode = 1;
} finally {
    if ($created) foreach ($tables as $table) $app->db()->exec('DROP TABLE IF EXISTS ' . $table);
}
exit($resultCode);
