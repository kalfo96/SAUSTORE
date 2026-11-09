# DreamStore on DirectAdmin

This package is tailored to the existing DirectAdmin subdomain:

```text
/domains/dreamstore.sauinndream.com/
  dreamstore-public/       configured subdomain document root
  dreamstore-private/      PHP source and private config
  dreamstore-tools/        command-line maintenance tools
```

## Upload

1. Back up the existing `dreamstore-private/config.php` and live database.
2. In File Manager, open `/domains/dreamstore.sauinndream.com/`.
3. Upload the `directadmin-linux-*.zip` archive and extract it there. The archive
   contains the three correctly named folders above. It does not contain or
   overwrite `config.php`.
4. Confirm that `dreamstore-public/index.html`,
   `dreamstore-public/api/index.php`, `dreamstore-private/lib/App.php`, and
   `dreamstore-private/lib/Validation.php` are real nested files. Filenames must
   not contain backslashes.
5. Keep the subdomain document root set to
   `/domains/dreamstore.sauinndream.com/dreamstore-public`.

With this sibling-folder layout the API finds
`dreamstore-private/config.php` automatically. Do not create
`dreamstore-public/api/private_path.php`. If an old copy already exists, download
it for backup and remove it so it cannot override the correct automatic path.

## Database and private configuration

If the four `dreamstore_*` tables do not already exist, select the new empty
database in phpMyAdmin and import `schema.sql` once. Never re-import that file
over an established live database.

If `dreamstore-private/config.php` does not exist, duplicate
`config.example.php` as `config.php`. Enter the full database name and username
shown by DirectAdmin, the newly rotated database password, and a private
64-character hexadecimal setup token. Leave HTTPS and same-origin security
enabled. Typical permissions are `755` for folders and `640` or `600` for the
private config; never use `777`.

Do not put MySQL credentials in Flutter, an APK, a JSON build configuration, the
public API folder, or this deployment archive.

## Verify

Open `https://dreamstore.sauinndream.com/api/health`. Continue only when it
returns status `ok` and schema version `3`. Then open
`https://dreamstore.sauinndream.com/api/setup.php` and create the first
administrator. After successful setup, clear `setup_token` in private
`config.php` and remove the public `api/setup.php` installer.

Test a small labelled stock item, a dated delivery, department usage, and a sale
from one device, then sign in and refresh on a second device. Remove the test
records before entering real hotel stock.

## Moving old device-only stock into the live database

An earlier local-mode browser keeps its inventory only on that device. Before
clearing browser data or forcing the new build, open **Settings > Export backup**
and keep the JSON file safely. Then close every DreamStore tab, clear the site's
cached files/service worker (not the exported file), reopen the HTTPS site, and
confirm **Settings > Storage** says **Live database**.

Sign in with the same live administrator account on both devices. If the live
database is empty, import the exported JSON once from the first device. Import
replaces the complete shared snapshot; do not import over newer live work.
Other open devices do not receive push updates automatically, so use the toolbar
refresh action or **Settings > Refresh shared inventory** after another device
makes a change.
