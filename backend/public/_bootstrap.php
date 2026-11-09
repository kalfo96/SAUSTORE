<?php
declare(strict_types=1);

// Only included by index.php/setup.php; Apache also denies direct web access.
if (realpath((string) ($_SERVER['SCRIPT_FILENAME'] ?? '')) === __FILE__) {
    http_response_code(404);
    exit;
}

function dreamstore_app(): \DreamStore\App
{
    try {
        $override = getenv('DREAMSTORE_CONFIG');
        $path = is_string($override) && $override !== ''
            ? $override
            : (is_file(__DIR__ . '/private_path.php')
                ? require __DIR__ . '/private_path.php'
                : dirname(__DIR__, 2) . '/dreamstore-private/config.php');
        if (!is_string($path) || !preg_match('/^(?:\/|[a-z]:[\\\\\/])/i', $path)) throw new RuntimeException('Private configuration path must be absolute.');
        $resolved = realpath($path);
        if ($resolved === false || !is_file($resolved) || !is_readable($resolved)) throw new RuntimeException('Private configuration is missing.');
        $normalized = strtolower(str_replace('\\', '/', $resolved));
        $documentRoot = realpath((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''));
        $publicPrefix = $documentRoot === false ? null : rtrim(strtolower(str_replace('\\', '/', $documentRoot)), '/') . '/';
        if (preg_match('~/public_html(?:/|$)~', $normalized)
            || ($publicPrefix !== null && str_starts_with($normalized, $publicPrefix))) {
            throw new RuntimeException('Private configuration must be outside all public web roots.');
        }
        $path = $resolved;
        $config = require $path;
        if (!is_array($config)) throw new RuntimeException('Private configuration is invalid.');
        require_once dirname($path) . '/lib/App.php';
        return new \DreamStore\App($config);
    } catch (Throwable $error) {
        error_log('DreamStore bootstrap failed (' . get_class($error) . ').');
        http_response_code(503);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        header('X-Content-Type-Options: nosniff');
        echo '{"error":{"code":"server_unavailable","message":"DreamStore is not configured. Please contact the hotel administrator."}}';
        exit;
    }
}
