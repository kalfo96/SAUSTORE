# DreamStore live hosting on cPanel

The cPanel build connects to a PHP API and one shared MySQL/MariaDB database.
Staff using the same live site see the same hotel's products, dated deliveries,
sales, department usage, and reports. The database is not created merely by
building or uploading the Flutter files: complete the installation below.

These instructions use `https://stock.example.com` as a placeholder for your
subdomain. Replace it with the actual hostname throughout.

DirectAdmin can run the same PHP/Flutter package. Its menu names and document
roots differ from cPanel: verify the configured HTTP **and HTTPS** roots in
**Subdomain Management > Document Root Override**. A folder named
`dreamstore-public` is served only when configured as that subdomain's root.

## What you need

- A cPanel account that supports a subdomain, HTTPS/AutoSSL, Apache/LiteSpeed
  rewrite rules, PHP 8.2 or newer, and the `pdo_mysql` extension.
- A MySQL/MariaDB database and a dedicated database user.
- File Manager or SFTP access. cPanel Terminal/SSH is recommended for password
  recovery, token generation, and maintenance.
- A current Flutter SDK on the development computer.

The web app and API normally use the same HTTPS subdomain. This avoids CORS
configuration; the public build contains `/api/`, never a database password.
Do not use plain HTTP for live sign-in.

## 1. Export existing local data first

Before changing the old app or URL, open **Settings**, export its JSON backup,
and keep a second copy somewhere safe. A new hostname has different browser
storage. Live mode deliberately does not silently upload local inventory or
reuse the old device-local password.

## 2. Build the deployment ZIP

From the project directory in PowerShell:

```powershell
.\scripts\build_cpanel.ps1
```

The script installs Flutter dependencies, checks analysis, runs tests, and
builds the release web application with `config/cpanel.json`. It bundles the
renderer locally, then creates a fresh ZIP and an uncompressed copy under
`dist/cpanel-linux-<timestamp>-<unique-id>`. Existing deployment packages are preserved.
The ZIP writer uses forward slashes in actual archive entry names so Linux
hosts create real nested directories, including `api/` and `assets/`. It runs
portable ZIP regression checks before building the application.
When PHP CLI is installed locally, the script also checks backend syntax and
runs its validation/security and public request-boundary tests. Without PHP
CLI those checks must be run separately on a PHP-enabled machine. Real MySQL
integration still requires a configured disposable test database or the live
smoke checks in step 8.

The package contains:

```text
public_html/                 Upload CONTENTS to the subdomain document root
  .htaccess                  Flutter routing and browser security headers
  api/                       PHP API entry points and API rewrite rules
dreamstore-private/          Upload outside ALL public document roots
  config.example.php         Copy to config.php and fill in ON THE SERVER
  .htaccess                  Additional deny-access protection
  lib/                       Backend PHP source
dreamstore-tools/            Upload outside ALL public document roots
schema.sql                   Import using phpMyAdmin; do not publish
INSTALL.md                   This document; do not publish
README.md                    Package layout reminder; do not publish
```

A second archive, `dreamstore-public-linux-<timestamp>-<unique-id>.zip`, contains
**only public app/API files at the ZIP root**. Extract it directly into an
already configured subdomain document root, such as `dreamstore-public`.
It does not include the private PHP library, tools, or SQL: install those from
the full `cpanel-linux` package as described below.

There are no real DB credentials, administrator passwords, or setup tokens in
the ZIP. The script excludes live `config.php` and private runtime files. Do
not share your edited server configuration or database backups publicly.

For an explicit HTTPS API URL (usually unnecessary for the web build):

```powershell
.\scripts\build_cpanel.ps1 -ApiBaseUrl 'https://stock.example.com/api/'
```

Native mobile apps cannot resolve `/api/` relative to a website. This project
has a separate Android production configuration containing the public HTTPS API
address and no secrets:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_android_release.ps1
```

Complete the release signing steps in `docs/ANDROID_RELEASE.md` first.

## 3. Create the subdomain and choose a safe document root

In cPanel **Domains**, create your stock-management subdomain. Prefer a
dedicated document root outside the main website's `public_html`, for example:

```text
/home/ACCOUNT/
  dreamstore-public/         Document root of stock.example.com
    index.html
    .htaccess
    api/
  dreamstore-private/        Not a document root and not within public_html
    config.php
    config.example.php
    lib/
  dreamstore-tools/          Not public
