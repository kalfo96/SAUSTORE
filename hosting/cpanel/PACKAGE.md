# DreamStore cPanel deployment package

Read `INSTALL.md` before uploading anything. The intended layout is:

This archive uses Linux-compatible forward-slash paths. After extraction,
`public_html/api` and `dreamstore-private/lib` must be real directories, not
files whose names contain backslashes. Do not use an older Windows-path ZIP.

```text
cPanel account home/
  public_html/              Flutter web application; includes api/
  dreamstore-private/       PHP application and config.example.php
  dreamstore-tools/         Administrator maintenance scripts; never public
```

`schema.sql` is for import through cPanel/phpMyAdmin. Do not upload it into
`public_html`. Keep this document, `INSTALL.md`, and database backups outside
the public document root too.

The archive does not contain a working database password, setup token, or
administrator account. Copy the private config example to `config.php` on your
server, fill in your cPanel database details, enable HTTPS, and then create the
first administrator using the one-time setup page.

This is a deployment package, not confirmation of a published site. You need
a cPanel hosting account, a domain with HTTPS, and a MySQL/MariaDB database.

Existing device/browser data is not uploaded automatically. Export a backup
from the old app before switching sites, then import it deliberately after
signing in to the live app. Importing replaces the hotel's shared inventory.

When repairing an older malformed archive, preserve existing private
`config.php`, custom `api/private_path.php`, and your database. Copy the corrected
public and private source from this archive; no SQL reimport is needed.
