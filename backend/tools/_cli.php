<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

function dreamstore_cli_app(?string $providedPath = null): \DreamStore\App
{
    $override = getenv('DREAMSTORE_CONFIG');
    $path = $providedPath ?? (is_string($override) && $override !== ''
        ? $override
        : dirname(__DIR__) . '/dreamstore-private/config.php');
    $resolved = realpath($path);
    if ($resolved === false || !is_file($resolved) || preg_match('~/public_html(?:/|$)~i', str_replace('\\', '/', $resolved))) {
        throw new RuntimeException('Use a private absolute configuration path outside public_html.');
    }
    $config = require $resolved;
    if (!is_array($config)) throw new RuntimeException('Configuration is invalid.');
    require_once dirname($resolved) . '/lib/App.php';
    return new \DreamStore\App($config);
}

function dreamstore_hidden_password(string $label): string
{
    if (!stream_isatty(STDIN)) throw new RuntimeException('Run this command in an interactive SSH terminal. Passwords must not be passed as command arguments.');
    if (PHP_OS_FAMILY === 'Windows' || !function_exists('shell_exec') || !function_exists('exec')) {
        throw new RuntimeException('Hidden password entry requires an interactive Linux/cPanel terminal with stty available.');
    }
    $mode = shell_exec('stty -g 2>/dev/null');
    if (!is_string($mode) || trim($mode) === '') throw new RuntimeException('Cannot disable password echo. Use an interactive SSH terminal.');
    fwrite(STDERR, $label);
    exec('stty -echo 2>/dev/null', $output, $status);
    if ($status !== 0) throw new RuntimeException('Cannot disable password echo.');
    try {
        $line = fgets(STDIN, 4096);
        if ($line === false) throw new RuntimeException('Password entry was interrupted.');
        return rtrim($line, "\r\n");
    } finally {
        exec('stty ' . escapeshellarg(trim($mode)) . ' 2>/dev/null');
        fwrite(STDERR, PHP_EOL);
    }
}