```

Replace `ACCOUNT` with your real cPanel username. Upload the **contents** of
the package's `public_html` folder into `dreamstore-public`; do not create
`dreamstore-public/public_html`. The package uses a conventional folder name,
but its contents belong in the subdomain's selected document root.

For a main-domain deployment, `/home/ACCOUNT/public_html` can be the public
root instead, with the same private/tool folders under `/home/ACCOUNT`.

The default PHP loader expects `dreamstore-private` alongside the public root.
Do not place configuration under `public_html`, even for a subdomain. If your
host only permits a nested root such as `public_html/stock`, use the explicit
private-path option in step 6 or ask your host to permit a separate document root.

In File Manager enable **Show Hidden Files** and check that both public
`.htaccess` files were uploaded. The public SPA rewrite reserves `/api/` for
PHP; missing API rewrite rules can turn API requests into Flutter HTML pages.
Leave `schema.sql`, the ZIP, installation documents, and backups outside the
public root. Extract the ZIP in an account-private temporary folder, then move
only the appropriate folders into their destinations.

## 4. Enable HTTPS and PHP

Use cPanel **SSL/TLS Status** to run AutoSSL for the subdomain. Wait for a valid
certificate, then enable **Force HTTPS Redirect** for the domain. Visit the
HTTPS URL and confirm there is no certificate warning.

In **MultiPHP Manager** or your host's PHP selector choose PHP 8.2 or newer.
Enable `pdo_mysql`. Use production error logging with `display_errors` off.
Keep logs outside the document root. Do not enable insecure-local mode on a
hosted site. A reverse-proxy/CDN HTTPS override is only for a trusted proxy that
your hosting provider has configured; leave it disabled otherwise.

## 5. Create and import the database

In cPanel **MySQL Databases** or **Database Wizard**:

1. Create a database, for example `ACCOUNT_dreamstore`.
2. Create a separate user, for example `ACCOUNT_stockapp`, with a generated
   strong database password.
3. Add that user to that database. During installation grant the permissions
   needed to import the schema; afterward the application's runtime user only
   needs `SELECT`, `INSERT`, `UPDATE`, and `DELETE` on that database.
4. Open **phpMyAdmin**, select the new database, and import package `schema.sql`.

Use the **full prefixed** database and username cPanel shows, not just the
unprefixed suffix. DB host is often `localhost`, but use your provider's actual
host and port. Do not expose the database publicly or enable arbitrary remote
MySQL access. This app's PHP API is the only database-facing client.

The schema stores one versioned inventory snapshot together with secure
administrator credentials, expiring sessions, and login rate-limit records.
It is a single-hotel deployment, not a multi-tenant accounting system. SQL
tables are application persistence, not one analytics table per stock item.

## 6. Configure the private backend

Outside the public root, copy `dreamstore-private/config.example.php` to
`dreamstore-private/config.php`. Edit that new file on the server:

- `database`: set `host`, `port`, `name`, `user`, and `password`.
- `setup_token`: set a randomly generated 64-character hexadecimal token for
  first-administrator setup. Never put this token in a URL or a Flutter define.
- `timezone`: keep `Africa/Dar_es_Salaam` unless the hotel's timezone differs.
- `allowed_origins`: leave `[]` for same-origin hosting. If a separate trusted
  web frontend is deliberately used, list its exact HTTPS origin, not `*`.
- `allow_insecure_local`: leave `false` in production.
- `trust_proxy_https`: leave `false` unless your host confirms a trusted HTTPS
  proxy configuration.

Generate the setup token in cPanel Terminal:

```sh
php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'
```

Copy the printed token directly to private config; do not paste credentials
into a public issue, chat, or source repository. File permissions should allow
only your account and the PHP process to read the configuration: typically
`600`, or `640` if your provider's PHP process needs a shared group. Never `777`.

If the subdomain must be nested under another public root, keep private files
at `/home/ACCOUNT/dreamstore-private`. In the uploaded public `api/` folder,
copy `private_path.example.php` to `private_path.php` and change its returned
path to the real **absolute configuration file** path:

```php
<?php
declare(strict_types=1);
return '/home/ACCOUNT/dreamstore-private/config.php';
```

That small path selector contains no database credentials. The API `.htaccess`
denies web access to both path-selector files. Preserve it on future updates.
The backend rejects private configuration inside a public document root or
under `public_html`. Do not move the private directory into a public folder
to make an incorrect relative path work.

Alternatively, a host-managed environment variable `DREAMSTORE_CONFIG` can
point to that same absolute private `config.php` path. Use the file selector
when your shared host does not reliably forward custom environment variables
to PHP/FastCGI. Do not configure both to different locations.

## 7. Create the first live administrator

Open `https://stock.example.com/api/setup.php` over HTTPS. Enter the private
setup token, administrator name, email, and a unique password of at least
12 characters. Passwords are limited to 72 bytes to avoid hashing truncation;
use a password manager. The token goes in the POST form, never the address bar.

