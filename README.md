# DreamStore

DreamStore is the stock desk for **The Dream of Sau Inn Beach
Hotel**. It keeps products, dated stock arrivals, sales, department usage, daily
reports, and the complete movement history together. Recording a sale or hotel
department usage reduces that department's available stock immediately;
receiving stock increases it and leaves an auditable entry.

Two configurations are available: an offline, device-local workspace and a
live cPanel deployment backed by PHP and MySQL. The cPanel build shares one
hotel inventory across devices with server login and version-checked writes.
See [the cPanel deployment guide](docs/CPANEL.md) for subdomain setup, SQL
import, private credentials, administrator creation, and backups.

## Highlights

- At-a-glance dashboard for product count, units on hand, stock value, sales,
  gross profit, and low/out-of-stock attention items.
- Product catalogue with SKU, category, description, cost, selling price,
  department, original stock-entry date, opening quantity, and low-stock threshold.
- Department-grouped inventory with department, search, and stock-status filters.
- Dated deliveries with before/after quantities, unit cost, and supplier notes.
- Purchase receipts with supplier, invoice, delivery date, unit, quantity, cost,
  optional expiry, and an actor recorded in the stock ledger.
- Department requisitions with request, approval, issue, and receipt-confirmation
  states; issuing is atomic and records department consumption.
- Printable A4 store issue form with requested/issued/used/returned quantities
  and requester, approver, storekeeper, and receiver signature fields.
- Multi-item sales, generated receipt numbers, customer/payment details, and
  immutable historical line prices and costs.
- Sales and stock-movement history, including safe sale reversal.
- Kitchen and other department usage with quantities and captured stock costs,
  daily/range reports, per-item totals, and daily report submission.
- Server-managed administrator login in live mode; device-local accounts in
  offline mode.
- Configurable store identity, currency precision, and system/light/dark theme.
- Polished responsive dashboard with an interactive usage chart, department
  shortcuts, card/list inventory views, mobile tabs, and quick delivery actions.
- Material 3 light/dark interface with accessible status colours and controls.
- Local-mode mobile inventory operations work offline. An already-open local web session can
  work offline, but offline reopening is not currently supported.

## Department stock and usage

1. Add a product, select its department (Kitchen, Housekeeping, Laundry, etc.),
   and choose the **Stock entered date** for its opening stock.
2. When another delivery arrives, choose **Receive stock** and enter its actual
   arrival date, quantity, unit cost, and optional supplier reference. Each
   delivery has its own history; it never overwrites the original entry date.
3. Use **Request stock** to submit department requirements. A store administrator
   approves the request, issues available stock, and records the receiver's
   confirmation. Issuing reduces central on-hand stock and creates department
   consumption entries. Existing direct department usage remains available for
   historical/manual corrections.
   Print a blank store form from **Requisitions**, or print a saved request with
   its items and recorded names for paper signatures and usage/return tracking.
   Editing a product's department reassigns its remaining stock after a
   confirmation; previous delivery and usage records keep their department.
4. Review usage by item, department, and day/date range in **Reports**. Usage
   value is the captured stock cost, not sales revenue. Submit a completed
   day's report only after all usage has been entered; that day is then locked
   against additional usage so submitted totals cannot become stale.

Arrival and usage dates cannot be future days. Backdated records update current
stock when saved; they do not reconstruct historical on-hand balances. Supplier,
invoice and expiry information is retained for each receipt movement. Costing
currently uses weighted-average cost; receipt lots are not yet depleted by FIFO,
and expiry alerts are not yet generated. A separate save timestamp and actor
name are retained in movement history. Older saved data remains compatible:
original entry dates fall back to the item's creation date, and missing
historical department snapshots are not invented. Inventory snapshots migrate
automatically to schema 4 when loaded.

## Architecture

The project deliberately stays small and dependency-light:

```text
lib/
├── auth/         Device-local administrator access
├── config/       Compile-time development and production configuration
├── models/       Immutable inventory entities, derived totals, JSON codecs
├── data/         Persistence contract and SharedPreferences implementation
├── state/        Validated inventory operations and app state notification
├── screens/      Dashboard, products, sales, activity, and settings flows
├── widgets/      Reusable metrics, empty states, rows, pills, and inputs
├── theme/        Material 3 light/dark themes and semantic colours
├── utils/        Dependency-free money, quantity, date, and label formatting
└── main.dart     App bootstrap and top-level navigation
```

