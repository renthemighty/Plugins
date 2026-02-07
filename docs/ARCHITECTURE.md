# Kira Architecture Overview

## System Overview

```
+-----------------------------------------------------------------------------------+
|                              Kira Flutter Application                             |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  +-------------+    +---------------+    +------------------+    +--------------+ |
|  |   Capture   |    |  Local Mirror |    |     Database     |    |   Reports    | |
|  |   & Stamp   |--->|   (on-disk)   |<-->|  (SQLite/Drift)  |<-->|   Engine     | |
|  +-------------+    +---------------+    +------------------+    +--------------+ |
|        |                    ^                     ^                      |         |
|        v                    |                     |                      v         |
|  +-------------+            |              +------+-------+    +--------------+   |
|  |  Integrity  |------------+              |  Sync Engine |    |  CSV / Tax   |   |
|  |   Auditor   |                           |  (bidir.)    |    |   Export     |   |
|  +-------------+                           +--------------+    +--------------+   |
|                                                   |                               |
|  +------------------------------------------------+-----------------------------+ |
|  |                       Storage Adapter Layer                                  | |
|  |  +----------+ +----------+ +----------+ +-----+ +-----------+ +----------+  | |
|  |  |  Google   | | Dropbox  | | OneDrive | | Box | |   Local   | |   Kira   |  | |
|  |  |  Drive    | |          | |          | |     | | Encrypted | |  Cloud   |  | |
|  |  +----------+ +----------+ +----------+ +-----+ +-----------+ +----------+  | |
|  |                    All via OAuth 2.0 / PKCE                                  | |
|  +--------------------------------------------------------------------------+   |
|                                                                                   |
|  +------------------------------------------------+-----------------------------+ |
|  |                    Accounting Adapter Layer                                   | |
|  |  +------------+ +------------+ +--------+ +------------+ +------+ +------+   | |
|  |  | QuickBooks | | TurboTax   | |  Xero  | | FreshBooks | | Zoho | | Sage |   | |
|  |  | (active)   | | (active)   | | (stub) | |   (stub)   | |(stub)| |(stub)|   | |
|  |  +------------+ +------------+ +--------+ +------------+ +------+ +------+   | |
|  +--------------------------------------------------------------------------+   |
|                                                                                   |
|  +------------------+  +------------------+  +------------------+                 |
|  |    Business       |  |   Admin / Error  |  |     Security     |                |
|  |   Workspaces      |  |    Backend       |  |      Layer       |                |
|  +------------------+  +------------------+  +------------------+                 |
|                                                                                   |
|  +------------------+                                                             |
|  |  i18n (EN, FR-CA,|                                                             |
|  |       ES-US)     |                                                             |
|  +------------------+                                                             |
+-----------------------------------------------------------------------------------+
```

---

## Module Descriptions

### 1. Capture & Stamp

The Capture module is the sole ingestion point for receipts in Kira. There is no
gallery picker, no file browser, and no import-from-photos flow. Every receipt
enters the system through the device camera.

**Responsibilities:**

- **Camera-only ingestion.** The app opens the native camera (via `camera`
  package) in a custom viewfinder. Users frame a receipt, tap to capture. No
  image is ever pulled from the device gallery.
- **Timestamp burning.** Immediately after capture, the module composites a
  UTC timestamp (ISO 8601) into the bottom margin of the image as a permanent,
  non-removable overlay. The burned timestamp is the canonical capture time and
  cannot be altered after the fact.
- **SHA-256 checksum.** After the timestamp is burned, a SHA-256 digest is
  computed over the final JPEG bytes. This checksum is stored in the database
  alongside the receipt record and is used for integrity verification throughout
  the receipt lifecycle.
- **Metadata extraction.** The module records device locale, GPS coordinates
  (if permitted), camera orientation, and capture session ID.

**Invariants:**

- A receipt without a burned timestamp is invalid and must not be persisted.
- The checksum is computed exactly once, on the post-stamp image bytes. Any
  subsequent mismatch indicates tampering or corruption.

---

### 2. Local Mirror

The Local Mirror is the on-disk file store for receipt images. It is structured,
deterministic, and governed by a strict no-overwrite policy.

