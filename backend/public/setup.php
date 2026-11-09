<?php
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';
$app = dreamstore_app();
$message = '';
$success = false;
try {
    $app->enforceWebSecurity();
    if (!$app->setupEnabled()) {
        \DreamStore\App::error(403, 'setup_disabled', 'Setup is disabled. Contact the hotel administrator.');
    }
    $method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
    if (!in_array($method, ['GET', 'POST'], true)) {
        header('Allow: GET, POST');
        \DreamStore\App::error(405, 'method_not_allowed', 'Use the setup form.');
    }
    if ($method === 'POST') {
        $app->createAdministrator($_POST);
        $success = true;
        $message = 'Administrator created. Delete api/setup.php, clear the private setup_token, and sign in to DreamStore.';
    }
} catch (\DreamStore\ApiError $error) {
    if (in_array($error->errorCode, ['https_required', 'origin_not_allowed', 'payload_too_large'], true)) {
        \DreamStore\App::error($error->status, $error->errorCode, $error->getMessage());
    }
    http_response_code($error->status);
    $message = $error->getMessage();
} catch (InvalidArgumentException $error) {
    http_response_code(422);
    $message = $error->getMessage();
} catch (Throwable $error) {
    \DreamStore\App::serverError($error);
}
header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>DreamStore · Secure setup</title>
    <link rel="stylesheet" href="setup.css">
</head>
<body>
<main>
    <div class="eyebrow">DREAMSTORE / LIVE WORKSPACE</div>
    <h1>One hotel.<br>One shared inventory.</h1>
    <p>Create your first administrator securely. This page locks itself after setup.</p>
    <?php if ($message !== ''): ?>
        <div class="notice" role="status"><?= htmlspecialchars($message, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?></div>
    <?php endif; ?>
    <?php if (!$success): ?>
    <form method="post" action="setup.php" autocomplete="off">
        <label for="setup-token">Private setup token</label>
        <input id="setup-token" name="setup_token" type="password" required minlength="64" maxlength="64" autocomplete="off">
        <label for="name">Administrator name</label>
        <input id="name" name="name" type="text" required maxlength="160" autocomplete="name">
        <label for="email">Work email</label>
        <input id="email" name="email" type="email" required maxlength="254" autocomplete="email">
        <label for="password">Password (12–72 bytes)</label>
        <input id="password" name="password" type="password" required minlength="12" maxlength="72" autocomplete="new-password">
        <label for="confirm">Confirm password</label>
        <input id="confirm" name="confirm_password" type="password" required minlength="12" maxlength="72" autocomplete="new-password">
        <button type="submit">Create secure workspace</button>
    </form>
    <?php endif; ?>
    <footer>HTTPS only · MySQL-backed · No public registration</footer>
</main>
</body>
</html>
