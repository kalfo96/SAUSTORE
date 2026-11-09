<?php
declare(strict_types=1);

require_once __DIR__ . '/helpers.php';

use DreamStore\ApiError;
use DreamStore\InventoryValidator;
use DreamStore\Security;

$tests = [];
$tests['accepts complete dated department snapshot without changing fields'] = static function (): void {
    $data = inventory_fixture();
    $encoded = json_encode($data, JSON_THROW_ON_ERROR);
    test_assert(InventoryValidator::validate($data) === $data, 'Must retain the full object.');
    test_assert(json_encode($data, JSON_THROW_ON_ERROR) === $encoded, 'Validation must not rewrite history.');
};
$tests['accepts legacy arrival and audit timestamp fallbacks'] = static function (): void {
    $data = inventory_fixture();
    $data->schemaVersion = 2;
    unset($data->products[0]->receivedAt);
    foreach ($data->movements as $movement) unset($movement->recordedAt, $movement->department);
    InventoryValidator::validate($data);
};
$tests['accepts schema 4 stock metadata and complete requisition transitions'] = static function (): void {
    $data = inventory_fixture();
    $data->schemaVersion = 4;
    $data->products[0]->unit = 'kg';
    $data->movements[1]->supplierName = 'Hotel Supplies Ltd';
    $data->movements[1]->invoiceNumber = 'INV-204';
    $data->movements[1]->expiryDate = '2027-04-01T00:00:00.000';
    $data->requisitions = [(object) [
        'id' => 'req1',
        'department' => 'housekeeping',
        'requestedBy' => 'Amina',
        'requestedAt' => '2026-09-13T10:00:00.000',
        'status' => 'received',
        'lines' => [(object) [
            'productId' => 'p1',
            'productName' => 'Rice',
            'productSku' => 'KIT-RICE',
            'quantity' => 2,
            'unitCostMinor' => 2000,
            'unit' => 'kg',
        ]],
        'approvedBy' => 'Manager',
        'approvedAt' => '2026-09-13T10:05:00.000',
        'issuedBy' => 'Store keeper',
        'issuedAt' => '2026-09-13T10:10:00.000',
        'receivedBy' => 'Amina',
        'receivedAt' => '2026-09-13T10:15:00.000',
    ]];
    InventoryValidator::validate($data);
    unset($data->requisitions[0]->issuedBy);
    expect_invalid(static fn() => InventoryValidator::validate($data), 'missing issue audit');
};
$tests['rejects unsupported schema and object-shaped collections'] = static function (): void {
    $data = inventory_fixture();
    $data->schemaVersion = 5;
    expect_invalid(static fn() => InventoryValidator::validate($data), 'future schema');
    $data = inventory_fixture();
    $data->products = new stdClass();
    expect_invalid(static fn() => InventoryValidator::validate($data), 'object as array');
};
$tests['rejects negative, floating, string, and unsafe money/quantity'] = static function (): void {
    foreach ([-1, 1.2, '17', true, 9007199254740992] as $quantity) {
        $data = inventory_fixture();
        $data->products[0]->quantity = $quantity;
        expect_invalid(static fn() => InventoryValidator::validate($data), 'invalid quantity');
    }
    $data = inventory_fixture();
    $data->products[0]->unitCostMinor = InventoryValidator::MAX_SAFE_INTEGER;
    expect_invalid(static fn() => InventoryValidator::validate($data), 'unsafe valuation');
};
$tests['rejects duplicate IDs and normalized SKUs'] = static function (): void {
    $data = inventory_fixture();
    $data->products[] = clone $data->products[0];
    expect_invalid(static fn() => InventoryValidator::validate($data), 'duplicate ID');
    $data->products[1]->id = 'p2';
    $data->products[1]->sku = 'kit-rice';
    expect_invalid(static fn() => InventoryValidator::validate($data), 'duplicate SKU');
};
$tests['rejects unbalanced movement and positive consumption'] = static function (): void {
    $data = inventory_fixture();
    $data->movements[1]->quantityAfter = 19;
    expect_invalid(static fn() => InventoryValidator::validate($data), 'ledger equation');
    $data->movements[1]->quantityDelta = 3;
    $data->movements[1]->quantityAfter = 23;
    expect_invalid(static fn() => InventoryValidator::validate($data), 'positive usage');
};
$tests['rejects missing reference and unknown department'] = static function (): void {
    $data = inventory_fixture();
    $data->departmentIssues[0]->productId = 'missing';
    expect_invalid(static fn() => InventoryValidator::validate($data), 'orphan usage');
    $data = inventory_fixture();
    $data->products[0]->department = 'unknown';
    expect_invalid(static fn() => InventoryValidator::validate($data), 'department');
};
$tests['dates reject calendar rollover and accept Dart local/UTC ISO format'] = static function (): void {
    foreach (['2026-09-12T00:00:00.000', '2026-09-12T00:00:00.000123Z', '2026-09-12T08:15:00+03:00', '2024-02-29T00:00:00'] as $value) {
        test_assert(InventoryValidator::validDate($value), "Date should be valid: $value");
    }
    foreach (['2026-02-30T00:00:00', '2026-09-12T24:00:00', 'not-a-date', '2026-09-12', '2026-09-12T00:00:00+14:30'] as $value) {
        test_assert(!InventoryValidator::validDate($value), "Date should be invalid: $value");
    }
    $data = inventory_fixture();
    $data->products[0]->receivedAt = '2026-02-30T00:00:00';
    expect_invalid(static fn() => InventoryValidator::validate($data), 'bad receipt date');
};
$tests['session tokens are random and only SHA256 representation is stored'] = static function (): void {
    $a = Security::token();
    $b = Security::token();
    test_assert(strlen($a) === 64 && ctype_xdigit($a) && $a !== $b, 'Tokens need random 256-bit entropy.');
    test_assert(Security::tokenHash($a) !== $a && strlen(Security::tokenHash($a)) === 64, 'Hash is not raw token.');
};
$tests['origin checks reject wildcard, null, credentials, paths and spoofed proxy'] = static function (): void {
    $server = ['HTTPS' => 'on', 'HTTP_HOST' => 'stock.hotel.example'];
    $config = ['allowed_origins' => ['https://office.hotel.example']];
    test_assert(Security::originAllowed('https://stock.hotel.example', $server, $config), 'Same origin');
    test_assert(Security::originAllowed('https://office.hotel.example', $server, $config), 'Explicit origin');
    foreach (['null', '*', 'https://evil.example', 'https://stock.hotel.example.evil', 'https://user@stock.hotel.example', 'https://stock.hotel.example/', 'https://stock.hotel.example?x=1'] as $origin) {
        test_assert(!Security::originAllowed($origin, $server, $config), "Forbidden origin: $origin");
    }
    test_assert(!Security::isHttps(['HTTP_X_FORWARDED_PROTO' => 'https'], []), 'Do not trust arbitrary proxy header.');
};
$tests['insecure local mode cannot allow a public HTTP client'] = static function (): void {
    test_assert(Security::localHttpAllowed(['REMOTE_ADDR' => '127.0.0.1', 'HTTP_HOST' => 'localhost:8080'], ['allow_insecure_local' => true]), 'Explicit localhost');
    test_assert(!Security::localHttpAllowed(['REMOTE_ADDR' => '1.2.3.4', 'HTTP_HOST' => 'localhost'], ['allow_insecure_local' => true]), 'Not a local client');
    test_assert(!Security::localHttpAllowed(['REMOTE_ADDR' => '127.0.0.1', 'HTTP_HOST' => 'stock.hotel.example'], ['allow_insecure_local' => true]), 'Not a local host');
};
$tests['password policy prevents short or bcrypt-truncated credentials'] = static function (): void {
    Security::validatePassword('a-strong-password-2026');
    expect_invalid(static fn() => Security::validatePassword('short'), 'short password');
    expect_invalid(static fn() => Security::validatePassword(str_repeat('x', 73)), 'bcrypt byte overflow');
    expect_invalid(static fn() => Security::validatePassword("strong-password\0oops"), 'null byte');
};
$tests['stale versions produce the specified conflict code and status'] = static function (): void {
    Security::conflictIfStale(3, 3);
    try {
        Security::conflictIfStale(3, 4);
    } catch (ApiError $error) {
        test_assert($error->status === 409 && $error->errorCode === 'inventory_conflict', 'Conflict contract');
        return;
    }
    throw new RuntimeException('Expected a stale version conflict.');
};

$failures = 0;
foreach ($tests as $name => $test) {
    try {
        $test();
        fwrite(STDOUT, "PASS $name\n");
    } catch (Throwable $error) {
        $failures++;
        fwrite(STDERR, "FAIL $name: " . $error->getMessage() . "\n");
    }
}
fwrite(STDOUT, count($tests) . " tests, $failures failures.\n");
exit($failures === 0 ? 0 : 1);