**Folder structure:**

```
<app_documents>/
  kira/
    mirror/
      <year>/
        <month>/
          <receipt_id>.jpg
          <receipt_id>.thumb.jpg
    quarantine/
      <receipt_id>.jpg
    export/
      <report_name>.csv
```

**File naming:**

Each file is named by its `receipt_id` (a UUID v4 generated at capture time).
This guarantees uniqueness without relying on timestamps or sequential counters.
Thumbnails use the `.thumb.jpg` suffix.

**No-overwrite policy:**

Once a file is written to the mirror, it is never overwritten. Updates to
metadata do not touch the image file. If a sync operation attempts to write a
file whose path already exists, the write is rejected and the conflict is
logged. The only operation that removes a file from the mirror is explicit
user-initiated deletion (which soft-deletes in the database first and
hard-deletes only after sync confirmation) or quarantine by the Integrity
Auditor.

---

### 3. Database (SQLite / Drift)

Kira uses SQLite via the [Drift](https://drift.simonbinder.eu/) package
(formerly Moor) for all structured data. The database is the single source of
truth for receipt metadata, sync state, and business data. It is designed
offline-first: every operation succeeds locally before any network call.

**Tables:**

| Table | Purpose |
|---|---|
| `receipts` | Core receipt metadata: `receipt_id` (PK, UUID), `captured_at` (UTC), `checksum` (SHA-256), `file_path`, `thumbnail_path`, `amount`, `currency`, `vendor`, `category`, `notes`, `is_deleted` (soft delete), `created_at`, `updated_at` |
| `sync_queue` | Pending sync operations: `queue_id`, `receipt_id` (FK), `operation` (upload/update/delete), `target_adapter` (enum), `status` (pending/in_progress/committed/failed), `retry_count`, `last_attempted_at`, `created_at` |
| `sync_state` | Per-adapter sync cursors: `adapter_id` (PK), `last_synced_at`, `cursor_token`, `is_full_sync_needed` |
| `storage_credentials` | OAuth token references: `adapter_id` (PK), `access_token_ref` (Keychain/Keystore key), `refresh_token_ref`, `expires_at`, `scopes` |
| `workspaces` | Business workspaces: `workspace_id` (PK), `name`, `owner_user_id`, `created_at` |
| `workspace_members` | Membership: `workspace_id` (FK), `user_id`, `role` (owner/admin/member/viewer), `joined_at` |
| `trips` | Business trips: `trip_id` (PK), `workspace_id` (FK), `name`, `start_date`, `end_date`, `status` (draft/submitted/approved) |
| `expense_reports` | Reports: `report_id` (PK), `workspace_id` (FK), `trip_id` (FK, nullable), `title`, `status` (draft/submitted/approved/rejected), `submitted_at`, `total_amount`, `currency` |
| `expense_report_items` | Line items: `item_id`, `report_id` (FK), `receipt_id` (FK), `amount`, `category`, `notes` |
| `audit_events` | Audit trail: `event_id`, `workspace_id` (FK), `actor_user_id`, `event_type`, `target_type`, `target_id`, `payload` (JSON), `occurred_at` |
| `integrity_log` | Auditor results: `log_id`, `receipt_id` (FK), `check_type` (checksum/orphan/missing_file), `result` (pass/fail), `details`, `checked_at` |
| `trial_state` | Trial tracking: `first_capture_at`, `trial_expires_at`, `is_upgraded` |
| `app_settings` | Key-value settings: `key` (PK), `value` |
| `accounting_exports` | Export history: `export_id`, `adapter_type`, `report_id` (FK, nullable), `exported_at`, `status`, `external_id` |

**DAOs:**

Each logical domain has a dedicated DAO class that encapsulates queries and
write operations:

- `ReceiptDao` -- CRUD, search by date range/vendor/category, soft delete
- `SyncQueueDao` -- enqueue, dequeue, mark committed/failed, retry logic
- `SyncStateDao` -- cursor management per adapter
- `WorkspaceDao` -- workspace and member management
- `TripDao` -- trip lifecycle
- `ExpenseReportDao` -- report assembly, status transitions
- `AuditEventDao` -- append-only audit log queries
- `IntegrityLogDao` -- log check results, query failures
- `TrialStateDao` -- trial start, expiry check, upgrade flag
- `SettingsDao` -- app preferences, locale, theme
- `AccountingExportDao` -- export history tracking

**Offline-first guarantees:**

- All writes go to SQLite first. Network operations are deferred to the
  Sync Engine.
- Reads never depend on network availability.
- The sync queue is durable: pending operations survive app restarts and
  device reboots.

---

### 4. Storage Adapters

Storage Adapters provide a uniform interface for uploading, downloading, listing,
and deleting receipt files on remote storage backends. Every adapter implements
the same `StorageAdapter` abstract class.

**Supported adapters:**

| Adapter | Auth Method | Key Scopes | Status |
|---|---|---|---|
| **Google Drive** | OAuth 2.0 + PKCE | `drive.file` (app-created files only) | Active |
| **Dropbox** | OAuth 2.0 + PKCE | `files.content.write`, `files.content.read` | Active |
| **OneDrive** | OAuth 2.0 + PKCE (MSAL) | `Files.ReadWrite.AppFolder` | Active |
| **Box** | OAuth 2.0 + PKCE | `root_readwrite` | Active |
| **Local Encrypted** | N/A (on-device) | N/A | Active |
| **Kira Cloud** | OAuth 2.0 + PKCE | Kira-defined scopes | Active |

**Common interface:**

```dart
abstract class StorageAdapter {
  Future<void> authenticate();
  Future<void> refreshToken();
  Future<String> uploadFile(String localPath, String remotePath);
  Future<void> downloadFile(String remotePath, String localPath);
  Future<List<RemoteFileEntry>> listFiles(String remotePath);
  Future<void> deleteFile(String remotePath);
  Future<StorageQuota> getQuota();
  Future<bool> fileExists(String remotePath);
}
```

**Auth flow (all adapters):**

1. App initiates OAuth 2.0 Authorization Code flow with PKCE.
2. System browser opens the provider's consent page.
3. User grants consent; provider redirects back to the app via custom URI
   scheme or universal link.
4. App exchanges the authorization code + code verifier for tokens.
5. Access token is stored in Keychain (iOS) / Keystore (Android) -- never in
   SharedPreferences or plain files.
6. Refresh token rotation is handled automatically; expired tokens trigger
   silent refresh before any API call.

**Users never see or enter API keys, client secrets, or tokens.** All
credentials are managed transparently through in-app OAuth.

---

### 5. Sync Engine

The Sync Engine orchestrates bidirectional synchronization between the local
database/mirror and the selected remote storage adapter. It is designed for
reliability over speed: every operation is idempotent, and partial failures
do not corrupt state.

**Core principles:**

- **Bidirectional sync.** Changes flow both from local to remote and from
  remote to local. The engine detects which direction has newer data using
  timestamps and sync cursors.
- **Two-step commit.** Every sync operation follows a two-phase protocol:
  1. **Prepare:** The file is uploaded/downloaded and the operation is marked
     `in_progress` in `sync_queue`.
  2. **Commit:** After verifying the remote write succeeded (or the local
     write matches the expected checksum), the operation is marked `committed`
     and the sync cursor is advanced.
  If the commit step fails, the operation remains `in_progress` and will be
  retried on the next sync cycle. This guarantees that a partially-uploaded
  file is never recorded as synced.
- **Backfill.** When a user upgrades from trial to a paid plan, the engine
  performs a one-time backfill of all locally-captured receipts to the newly
  connected remote storage. Backfill uses the same two-step commit protocol
  and respects deduplication rules.
- **Conflict resolution.** If the same `receipt_id` exists both locally and
  remotely with different checksums, the engine applies last-writer-wins
  based on `updated_at` timestamps. In practice, conflicts are rare because
  the no-overwrite policy prevents image file mutations; conflicts arise only
  from metadata edits.
- **Background sync.** On Android, sync runs via WorkManager periodic tasks.
  On iOS, sync runs via BGTaskScheduler (BGAppRefreshTask and
  BGProcessingTask). The engine also syncs opportunistically when the app
  is foregrounded.

**Sync algorithm:**

```
1. Acquire sync lock (prevent concurrent runs).
2. Load sync cursor for the active adapter from `sync_state`.
3. LOCAL-TO-REMOTE phase:
   a. Query `sync_queue` for pending upload/update/delete operations.
   b. For each operation (ordered by `created_at` ASC):
      i.   Set status = in_progress.
      ii.  Execute the adapter call (upload/update/delete).
      iii. Verify remote state (e.g., checksum match for uploads).
      iv.  Set status = committed; update sync cursor.
      v.   On failure: increment retry_count; set status = failed if
           retry_count exceeds threshold.
4. REMOTE-TO-LOCAL phase:
   a. Call adapter.listFiles() with cursor for incremental listing.
   b. For each remote file not present locally:
      i.   Download to local mirror (respecting no-overwrite).
      ii.  Compute checksum; insert receipt record into database.
   c. For each remote deletion not reflected locally:
      i.   Soft-delete the local receipt record.
5. Update sync cursor in `sync_state`.
6. Release sync lock.
```

**Retry policy:**

- Transient failures (network timeout, 5xx): exponential backoff, max 5
  retries.
- Auth failures (401/403): attempt token refresh, then retry once.
- Permanent failures (404 on upload target, quota exceeded): mark failed,
  surface to user.

---

### 6. Integrity Auditor

The Integrity Auditor is a background subsystem that continuously verifies the
consistency between the database, the local mirror, and (when online) the remote
storage.

**Checks performed:**

| Check | Description | Frequency |
|---|---|---|
| **Orphan detection (mirror)** | Files in the mirror directory with no matching `receipts` row. | Daily |
| **Orphan detection (DB)** | Receipt rows whose `file_path` points to a nonexistent file. | Daily |
| **Checksum verification** | Recompute SHA-256 of the on-disk file and compare against the stored `checksum`. | Weekly (rotating subset) |
| **Remote consistency** | Compare local receipt list against remote file list; flag discrepancies. | On each full sync |
| **Thumbnail integrity** | Verify thumbnail files exist for all receipts. | Daily |

**Quarantine:**

When a check fails, the affected receipt is moved to quarantine:

1. The image file is relocated from `mirror/<year>/<month>/` to `quarantine/`.
2. The `receipts` row is flagged with a quarantine status.
3. An entry is written to `integrity_log` with full details.
4. The user is notified (in-app banner) and can choose to re-capture or
   force-accept.

Quarantined files are never synced to remote storage until the issue is
resolved.

---

### 7. Reports

The Reports module generates financial summaries from receipt data. Reports
are computed entirely from the local database and are available offline.

**Report types:**

| Period | Contents |
|---|---|
| **Daily** | All receipts for a given day, grouped by category. Subtotals per category, grand total. |
| **Monthly** | All receipts for a calendar month. Category breakdown, vendor frequency, daily averages. |
| **Quarterly** | Three-month aggregate. Quarter-over-quarter comparison when prior data exists. |
| **Yearly** | Full calendar year. Category trends, monthly breakdown chart data, annual totals. |

**Export formats:**

- **CSV export.** Tab-delimited file with columns: date, vendor, category,
  amount, currency, receipt_id, checksum. Compatible with spreadsheet
  software and accounting imports.
- **Tax export.** Structured CSV matching common tax-filing categories
  (business meals, travel, office supplies, etc.). Includes subtotals per
  category and a summary row. Designed for direct import into TurboTax and
  similar tools.

**Offline availability:**

Reports are generated on-device from SQLite queries. No network call is
required. Exported files are written to `mirror/export/` and can be shared
via the OS share sheet.

---

### 8. Business Workspaces

Business Workspaces enable teams and organizations to collaborate on expense
management within Kira.

**Concepts:**

- **Workspace.** A named container owned by a single user. All business data
  (trips, expense reports, receipts tagged to the workspace) lives under this
  scope.
- **Members.** Users invited to a workspace with a role:
  - `owner` -- full control, billing, can delete workspace.
  - `admin` -- manage members, approve reports, view all data.
  - `member` -- submit expense reports, view own data.
  - `viewer` -- read-only access to approved reports.
- **Trips.** A date-bounded grouping of expenses (e.g., "NYC Client Visit
  2025-03-10 to 2025-03-14"). Receipts captured during the trip dates can be
  auto-associated.
- **Expense Reports.** A collection of receipt line items submitted for
  approval. Reports follow a lifecycle: `draft` -> `submitted` -> `approved`
  or `rejected`.
- **Audit Events.** Every significant action (report submitted, member added,
  receipt deleted) is logged as an immutable audit event with actor, timestamp,
  and payload.

---

### 9. Accounting Adapters

Accounting Adapters export expense data to external accounting and tax
software. They share a common interface similar to Storage Adapters.

**Active integrations:**

| Adapter | Auth | Capabilities |
|---|---|---|
| **QuickBooks Online** | OAuth 2.0 (Intuit) | Push expense reports as bills/expenses; sync chart of accounts for category mapping. |
| **TurboTax** | File export | Generate TurboTax-compatible CSV/TXF for direct import during tax filing. |

**Roadmap stubs (interface defined, implementation pending):**

| Adapter | Status |
|---|---|
| Xero | Stub |
| FreshBooks | Stub |
| Zoho Books | Stub |
| Sage | Stub |

Each stub implements the `AccountingAdapter` abstract class and throws
`UnimplementedError` on all methods, ensuring the interface contract is
locked in before implementation begins.

```dart
abstract class AccountingAdapter {
  Future<void> authenticate();
  Future<void> exportExpenseReport(ExpenseReport report);
  Future<List<AccountCategory>> fetchCategories();
  Future<ExportResult> getExportStatus(String exportId);
}
```

---

### 10. Admin / Error Backend

The Admin/Error Backend provides operational visibility without compromising
user privacy.

**Privacy-safe metrics:**

- Aggregate counts: receipts captured per day (no content), sync success/failure
  rates, adapter usage distribution.
- No receipt images, amounts, vendor names, or user-identifiable data leave
  the device in metrics payloads.
- Metrics are batched and sent at most once per 24 hours.

**Error reporting:**

- Crash reports are captured via a privacy-respecting crash reporter (e.g.,
  Firebase Crashlytics with data collection consent).
- Stack traces are symbolicated but stripped of user data.
- Sync failures, integrity check failures, and auth errors are reported with
  error codes and adapter identifiers only.

**Audit log:**

- A local audit log (distinct from business workspace audit events) records
  all security-relevant operations: login, logout, app lock trigger, token
  refresh, export, delete.
- The audit log is append-only and survives app updates.
- It can be exported by the user for their own records.

---

### 11. Internationalization (i18n)

Kira supports three locales at launch:

| Locale | Language | Region |
|---|---|---|
| `en` | English | Default / US |
| `fr-CA` | French | Canada |
| `es-US` | Spanish | United States |

**Implementation:**

- Flutter's `flutter_localizations` and `intl` packages with ARB files.
- Generated via `flutter gen-l10n`.
- All user-facing strings are localized, including error messages, button
  labels, report headers, and date/currency formats.

**Locale-aware formatting:**

- **Dates:** Formatted per locale (e.g., `MM/dd/yyyy` for en-US,
  `yyyy-MM-dd` for fr-CA).
- **Currency:** Locale-appropriate symbols and decimal separators
  (e.g., `$1,234.56` for en-US, `1 234,56 $` for fr-CA).
- **Numbers:** Thousand separators and decimal points per locale.

---

### 12. Security

Security is layered across transport, storage, authentication, and application
access.

**Transport security:**

- All network communication uses HTTPS (TLS 1.2+).
- Android: `android:usesCleartextTraffic="false"` in the manifest; network
  security config enforces HTTPS.
- iOS: App Transport Security (ATS) enabled globally with no exceptions.
- **Certificate pinning** is applied exclusively to the Kira backend domain.
  Third-party APIs (Google, Dropbox, Microsoft, Box, Intuit) use standard
  system CA validation -- pinning their certificates would break when
  providers rotate certs.

**Authentication:**

- All external service authentication uses OAuth 2.0 Authorization Code
  with PKCE (Proof Key for Code Exchange).
- No client secrets are embedded in the app binary.
- PKCE code verifiers are generated per session and never reused.

**Credential storage:**

- iOS: Keychain Services with `kSecAttrAccessibleAfterFirstUnlock`.
- Android: Android Keystore system with hardware-backed keys where available.
- Tokens are never stored in SharedPreferences, plain files, or SQLite.

**App lock:**

- Optional biometric lock (Face ID / Touch ID on iOS, BiometricPrompt on
  Android) or PIN/passcode.
- App lock activates on background-to-foreground transition after a
  configurable timeout (default: immediate).

**Encryption:**

- Local database: SQLite encryption via `sqlcipher_flutter_libs` with a
  key derived from device-protected storage.
- Local mirror files: AES-256-GCM encryption at rest when "Local Encrypted"
  storage adapter is selected.
- Export files: Unencrypted by default (user is exporting intentionally);
  user may choose to encrypt exports with a passphrase.

---

## Data Flow Diagrams

### Receipt Capture Flow

```
User taps "Capture"
        |
        v
+------------------+
|   Camera opens   |
|  (no gallery)    |
+------------------+
        |
        v
+------------------+
| JPEG captured    |
+------------------+
        |
        v
+------------------+
| Burn UTC         |
| timestamp into   |
| image pixels     |
+------------------+
        |
        v
+------------------+
| Compute SHA-256  |
| checksum         |
+------------------+
        |
        v
+------------------+       +------------------+
| Write file to    |       | Insert receipt    |
| local mirror     |------>| row into SQLite   |
| (no-overwrite)   |       | (offline-first)   |
+------------------+       +------------------+
                                    |
                                    v
                           +------------------+
                           | Enqueue upload    |
                           | in sync_queue     |
                           +------------------+
                                    |
                                    v
                           +------------------+
                           | Sync Engine       |
                           | picks up item     |
                           | (when online)     |
                           +------------------+
```

### Sync Data Flow

```
+-------------------+        +-------------------+        +--------------------+
|   Local Mirror    |        |   Sync Engine     |        |  Remote Storage    |
|   (on-disk JPEG)  |        |                   |        |  (Drive/Dropbox/   |
|                   |<------>|  1. Read queue     |<------>|   OneDrive/Box/    |
+-------------------+        |  2. Upload/Download|        |   Kira Cloud)      |
                             |  3. Verify checksum|        +--------------------+
+-------------------+        |  4. Commit or retry|
|   SQLite DB       |<------>|  5. Update cursor  |
|   (receipts,      |        |                   |
|    sync_queue,    |        +-------------------+
|    sync_state)    |
+-------------------+
```

---

## Trial -> Upgrade -> Backfill Flow

```
+-------------------+
|  First Capture    |
|  (trial starts)   |
+-------------------+
        |
        v
+-------------------+
|  Trial Mode       |
|  (7 days)         |
|  - Local only     |
|  - Full features  |
|  - No sync        |
+-------------------+
        |
        |  7 days pass without upgrade
        v
+-------------------+
|  Trial Expired    |
|  - Read-only mode |
|  - Upgrade wall   |
|  - Receipts auto- |
|    deleted 7 days |
|    after capture  |
+-------------------+
        |
        |  User chooses to upgrade
        v
+----------------------------+
|  Upgrade Flow              |
|  1. Select country         |
|  2. Choose storage provider|
|  3. OAuth login to provider|
|  4. Configure sync settings|
|  5. Begin backfill         |
+----------------------------+
        |
        v
+----------------------------+
|  Backfill                  |
|  - Scan all local receipts |
|  - Dedup by receipt_id     |
|    or checksum match       |
|  - Upload via two-step     |
|    commit                  |
|  - Never overwrite remote  |
|  - Integrity verify after  |
+----------------------------+
        |
        v
+----------------------------+
|  Normal Operation          |
|  - Bidirectional sync      |
|  - Background sync active  |
|  - Full feature access     |
+----------------------------+
```

---

## Sync Algorithm (Detailed)

```
FUNCTION runSync(adapter: StorageAdapter):
    IF NOT acquireLock():
        RETURN  // Another sync is running

    TRY:
        state = syncStateDao.getState(adapter.id)

        // === Phase 1: Local-to-Remote ===
        pendingOps = syncQueueDao.getPending(adapter.id)
        FOR EACH op IN pendingOps ORDER BY created_at ASC:
            syncQueueDao.markInProgress(op.id)
            TRY:
                SWITCH op.operation:
                    CASE upload:
                        remotePath = buildRemotePath(op.receipt)
                        adapter.uploadFile(op.receipt.filePath, remotePath)
                        remoteChecksum = adapter.getChecksum(remotePath)
                        ASSERT remoteChecksum == op.receipt.checksum
                    CASE update:
                        adapter.uploadFile(op.receipt.filePath, remotePath)
                    CASE delete:
                        adapter.deleteFile(remotePath)

                syncQueueDao.markCommitted(op.id)

            CATCH TransientError:
                syncQueueDao.incrementRetry(op.id)
                IF op.retryCount > MAX_RETRIES:
                    syncQueueDao.markFailed(op.id)

            CATCH AuthError:
                adapter.refreshToken()
                RETRY ONCE

        // === Phase 2: Remote-to-Local ===
        remoteFiles = adapter.listFiles(cursor: state.cursorToken)
        FOR EACH remoteFile IN remoteFiles:
            IF NOT receiptDao.existsByChecksum(remoteFile.checksum):
                localPath = buildLocalPath(remoteFile)
                IF NOT fileExists(localPath):  // No-overwrite check
                    adapter.downloadFile(remoteFile.path, localPath)
                    localChecksum = computeSHA256(localPath)
                    ASSERT localChecksum == remoteFile.checksum
                    receiptDao.insert(buildReceipt(remoteFile, localPath, localChecksum))

        // === Update Cursor ===
        syncStateDao.updateCursor(adapter.id, remoteFiles.newCursor)

    FINALLY:
        releaseLock()
```

---

## No-Overwrite Guarantees

The no-overwrite policy is enforced at multiple layers:

1. **Local Mirror:** Before writing any file, the mirror checks
   `File(path).existsSync()`. If the file exists, the write is aborted and
   an error is logged. This applies to both capture (new files) and sync
   (downloaded files).

2. **Database:** Receipt IDs are UUIDs generated at capture time. The
   `receipts` table uses `receipt_id` as a primary key. Attempting to insert
   a duplicate throws a constraint violation, which the DAO catches and
   resolves via the dedup path (compare checksums, keep existing).

3. **Remote Storage:** Upload operations target paths derived from
   `receipt_id`. Before uploading, the adapter checks `fileExists()`. If the
   remote file exists with a matching checksum, the upload is skipped
   (idempotent). If it exists with a different checksum, the conflict is
   flagged (this should not happen under normal operation).

4. **Backfill:** During post-upgrade backfill, each receipt is checked against
   the remote store by `receipt_id` and by `checksum`. If either matches, the
   receipt is considered already synced and is skipped.

---

## Index Merge Rules

When the Sync Engine encounters receipt records from multiple sources (e.g.,
during backfill from a second device or workspace member sync), index records
are merged according to these rules:

1. **Primary key match (`receipt_id`).** If a receipt with the same UUID exists
   locally, merge metadata fields using last-writer-wins on `updated_at`.
   The image file is never replaced (no-overwrite).

2. **Checksum match (different `receipt_id`).** If a receipt with a different
   UUID but identical SHA-256 checksum is found, this is treated as a
   duplicate capture. The older record (by `captured_at`) is kept; the newer
   duplicate is discarded. An audit event is logged.

3. **No match.** The remote receipt is inserted as a new local record. The
   image is downloaded to the mirror.

4. **Soft-delete propagation.** If a receipt is soft-deleted on one side, the
   deletion propagates to the other side during sync. Hard deletion occurs
   only after both sides confirm the soft delete.

5. **Conflict tie-breaking.** In the unlikely event of identical `updated_at`
   timestamps, the record with the lexicographically smaller `receipt_id` wins.
   This is deterministic and reproducible across devices.