The UI asks the state layer to perform a business operation; it does not adjust
quantities directly. The controller validates each request, derives an immutable
snapshot, persists it through the store interface, and only then publishes the
new state to listeners. This prevents a failed write from appearing successful
in the current session. `MemoryInventoryStore` keeps domain tests independent
from platform plugins.

Beyond the standard Flutter template dependencies, the runtime uses
`shared_preferences` for local persistence, `crypto` for one-way local
password hashing, and `http` for the authenticated live API. There is no service locator, database generator,
internationalisation package, or code generation.

## Local data behaviour

- The complete inventory is stored on the device as one versioned JSON snapshot
  under the `stockpilot.inventory.v1` preferences key.
- Products, settings, sales, and stock movements are restored on launch and
  saved after accepted changes. A new installation begins with empty data;
  loading the optional demonstration catalogue is an explicit action.
- Quantities are whole integers. Monetary values are integer minor units, which
  avoids floating-point rounding drift. Currency decimal precision in settings
  determines how those integers are displayed.
- Dates are serialized as ISO-8601 strings. Historical sale lines retain the
  product name, SKU, sale price, and average unit cost that applied at checkout.
- The schema version is checked while loading so data from an unsupported newer
  app version is not silently misread.
- Corrupt reads and failed writes are surfaced as user-safe storage errors.
- Clearing all data removes the preferences entry. The controller can instead
  preserve settings while saving a fresh, empty current-version inventory.

In local mode, data belongs to one app installation, with no cross-device sync,
automatic backup, or encryption layer. Clearing
the app's operating-system data or uninstalling it can remove the inventory.
Use the cPanel configuration below when devices need to share inventory.

The local-mode login is also device-local. On a local-mode hosted web build, each browser profile has
its own account and inventory in browser storage. It is an access gate for a
single-device stock desk, not centralized server authentication. Do not expect
two devices to share data in that configuration.

## Live cPanel deployment

Build the upload-ready package from PowerShell:

```powershell
.\scripts\build_cpanel.ps1
```

This runs analysis, tests, and a production Flutter web build configured for
`/api/` on the same HTTPS subdomain. It creates a new ZIP in `dist/` containing
the public web app/API, private PHP source, SQL schema, maintenance tools, and
installation instructions. No database passwords are bundled.
Archive entries use Linux-compatible forward slashes and are regression-tested
without normalizing their stored names. The script also creates a public-only
`dreamstore-public-linux-*.zip` for direct extraction into a configured web root.
Use the full `cpanel-linux-*.zip` to install the matching private PHP library.

The live API stores a shared, schema-validated inventory snapshot in MySQL.
Writes use a transaction and expected-version check: a stale device reloads
the latest inventory and asks you to retry, never silently overwriting or
replaying a stock deduction. Refresh from the mobile toolbar or Settings to
see another device's changes; this is not push synchronization.

Live mode requires a network connection and does not fall back to local data.
Session tokens stay in memory; reopening the app requires login. Accounts are
created through the protected first-administrator setup; password recovery is
administrator-managed. Production demo data is disabled. Keep private database
configuration outside every public web root and use HTTPS.

For Android connected to this backend, use the dedicated production
configuration. It contains only the public HTTPS API address, never database
credentials:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_android_release.ps1
```

See `docs/ANDROID_RELEASE.md` for upload-key setup, outputs, and the device test
checklist. Database provisioning, uploading the server files, HTTPS
configuration, and a real MySQL smoke test still need to be completed on your
hosting account; building an APK does not publish or configure the backend.

## Inventory business rules

1. Product names and SKUs are required; SKUs identify products and must be
   unique without regard to letter case.
2. Opening stock, prices, and low-stock thresholds cannot be negative. Stock is
   always a whole-unit quantity.
3. Every opening balance, restock, sale, manual adjustment, and reversal is
   represented by a stock movement with its before and after quantity.
4. A sale line must request at least one unit of an active product. Every line
   is validated before anything changes, so insufficient stock rejects the
   whole sale and inventory never becomes negative.
5. Duplicate checkout lines for the same product and unit price are combined.
   A successful sale snapshots its name, SKU, price, and average cost; it then
   reduces stock and creates a linked negative movement for every line.
6. A restock must add at least one unit. It creates a positive movement and
   recalculates unit cost as the weighted average of old and arriving stock.
7. Quantity `0` is out of stock. A positive quantity at or below the product's
   threshold is low stock; a quantity above the threshold is in stock.
8. Product edits do not rewrite historical receipts. Inventory quantity changes
   go through stock operations so the audit trail remains meaningful.
9. Voiding a sale is allowed only once. It marks the original receipt void,
   restores all sold units using the captured cost in the new weighted average,
   and records linked reversal movements instead of deleting history.
10. Financial totals use stored integer values: inventory value is quantity ×
    unit cost, revenue is quantity × sale price, and gross profit is revenue
    minus the captured cost of goods.

## Run locally

### Prerequisites

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`
- Android Studio/Android SDK for Android, or macOS with Xcode for iOS
- A configured emulator, simulator, or physical device