The page stops accepting account creation once an administrator exists. After
successful setup, clear `setup_token` in private config and remove the uploaded
public `api/setup.php` file. The application's sign-in page is not an open
staff-registration form. Log in at the normal subdomain root with the new live
credentials; the old local password does not migrate.

This first version supports administrator access to one shared hotel dataset.
Do not assume per-department permission isolation or staff role management.
Use an accountable administrator account and keep the password private.

## 8. Check the live environment before entering real stock

- HTTPS sign-in succeeds and an incorrect password fails safely.
- Refreshing loads the latest server inventory. Reopening requires login,
  then loads the same shared inventory.
- Add a clearly labelled test item to Kitchen with a stock-entry date.
- Receive a delivery with its date; confirm the delivery appears in history.
- Record Kitchen usage and verify on-hand quantity falls by the used amount.
- Open a second browser/device on the same live URL, sign in, and refresh its
  data; confirm the same item and movements are visible.
- Check that `https://stock.example.com/dreamstore-private/config.php` and
  `https://stock.example.com/schema.sql` do **not** expose private files.
- Test an ordinary Flutter URL and `/api/` independently. API replies must be
  JSON (or a documented setup form), not the Flutter loading page.

Remove test data deliberately before importing or entering the real hotel's
stock. Avoid submitting a day's report with test usage in the production data.

## 9. Import the hotel's existing inventory deliberately

Sign in to the live app, then import the JSON backup exported in step 1 through
**Settings**. Review the confirmation carefully: importing replaces the
**entire shared inventory snapshot**, including existing products, sales,
department usage, reports, and settings. It is not a merge operation and does
not copy the old device-local account.

Before replacing a nonempty live inventory, export a backup of it too. Choose
a quiet maintenance period and tell other users to stop editing and refresh
afterward. Do not repeatedly import separate browser exports expecting them
to merge into one database.

## Shared data, offline use, and conflicting edits

Live mode needs the server to load and save. It does not queue offline writes
or fall back to device-local stock when the network fails. An unsuccessful
save must not be treated as a completed delivery or sale.

The server protects the shared snapshot with a revision check and atomic SQL
updates. If two users edit the same revision, the second save is rejected
instead of silently replacing the first user's stock. Use the toolbar refresh
button or **Settings > Refresh shared inventory**,
review the latest quantity/history, and submit the intended operation again.
The client does not automatically retry stock mutations, because that can
duplicate deliveries, sales, or department usage.

There is no automatic real-time push between devices. Refresh live data before
working with quantities that another user may have changed. Expired sessions
require signing in again. Never disable conflict checks to hide these messages.

When replacing an older local-mode web build, export that browser's JSON backup
before clearing any site data. Confirm the new build reports **Live database**
in Settings, then import the old snapshot once only if the live database is
empty. Browsers may need a hard refresh or cached-site-data clear after the
deployment; the packaged cache headers force mutable Flutter entry points to
revalidate on future visits.

## Backups, recovery, and maintenance

Use cPanel **Backup Wizard** or your host's scheduled database backups. Retain
off-server copies and periodically practise recovery in a separate test
database. An app JSON export is useful for inventory, but it is not a complete
backup of server users, sessions, rate limits, and configuration.

For SSH/Terminal backups, use your full cPanel database identifiers. `-p`
prompts for the database password; never embed it in shell arguments:

```sh
mysqldump -h localhost -u ACCOUNT_stockapp -p --single-transaction --no-tablespaces ACCOUNT_dreamstore > /home/ACCOUNT/backups/dreamstore-2026-09-13.sql
```

Create the private backups directory first and replace the sample date. Keep
the dump out of every document root. Your host may need to perform backups if
your restricted runtime DB user lacks dump permissions.

For disaster recovery, first stop other users and retain the current database.
Restore to a **new** test database using phpMyAdmin/cPanel and verify it before
changing production config. A direct CLI import is destructive to its selected
database; only run it after checking the exact target and backup:

```sh
mysql -h localhost -u ACCOUNT_stockapp -p ACCOUNT_dreamstore_restore < /home/ACCOUNT/backups/dreamstore-2026-09-13.sql
```

To reset an existing administrator password in cPanel Terminal:

```sh
php /home/ACCOUNT/dreamstore-tools/reset_admin_password.php admin@example.com /home/ACCOUNT/dreamstore-private/config.php
```

