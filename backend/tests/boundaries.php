<?php
declare(strict_types=1);

// Exercise the actual public index/bootstrap in isolated PHP child processes.
// All cases reject before database access; no MySQL extension is required.
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
$cases = [
    'https' => [403, 'https_required'],
    'origin' => [403, 'origin_not_allowed'],
    'unauthorized' => [401, 'unauthorized'],
    'invalid-bearer' => [401, 'unauthorized'],
    'method' => [405, 'method_not_allowed'],
    'json' => [400, 'invalid_json'],
    'content-type' => [415, 'json_required'],
    'size' => [413, 'payload_too_large'],
    'route' => [404, 'not_found'],
    'missing-private' => [503, 'server_unavailable'],
    'public-private' => [503, 'server_unavailable'],
];
$failures = 0;
foreach ($cases as $name => [$expectedStatus, $expectedCode]) {
    try {
        $pipes = [];
        $process = proc_open([PHP_BINARY, '-n', __DIR__ . '/boundary_runner.php', $name], [
            0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w'],
        ], $pipes);
        if (!is_resource($process)) throw new RuntimeException('Could not start PHP fixture.');
        fclose($pipes[0]);
        $stdout = stream_get_contents($pipes[1]);
        $stderr = stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        $exitCode = proc_close($process);
        if (!is_string($stdout) || $exitCode !== 0) throw new RuntimeException('Fixture failed.');
        $parts = preg_split('/\r?\n/', trim($stdout));
        if (count($parts) !== 2) throw new RuntimeException('Response contains unexpected output.');
        $body = json_decode($parts[0], true, 64, JSON_THROW_ON_ERROR);
        $status = json_decode($parts[1], true, 64, JSON_THROW_ON_ERROR);
        if (($status['httpStatus'] ?? null) !== $expectedStatus || ($body['error']['code'] ?? null) !== $expectedCode) {
            throw new RuntimeException('Unexpected status/error code.');
        }
        foreach (['REPLACE_WITH', 'SELECT ', 'PDO', 'config.example.php', 'password_hash'] as $sensitive) {
            if (str_contains($parts[0], $sensitive)) throw new RuntimeException('Response leaked implementation/secrets.');
        }
        fwrite(STDOUT, "PASS public request boundary: $name\n");
    } catch (Throwable $error) {
        $failures++;
        fwrite(STDERR, "FAIL $name: " . $error->getMessage() . "\n");
    }
}
fwrite(STDOUT, count($cases) . " request-boundary tests, $failures failures.\n");
exit($failures === 0 ? 0 : 1);