Confirm the toolchain and install packages:

```sh
flutter doctor
flutter pub get
flutter devices
```

Launch on the selected device:

```sh
flutter run
```

To run with the checked-in development configuration:

```sh
flutter run -d chrome --dart-define-from-file=config/development.json
```

If several devices are connected, pass the identifier shown by
`flutter devices`:

```sh
flutter run -d <device-id>
```

## Quality checks

Run static analysis and the test suite before shipping:

```sh
flutter analyze
flutter test
```

## Release builds

Build the production web bundle (PowerShell):

```powershell
.\scripts\build_web.ps1
```

The same build can be run directly on any platform:

```sh
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/production.json
```

Android APK:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_android_release.ps1 -ApkOnly
```

Android App Bundle for Play distribution:

```sh
flutter build appbundle --release --dart-define-from-file=config/android-production.json
```

iOS archive input (requires macOS, Xcode, and signing configuration):

```sh
flutter build ios --release --dart-define-from-file=config/production.json
```

Release artifacts are written below `build/`. Android release builds require
the private upload key described in `docs/ANDROID_RELEASE.md`; the project no
longer signs release artifacts with Flutter's debug key. Configure the Apple
team/provisioning profile before publishing to the App Store.

## Environment configuration

Flutter environment values are compile-time values in `config/development.json`
and `config/production.json`, with `config/cpanel.json` for the same-origin web
API and `config/android-production.json` for the absolute Android API address.
They control the visible app name, environment, support contact, and whether
starter/demo inventory is offered. Change the production support email before
publishing.

Release builds default to production when no environment is supplied. Use the
production JSON explicitly for consistent release settings on every platform.

Never put passwords, API keys, or private credentials in these files. Flutter
web compile-time values are delivered to the browser and are not secrets.

## Local-mode static web hosting

When built with `config/production.json`, the bundle is a local-mode static
single-page application in `build/web`. For the shared MySQL deployment use
`scripts/build_cpanel.ps1` and the cPanel guide above instead.
The build packages its renderer locally using `--no-web-resources-cdn`; it does
not need Google's renderer CDN. Web inventory is local and can be used offline
in an already-open session. The current build does not provide a service worker
for offline reopening.
Three hosting paths are prepared:

### Firebase Hosting

1. Install the Firebase CLI and sign in.
2. Copy `.firebaserc.example` to `.firebaserc` and replace the placeholder with
   your Firebase project ID.
3. Run the production web build shown above.
4. Deploy with `firebase deploy --only hosting`.

`firebase.json` includes the SPA fallback, safe response headers, sensible
asset caching, and excludes source maps from the public upload.

### Docker or a container host

Build and serve the production application with Nginx:

```sh
docker compose up --build
```

Open `http://localhost:8080`. The same image can be deployed to a container
service that accepts port 8080. `hosting/nginx.conf` provides the SPA fallback,
compression, cache rules, and security headers.

### Other static hosts

Upload the contents of `build/web`. The checked-in `web/_redirects` and
`web/_headers` files support hosts that recognize Netlify-style routing and
header files. For another provider, configure all unknown routes to serve
`index.html` and do not cache `index.html` permanently.

Use HTTPS in production. Because inventory lives in browser storage, operators
must use the same browser profile and hostname consistently; changing the
domain creates a separate storage origin.
