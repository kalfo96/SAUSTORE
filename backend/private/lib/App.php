<?php
declare(strict_types=1);

namespace DreamStore;

use InvalidArgumentException;
use PDO;
use RuntimeException;
use stdClass;
use Throwable;

require_once __DIR__ . '/Validation.php';

final class ApiError extends RuntimeException
{
    public function __construct(public readonly int $status, public readonly string $errorCode, string $message)
    {
        parent::__construct($message);
    }
}

final class Security
{
    public static function token(): string
    {
        return bin2hex(random_bytes(32));
    }

    public static function tokenHash(string $token): string
    {
        return hash('sha256', $token);
    }

    public static function isHttps(array $server, array $config): bool
    {
        if (isset($server['HTTPS']) && $server['HTTPS'] !== '' && strtolower((string) $server['HTTPS']) !== 'off') return true;
        return ($config['trust_proxy_https'] ?? false) === true
            && strtolower((string) ($server['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
    }

    public static function localHttpAllowed(array $server, array $config): bool
    {
        if (($config['allow_insecure_local'] ?? false) !== true) return false;
        $remote = (string) ($server['REMOTE_ADDR'] ?? '');
        $host = strtolower((string) ($server['HTTP_HOST'] ?? ''));
        return in_array($remote, ['127.0.0.1', '::1'], true)
            && preg_match('/^(?:localhost|127\.0\.0\.1|\[::1\])(?::\d{1,5})?$/D', $host) === 1;
    }

    public static function originAllowed(string $origin, array $server, array $config): bool
    {
        if ($origin === '' || $origin === 'null' || !self::validOrigin($origin)) return false;
        $host = strtolower((string) ($server['HTTP_HOST'] ?? ''));
        if (!preg_match('/^(?:[a-z0-9.-]+|\[[a-f0-9:]+\])(?::\d{1,5})?$/D', $host)) return false;
        $same = (self::isHttps($server, $config) ? 'https://' : 'http://') . $host;
        if (hash_equals($same, strtolower($origin))) return true;
        foreach ($config['allowed_origins'] ?? [] as $allowed) {
            if (is_string($allowed) && self::validOrigin($allowed) && hash_equals(strtolower($allowed), strtolower($origin))) return true;
        }
        return false;
    }

    public static function validOrigin(string $value): bool
    {
        $parts = parse_url($value);
        return is_array($parts)
            && isset($parts['scheme'], $parts['host'])
            && in_array(strtolower($parts['scheme']), ['https', 'http'], true)
            && !isset($parts['user']) && !isset($parts['pass'])
            && !isset($parts['query']) && !isset($parts['fragment'])
            && !isset($parts['path'])
            && !str_contains($value, "\r") && !str_contains($value, "\n")
            && preg_match('/^[a-z0-9.-]+$|^\[[a-f0-9:]+\]$/Di', $parts['host']) === 1;
    }

    public static function validatePassword(string $password): void
    {
        // PASSWORD_DEFAULT is currently bcrypt: explicitly cap its byte length
        // rather than silently accepting passwords truncated at 72 bytes.
        if (strlen($password) < 12 || strlen($password) > 72 || str_contains($password, "\0")) {
            throw new InvalidArgumentException('Use a password between 12 and 72 bytes.');
        }
    }

    public static function validateEmail(mixed $value): string
    {
        if (!is_string($value) || strlen($value) > 254 || filter_var(trim($value), FILTER_VALIDATE_EMAIL) === false) {
            throw new InvalidArgumentException('Enter a valid email address.');
        }
        return strtolower(trim($value));
    }

    public static function conflictIfStale(int $expected, int $actual): void
    {
        if ($expected !== $actual) {
            throw new ApiError(409, 'inventory_conflict', 'Stock changed on another device. Refresh and retry.');
        }
    }
}

final class App
{
    public const MAX_BODY_BYTES = 8388608;
    private ?PDO $connection = null;

    public function __construct(public readonly array $config)
    {
        if (PHP_VERSION_ID < 80200) throw new RuntimeException('PHP 8.2 or newer is required.');
        if (!isset($config['database']) || !is_array($config['database'])) throw new RuntimeException('Database configuration is missing.');
        if (!is_array($config['allowed_origins'] ?? [])) throw new RuntimeException('Origin configuration is invalid.');
        foreach ($config['allowed_origins'] ?? [] as $origin) {
            if (!is_string($origin) || !Security::validOrigin($origin) || !str_starts_with($origin, 'https://')) {
                throw new RuntimeException('Allowed origins must be exact HTTPS origins.');
            }
        }
        $timezone = $config['timezone'] ?? 'Africa/Dar_es_Salaam';
        if (!is_string($timezone) || !date_default_timezone_set($timezone)) throw new RuntimeException('Timezone configuration is invalid.');
    }

    public function db(): PDO
    {
        if ($this->connection !== null) return $this->connection;
        $db = $this->config['database'];
        foreach (['host', 'name', 'user', 'password'] as $field) {
            if (!isset($db[$field]) || !is_string($db[$field]) || $db[$field] === '' || str_contains($db[$field], "\0")) {
                throw new RuntimeException('Database configuration is incomplete.');
            }
        }
        if (!preg_match('/^[a-z0-9._-]+$/Di', $db['host']) || !preg_match('/^[a-z0-9_$-]+$/Di', $db['name'])) {
            throw new RuntimeException('Database connection settings are invalid.');
        }
        $port = $db['port'] ?? 3306;
        if (!is_int($port) || $port < 1 || $port > 65535) throw new RuntimeException('Database port is invalid.');
        $dsn = 'mysql:host=' . $db['host'] . ';port=' . $port . ';dbname=' . $db['name'] . ';charset=utf8mb4';
        $this->connection = new PDO($dsn, $db['user'], $db['password'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_TIMEOUT => 10,
        ]);
        $this->connection->exec("SET time_zone = '+00:00'");
        return $this->connection;
    }

    public function enforceWebSecurity(): void
    {
        header('Cache-Control: no-store, private, max-age=0');
        header('Pragma: no-cache');
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: no-referrer');
        header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
        header("Content-Security-Policy: default-src 'none'; style-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
        if (Security::isHttps($_SERVER, $this->config)) {
            header('Strict-Transport-Security: max-age=31536000');
        } elseif (!Security::localHttpAllowed($_SERVER, $this->config)) {
            throw new ApiError(403, 'https_required', 'Use the secure HTTPS address for DreamStore.');
        }
        $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
        if ($origin !== null) {
            if (!is_string($origin) || !Security::originAllowed($origin, $_SERVER, $this->config)) {
                throw new ApiError(403, 'origin_not_allowed', 'This website is not allowed to access DreamStore.');
            }
            header('Access-Control-Allow-Origin: ' . $origin);
            header('Vary: Origin');
            header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
            header('Access-Control-Allow-Headers: Authorization, Content-Type');
            header('Access-Control-Max-Age: 600');
        }
        $contentLength = $_SERVER['CONTENT_LENGTH'] ?? '0';
        if (is_numeric($contentLength) && (float) $contentLength > self::MAX_BODY_BYTES) {
            throw new ApiError(413, 'payload_too_large', 'The inventory is too large for this server. Maximum request size is 8 MB.');
        }
    }

    public function serve(): never
    {
        try {
            $this->enforceWebSecurity();
            $method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
            if ($method === 'OPTIONS') {
                http_response_code(204);
                exit;
            }
            $route = $this->route();
            if ($route === 'health') {
                $this->requireMethod($method, ['GET']);
                if ($this->db()->query('SELECT version FROM dreamstore_inventory WHERE id = 1')->fetchColumn() === false) {
                    throw new RuntimeException('Inventory singleton is missing.');
                }
                self::respond(['status' => 'ok', 'service' => 'DreamStore API', 'schemaVersion' => 3]);
            }
            if ($route === 'auth/login') {
                $this->requireMethod($method, ['POST']);
                self::respond($this->login($this->readJson()));
            }
            if ($route === 'auth/logout') {
                $this->requireMethod($method, ['POST']);
                $user = $this->authenticate();
                $query = $this->db()->prepare('DELETE FROM dreamstore_sessions WHERE token_hash = ? AND user_id = ?');
                $query->execute([$user['token_hash'], $user['id']]);
                self::respond(['ok' => true]);
            }
            if ($route === 'inventory') {
                $this->requireMethod($method, ['GET', 'PUT', 'DELETE']);
                $user = $this->authenticate();
                if ($method === 'GET') self::respond($this->getInventory());
                $body = $this->readJson();
                $expected = InventoryValidator::integer($body, 'expectedVersion');
                $data = $method === 'DELETE' ? null : InventoryValidator::validate($body->data ?? null);
                self::respond(['version' => $this->saveInventory($expected, $data, (int) $user['id'])]);
            }
            throw new ApiError(404, 'not_found', 'This API endpoint does not exist.');
        } catch (ApiError $error) {
            self::error($error->status, $error->errorCode, $error->getMessage());
        } catch (InvalidArgumentException $error) {
            self::error(422, 'invalid_inventory', $error->getMessage());
        } catch (Throwable $error) {
            self::serverError($error);
        }
    }

    public function login(stdClass $body): array
    {
        try {
            $email = Security::validateEmail($body->email ?? null);
        } catch (InvalidArgumentException $error) {
            throw new ApiError(400, 'invalid_login', $error->getMessage());
        }
        $password = $body->password ?? null;
        if (!is_string($password) || $password === '' || strlen($password) > 72 || str_contains($password, "\0")) {
            throw new ApiError(400, 'invalid_login', 'Enter your email and password.');
        }
        $this->consumeLoginLimits($email);
        $db = $this->db();
        $db->beginTransaction();
        try {
            // Serialize against password resets: an old password cannot create a
            // fresh session after the reset has revoked this account's sessions.
            $query = $db->prepare('SELECT id, name, email, password_hash, role, is_active FROM dreamstore_users WHERE email = ? LIMIT 1 FOR UPDATE');
            $query->execute([$email]);
            $user = $query->fetch();
            // A fixed bcrypt hash gives missing accounts a verification workload.
            $dummyHash = '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi.';
            $valid = password_verify($password, $user === false ? $dummyHash : $user['password_hash']);
            if ($user === false || !$valid || (int) $user['is_active'] !== 1 || $user['role'] !== 'admin') {
                throw new ApiError(401, 'invalid_credentials', 'The email or password is incorrect.');
            }
            if (password_needs_rehash($user['password_hash'], PASSWORD_DEFAULT)) {
                $update = $db->prepare('UPDATE dreamstore_users SET password_hash = ? WHERE id = ?');
                $update->execute([password_hash($password, PASSWORD_DEFAULT), $user['id']]);
            }
            $token = Security::token();
            $now = time();
            $query = $db->prepare('INSERT INTO dreamstore_sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)');
            $query->execute([Security::tokenHash($token), $user['id'], gmdate('Y-m-d H:i:s', $now), gmdate('Y-m-d H:i:s', $now + 43200)]);
            $db->commit();
            return ['token' => $token, 'user' => ['name' => $user['name'], 'email' => $user['email']]];
        } catch (Throwable $error) {
            if ($db->inTransaction()) $db->rollBack();
            throw $error;
        }
    }

    public function authenticate(): array
    {
        $header = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
        if (!preg_match('/^Bearer ([a-f0-9]{64})$/Di', $header, $match)) {
            throw new ApiError(401, 'unauthorized', 'Please sign in to your live DreamStore account.');
        }
        $tokenHash = Security::tokenHash(strtolower($match[1]));
        $query = $this->db()->prepare('SELECT u.id, u.name, u.email, u.role, u.is_active FROM dreamstore_sessions s JOIN dreamstore_users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > UTC_TIMESTAMP() LIMIT 1');
        $query->execute([$tokenHash]);
        $user = $query->fetch();
        if ($user === false || (int) $user['is_active'] !== 1) {
            throw new ApiError(401, 'session_expired', 'Your session has expired. Please sign in again.');
        }
        if ($user['role'] !== 'admin') throw new ApiError(403, 'forbidden', 'An administrator account is required.');
        $user['token_hash'] = $tokenHash;
        return $user;
    }

    public function getInventory(): array
    {
        $row = $this->db()->query('SELECT version, snapshot FROM dreamstore_inventory WHERE id = 1')->fetch();
        if ($row === false) throw new RuntimeException('Inventory singleton is missing.');
        $data = $row['snapshot'] === null ? null : json_decode($row['snapshot'], false, 64, JSON_THROW_ON_ERROR);
        return ['version' => (int) $row['version'], 'data' => $data];
    }

    public function saveInventory(int $expectedVersion, ?stdClass $data, int $userId): int
    {
        $serialized = $data === null ? null : json_encode(InventoryValidator::validate($data), JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($serialized !== null && strlen($serialized) > self::MAX_BODY_BYTES - 1024) {
            throw new ApiError(413, 'payload_too_large', 'The inventory is too large for this server. Maximum request size is 8 MB.');
        }
        $db = $this->db();
        $db->beginTransaction();
        try {
            $row = $db->query('SELECT version FROM dreamstore_inventory WHERE id = 1 FOR UPDATE')->fetch();
            if ($row === false) throw new RuntimeException('Inventory singleton is missing.');
            $version = (int) $row['version'];
            Security::conflictIfStale($expectedVersion, $version);
            if ($version >= InventoryValidator::MAX_SAFE_INTEGER) throw new RuntimeException('Inventory version is out of range.');
            $next = $version + 1;
            $query = $db->prepare('UPDATE dreamstore_inventory SET version = ?, snapshot = ?, updated_at = UTC_TIMESTAMP(), updated_by = ? WHERE id = 1');
            $query->execute([$next, $serialized, $userId]);
            $db->commit();
            return $next;
        } catch (Throwable $error) {
            if ($db->inTransaction()) $db->rollBack();
            throw $error;
        }
    }

    public function hasAdministrator(): bool
    {
        return $this->db()->query('SELECT id FROM dreamstore_users LIMIT 1')->fetchColumn() !== false;
    }

    public function setupEnabled(): bool
    {
        $token = $this->config['setup_token'] ?? '';
        return is_string($token) && preg_match('/^[a-f0-9]{64}$/Di', $token) === 1 && !$this->hasAdministrator();
    }

    public function createAdministrator(array $input): void
    {
        $configured = $this->config['setup_token'] ?? '';
        $provided = $input['setup_token'] ?? '';
        if (!$this->setupEnabled() || !is_string($provided) || !hash_equals($configured, $provided)) {
            throw new ApiError(403, 'setup_disabled', 'Setup is unavailable or the setup token is incorrect.');
        }
        $name = $input['name'] ?? null;
        if (!is_string($name) || trim($name) === '' || strlen($name) > 160 || str_contains($name, "\0")) throw new InvalidArgumentException('Enter an administrator name.');
        $email = Security::validateEmail($input['email'] ?? null);
        $password = $input['password'] ?? null;
        if (!is_string($password)) throw new InvalidArgumentException('Enter an administrator password.');
        Security::validatePassword($password);
        if (!isset($input['confirm_password']) || !is_string($input['confirm_password']) || !hash_equals($password, $input['confirm_password'])) throw new InvalidArgumentException('The passwords do not match.');
        $hash = password_hash($password, PASSWORD_DEFAULT);
        $db = $this->db();
        $db->beginTransaction();
        try {
            // The singleton row serializes bootstrap attempts; the second request
            // sees the first committed user and cannot create another account.
            $singleton = $db->query('SELECT id FROM dreamstore_inventory WHERE id = 1 FOR UPDATE')->fetchColumn();
            if ($singleton === false) throw new RuntimeException('Import schema.sql before setup.');
            if ($this->hasAdministrator()) throw new ApiError(403, 'setup_disabled', 'An administrator already exists. Setup is disabled.');
            $query = $db->prepare("INSERT INTO dreamstore_users (name, email, password_hash, role) VALUES (?, ?, ?, 'admin')");
            $query->execute([trim($name), $email, $hash]);
            $db->commit();
        } catch (Throwable $error) {
            if ($db->inTransaction()) $db->rollBack();
            throw $error;
        }
    }

    public function maintenance(): array
    {
        $expired = $this->db()->exec('DELETE FROM dreamstore_sessions WHERE expires_at <= UTC_TIMESTAMP()');
        $query = $this->db()->prepare('DELETE FROM dreamstore_rate_limits WHERE window_start < ?');
        $query->execute([time() - 86400]);
        return ['expired_sessions_removed' => $expired, 'old_rate_buckets_removed' => $query->rowCount()];
    }

    public function resetPassword(string $email, string $password): void
    {
        Security::validatePassword($password);
        $db = $this->db();
        $db->beginTransaction();
        try {
            $query = $db->prepare("SELECT id FROM dreamstore_users WHERE email = ? AND role = 'admin' FOR UPDATE");
            $query->execute([Security::validateEmail($email)]);
            $id = $query->fetchColumn();
            if ($id === false) throw new InvalidArgumentException('That administrator does not exist.');
            $query = $db->prepare('UPDATE dreamstore_users SET password_hash = ? WHERE id = ?');
            $query->execute([password_hash($password, PASSWORD_DEFAULT), $id]);
            $query = $db->prepare('DELETE FROM dreamstore_sessions WHERE user_id = ?');
            $query->execute([$id]);
            $db->commit();
        } catch (Throwable $error) {
            if ($db->inTransaction()) $db->rollBack();
            throw $error;
        }
    }

    private function consumeLoginLimits(string $email): void
    {
        $remote = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        $buckets = [hash('sha256', 'ip:' . $remote) => 30, hash('sha256', 'email:' . $email) => 12];
        ksort($buckets);
        $now = time();
        $db = $this->db();
        $db->beginTransaction();
        $limited = false;
        try {
            foreach ($buckets as $bucket => $limit) {
                $query = $db->prepare('INSERT IGNORE INTO dreamstore_rate_limits (bucket_hash, window_start, attempts) VALUES (?, ?, 0)');
                $query->execute([$bucket, $now]);
                $query = $db->prepare('SELECT window_start, attempts FROM dreamstore_rate_limits WHERE bucket_hash = ? FOR UPDATE');
                $query->execute([$bucket]);
                $row = $query->fetch();
                $window = (int) $row['window_start'];
                $attempts = (int) $row['attempts'];
                if ($window <= $now - 900) {
                    $window = $now;
                    $attempts = 0;
                }
                $attempts = min($attempts + 1, 1000000);
                $query = $db->prepare('UPDATE dreamstore_rate_limits SET window_start = ?, attempts = ? WHERE bucket_hash = ?');
                $query->execute([$window, $attempts, $bucket]);
                if ($attempts > $limit) $limited = true;
            }
            $db->commit();
        } catch (Throwable $error) {
            if ($db->inTransaction()) $db->rollBack();
            throw $error;
        }
        if ($limited) {
            header('Retry-After: 900');
            throw new ApiError(429, 'rate_limited', 'Too many sign-in attempts. Please try again in 15 minutes.');
        }
    }

    private function readJson(): stdClass
    {
        if (!str_starts_with(strtolower((string) ($_SERVER['CONTENT_TYPE'] ?? '')), 'application/json')) {
            throw new ApiError(415, 'json_required', 'Send this request as application/json.');
        }
        $stream = fopen('php://input', 'rb');
        if ($stream === false) throw new RuntimeException('Cannot read the request body.');
        $raw = stream_get_contents($stream, self::MAX_BODY_BYTES + 1);
        fclose($stream);
        if ($raw === false) throw new RuntimeException('Cannot read the request body.');
        if (strlen($raw) > self::MAX_BODY_BYTES) throw new ApiError(413, 'payload_too_large', 'Maximum request size is 8 MB.');
        try {
            $body = json_decode($raw, false, 64, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new ApiError(400, 'invalid_json', 'The request body is not valid JSON.');
        }
        if (!$body instanceof stdClass) throw new ApiError(400, 'invalid_json', 'The request body must be a JSON object.');
        return $body;
    }

    private function route(): string
    {
        $path = parse_url((string) ($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH);
        $base = str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? '/api/index.php')));
        $prefix = rtrim($base, '/') . '/';
        if (!is_string($path) || !str_starts_with($path, $prefix)) throw new ApiError(404, 'not_found', 'This API endpoint does not exist.');
        return trim(substr($path, strlen($prefix)), '/');
    }

    private function requireMethod(string $method, array $allowed): void
    {
        if (!in_array($method, $allowed, true)) {
            header('Allow: ' . implode(', ', $allowed));
            throw new ApiError(405, 'method_not_allowed', 'This request method is not supported.');
        }
    }

    public static function respond(array $body, int $status = 200): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($body, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    public static function error(int $status, string $code, string $message): never
    {
        self::respond(['error' => ['code' => $code, 'message' => $message]], $status);
    }

    public static function serverError(Throwable $error): never
    {
        // Do not echo/log SQL text, configuration, passwords, tokens, or snapshots.
        error_log('DreamStore API server error (' . get_class($error) . '). Check private configuration and database schema.');
        self::error(503, 'server_unavailable', 'DreamStore is temporarily unavailable. Please contact the hotel administrator.');
    }
}
