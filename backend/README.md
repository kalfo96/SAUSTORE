# DreamStore cPanel API

This backend stores one hotel's shared inventory in MySQL/MariaDB. Flutter uses
authenticated HTTPS JSON requests; the database is never exposed to the app.
Deployment instructions are in [CPANEL.md](../docs/CPANEL.md).

Requires PHP 8.2+, PDO MySQL, InnoDB, Apache rewrite support, and an SSL certificate.
Import `schema.sql` once into an empty cPanel database. Upload `public/` into the
web document root's `api/` folder. Place `private/` at
`/home/CPANEL_ACCOUNT/dreamstore-private`, outside every public web root, and copy
`config.example.php` to `config.php`. Set real database credentials only there.
For nested subdomain roots such as `public_html/stock`, copy
`public/private_path.example.php` to `api/private_path.php` and enter the private
configuration's absolute path. `DREAMSTORE_CONFIG` is an alternative server-only
absolute-path environment override. Bootstrap rejects configuration in
`public_html` or the current document root.

Generate a setup token using `php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"`
and set it in private configuration. Open `/api/setup.php` over HTTPS and enter
the token, administrator name/email, and a 12–72-byte password. Setup locks
after the first user; subsequently delete `api/setup.php` and blank the token.
There is no public registration or email/name-based password reset.

## API contract

All errors are `{ "error": { "code": "...", "message": "..." } }`. Login returns
only a token and a user's name/email, never password hashes. Bearer tokens expire
after 12 hours and their SHA-256 representations, not raw tokens, are stored.

| Method | Route | Request | Success |
| --- | --- | --- | --- |
| GET | `/api/health` | None | `status: "ok"`, `schemaVersion: 3` |
| POST | `/api/auth/login` | `email`, `password` | `token`, `user: {name,email}` |
| POST | `/api/auth/logout` | Bearer token | `ok: true` |
| GET | `/api/inventory` | Bearer token | `version`, `data` (snapshot or null) |
| PUT | `/api/inventory` | Bearer; `expectedVersion`, `data` | New `version` |
| DELETE | `/api/inventory` | Bearer; `expectedVersion` | New `version` |

Inventory changes are atomic, version-checked snapshots protected by a locked
singleton database row. A stale version returns HTTP 409 `inventory_conflict`;
the app must refresh before trying the operation again. A network timeout can
mean a write reached the server, so never automatically retry mutations.

Validation checks JSON objects/arrays, schemas 1–4, unique IDs/SKUs, product
references, nonnegative integer money/stock, safe integer values, valid dates,
departments, and stock-movement balance. Original receipt dates, later delivery
dates, recorded timestamps, usage, sales, and reports remain in the snapshot.
The request limit is 8 MB. Archived products retain their history.

All current accounts are trusted hotel administrators with full inventory
access. This is not multi-hotel tenancy or department-restricted permissions.
The snapshot is not a separate normalized reporting database or tamper-proof
append-only audit archive. Keep regular private database backups.

Same-origin access is the default. Separately hosted browsers require exact
HTTPS `allowed_origins` entries; wildcard access is not supported. Proxy HTTPS
headers are not trusted unless the host explicitly guarantees their integrity.
`allow_insecure_local` applies only to localhost hosts and loopback clients for
development; production must leave it false.

## Administrator tools

Upload `tools/` as `/home/CPANEL_ACCOUNT/dreamstore-tools`, never inside a web
root. In an interactive Linux/cPanel SSH terminal:

```sh
php /home/CPANEL_ACCOUNT/dreamstore-tools/reset_admin_password.php admin@example.com
```

The tool prompts twice with password echo disabled and revokes that user's
existing sessions. It accepts an optional absolute private configuration path
after the email. Passwords are never command arguments. It refuses non-terminal
input or hosts where hidden entry is unavailable.

An optional daily cron command removes expired sessions and old login-rate
buckets without deleting stock/history:

```sh
php /home/CPANEL_ACCOUNT/dreamstore-tools/maintenance.php /home/CPANEL_ACCOUNT/dreamstore-private/config.php
```

## Verification

```sh
php backend/tests/run.php
php backend/tests/boundaries.php
php backend/tests/integration.php
```

Pure-PHP validation/security and public request-boundary tests need no database.
The boundary suite launches PHP child processes to verify security/error routes
and private-path guards before database access. Integration tests skip unless
`DREAMSTORE_TEST_ALLOW_CREATE=1` and `DREAMSTORE_TEST_DB_NAME` ends in `_test`.
Set `DREAMSTORE_TEST_DB_HOST`, `PORT`, `USER`, and `PASSWORD` only for a **new,
empty disposable test database**. The script refuses a nonempty database,
creates its own four tables, exercises setup/login/session hashing, dated
round-trip, conflict rollback, password reset, and clear, then drops those test
tables. Do not use production database credentials for tests.

Implementation follows PHP's [password hashing API](https://www.php.net/passwords),
native [PDO MySQL prepared statements](https://www.php.net/manual/en/ref.pdo-mysql.php),
and MySQL [locking reads](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking-reads.html).