The tool prompts privately for a new password and confirmation; it never
accepts a password in command-line arguments. Existing sessions are revoked.
There is no insecure public name/email recovery flow in live mode. If Terminal
is unavailable, ask your hosting administrator to run the maintenance tool;
do not re-enable public setup or weaken authentication.

Expired sessions and rate-limit buckets can be cleaned using:

```sh
php /home/ACCOUNT/dreamstore-tools/maintenance.php /home/ACCOUNT/dreamstore-private/config.php
```

After testing that command, it can be scheduled daily in cPanel **Cron Jobs**
with the host's correct PHP executable path. Store cron logs privately. Do not
put database passwords or setup tokens in the cron command.

## Updating the app safely

Back up the live database and private config, then build a fresh package.
Upload the new public app/API files and matching private PHP source during a
short maintenance window. Preserve the existing private `config.php` and
any public `api/private_path.php`; never overwrite configuration with the
examples. Keep `api/setup.php` deleted after the
first administrator is created; a new package includes the installer again.

Do not re-import initial `schema.sql` into an established database as an update
procedure. Future schema changes require a reviewed migration. Tell users to
refresh/reopen the site after deployment to load matching frontend/API code.

## Troubleshooting

### Literal backslashes in uploaded filenames / 403 after extraction

Older Windows-created ZIPs may contain entries such as
`public_html\index.html` instead of `public_html/index.html`. Some Linux
extractors turn these into flat, literal filenames, so the web server cannot
find `index.html` or `api/index.php`. Do not rename files individually or change
permissions to `777`; use a fresh `cpanel-linux` package generated by the
updated script instead.

1. Back up existing server `dreamstore-private/config.php` and any
   `api/private_path.php`. Keep backups outside every public root.
2. Extract the corrected full ZIP into a **new private staging folder**, not
   straight over the current document root. Confirm it has real
   `public_html/api` and `dreamstore-private/lib` directories.
3. Copy the **contents** of staged `public_html` into the existing subdomain
   document root. Alternatively, extract the new public-only ZIP directly into
   that root. Keep host-specific PHP-handler settings when reviewing `.htaccess`.
4. Copy the corrected private PHP source into the existing private folder,
   preserving the live `config.php`. The old extraction may have damaged the
   private library paths too. Install tools outside the public root likewise.
5. Confirm `/index.html` opens, then check `/api/health` and sign in. If the
   files exist but HTTPS still returns 404, confirm the HTTPS document-root
   override matches the HTTP root.
6. Only after verification, move the identified malformed backslash-named
   package files to a private quarantine folder. Do not delete unrelated files,
   private config, or existing inventory backups.

This archive repair does not require changing the database, reimporting
`schema.sql`, or recreating an existing administrator.

### Other problems

- **Logo/loading appears, then a blank screen:** inspect the browser Console
  and Network tabs. CanvasKit `.wasm` responses must be HTTP 200 with
  `Content-Type: application/wasm`, not `application/octet-stream` or Flutter
  HTML. The public `.htaccess` sets `AddType application/wasm .wasm`; preserve
  it on Apache/LiteSpeed hosts. Check both `canvaskit/canvaskit.wasm` and the
  browser-selected `canvaskit/chromium/canvaskit.wasm`. Add the MIME rule in the
  public root, not in the private deny-access file. If a host overrides MIME
  rules, ask its administrator to enable that type. This is separate from
  database setup, which does not block the initial login screen.

- **API response is HTML / sign-in cannot reach the server:** check the
  subdomain's actual root, uploaded hidden `.htaccess` files, PHP routing, and
  that `api/` is not being rewritten to Flutter `index.html`.
- **Private configuration not found:** confirm the sibling folder layout or
  `api/private_path.php`/`DREAMSTORE_CONFIG` override. Keep secrets outside public
  roots; do not fix this by copying config into `api/`.
- **Database connection error:** check prefixed names, provider DB host/port,
  user grants, imported schema, and `pdo_mysql`; inspect private server logs.
- **HTTPS required:** fix AutoSSL and Force HTTPS Redirect. Do not enable
  insecure-local mode to bypass a live certificate problem.
- **Session expired:** sign in again. Browser sessions can differ between
  devices; changing/resetting the password revokes old sessions.
- **Inventory changed elsewhere:** refresh, review current stock, and repeat
  the operation deliberately. Do not restore an old export to bypass conflict
  protection.
- **Different devices show different inventories:** confirm both use the same
  live URL/API build rather than an old local-only build; refresh server data.

Building this package does not provision a hosting account, create your actual
database, or publish a domain. Production sign-in, SQL connectivity, backups,
and multi-device behaviour must be verified on your hosting account before
real hotel operations start.
