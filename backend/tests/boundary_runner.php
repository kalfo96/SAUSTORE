<?php
declare(strict_types=1);

// Child-process fixture for request-boundary tests. No database connection or
// credentials are needed: every case must fail before reaching PDO.
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
$case = $argv[1] ?? '';
$backend = dirname(__DIR__);
$_SERVER = [
    'DOCUMENT_ROOT' => $backend . '/public',
    'SCRIPT_NAME' => '/api/index.php',
    'SCRIPT_FILENAME' => $backend . '/public/index.php',
    'REQUEST_URI' => '/api/inventory',
    'REQUEST_METHOD' => 'GET',
    'HTTP_HOST' => 'stock.hotel.example',
    'HTTPS' => 'on',
    'REMOTE_ADDR' => '127.0.0.1',
];
putenv('DREAMSTORE_CONFIG=' . $backend . '/private/config.example.php');
switch ($case) {
    case 'https':
        unset($_SERVER['HTTPS']);
        break;
    case 'origin':
        $_SERVER['HTTP_ORIGIN'] = 'https://evil.example';
        break;
    case 'unauthorized':
        break;
    case 'invalid-bearer':
        $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer secret';
        break;
    case 'method':
        $_SERVER['REQUEST_URI'] = '/api/auth/login';
        break;
    case 'json':
        $_SERVER['REQUEST_URI'] = '/api/auth/login';
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_SERVER['CONTENT_TYPE'] = 'application/json';
        break;
    case 'content-type':
        $_SERVER['REQUEST_URI'] = '/api/auth/login';
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_SERVER['CONTENT_TYPE'] = 'text/plain';
        break;
    case 'size':
        $_SERVER['CONTENT_LENGTH'] = 9000000;
        break;
    case 'route':
        $_SERVER['REQUEST_URI'] = '/api/not-a-route';
        break;
    case 'missing-private':
        putenv('DREAMSTORE_CONFIG=' . $backend . '/private/no-config-here.php');
        break;
    case 'public-private':
        putenv('DREAMSTORE_CONFIG=' . $backend . '/public/private_path.example.php');
        break;
    default:
        fwrite(STDERR, "Unknown test case.\n");
        exit(2);
}
register_shutdown_function(static function (): void {
    echo PHP_EOL . json_encode(['httpStatus' => http_response_code()], JSON_THROW_ON_ERROR);
});
require $backend . '/public/index.php';
