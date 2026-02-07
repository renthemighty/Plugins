# Trial Mode and Upgrade Flow

## Trial Policy

### Activation

The trial period begins automatically on the user's **first receipt capture**.
There is no sign-up, no email collection, and no account creation required to
start the trial. The moment the camera captures the first receipt, the app
records `first_capture_at` in the `trial_state` table and computes
`trial_expires_at` as `first_capture_at + 7 days`.

### Duration

The trial lasts **7 calendar days** from the first capture timestamp (UTC).
The countdown is based on wall-clock time, not usage time. Uninstalling and
reinstalling the app does not reset the trial (the trial state persists in
the database, which is backed up if the OS supports app data backup; on a
true fresh install, the trial resets but all prior receipts are lost).

### What Works During Trial

During the trial period, the user has access to the full local feature set:

| Feature | Available | Notes |
|---|---|---|
| Camera capture | Yes | Unlimited receipts |
| Timestamp burning | Yes | Applied to every capture |
| Checksum generation | Yes | SHA-256 computed on every image |
| Local mirror storage | Yes | Full folder structure |
| SQLite database | Yes | All tables, same schema as paid |
| Receipt search/filter | Yes | By date, vendor, category |
| Reports (daily/monthly/quarterly/yearly) | Yes | Generated locally |
| CSV export | Yes | From local data |
| Tax export | Yes | From local data |
| i18n / locale formatting | Yes | All supported locales |
| App lock (biometric/PIN) | Yes | Security is not gated |
| Integrity auditor | Yes | Runs on local data |
| Cloud sync | **No** | Requires upgrade |
| Storage adapter connection | **No** | Requires upgrade |
| QuickBooks / TurboTax export | **No** | Requires upgrade |
| Business workspaces | **No** | Requires upgrade |

**No internet connection is required during the trial.** The app is fully
functional offline. The database schema and local mirror structure are
identical to the paid version -- there is no migration or data transformation
when the user upgrades.

---

## Trial Expiry

### Expired Receipt Auto-Deletion

Receipts captured during the trial are subject to auto-deletion if the user
does not upgrade:

- Each receipt has an implicit expiry of **7 days after its individual
  `captured_at` timestamp**.
- When the trial expires and the user has NOT upgraded, receipts whose
  `captured_at + 7 days` has passed are automatically deleted.
- Deletion is **permanent**: the image file is removed from the local mirror,
  the database row is hard-deleted, and the thumbnail is removed.
- Deletion happens lazily: each time the app is opened after trial expiry,
  it checks for and removes expired receipts.

**Example timeline:**

```
Day 0:  User captures Receipt A.  Trial starts.
Day 3:  User captures Receipt B.
Day 6:  User captures Receipt C.
Day 7:  Trial expires.
        - Receipt A is now 7 days old -> auto-deleted.
        - Receipts B and C are still within their 7-day window.
Day 10: - Receipt B is now 7 days old -> auto-deleted.
        - Receipt C has 3 days remaining.
Day 13: - Receipt C is now 7 days old -> auto-deleted.
Day 13+: All trial receipts are gone. The app is empty.
```

### Read-Only Mode

After the trial expires:

- The user **cannot capture new receipts**. The capture button is disabled
  and shows an upgrade prompt.
- The user **can still view** existing receipts (those not yet auto-deleted).
- The user **can still generate reports** from existing data.
- The user **can still export CSV/tax files** from existing data.
- An **upgrade wall** is presented on every app open and on any action that
  requires capture or sync.

### Upgrade Wall

The upgrade wall is a non-dismissible modal that appears when the user
attempts a gated action. It shows:

1. A clear explanation of what the trial included and what expired.
2. The number of receipts at risk of auto-deletion and their deadlines.
3. A prominent "Upgrade Now" button that initiates the upgrade flow.
4. A "Maybe Later" option that returns to read-only mode.

---

## Upgrade Flow

When the user taps "Upgrade Now," they proceed through a guided setup:

### Step 1: Select Country

```
+----------------------------------+
|  Where are you located?          |
|                                  |
|  [  Canada            ]  >      |
|  [  United States     ]  >      |
|                                  |
|  This determines your currency,  |
|  tax categories, and available   |
|  accounting integrations.        |
+----------------------------------+
```

The country selection determines:
- Default currency (CAD / USD).
- Tax category mappings (GST/HST for Canada, sales tax for US).
- Available accounting adapters (region-specific rules).
- Locale formatting defaults.

### Step 2: Choose Storage Provider

```
+----------------------------------+
|  Where should Kira store your    |
|  receipts?                       |
|                                  |
|  [  Google Drive      ]  >      |
|  [  Dropbox           ]  >      |
|  [  OneDrive          ]  >      |
|  [  Box               ]  >      |
|  [  Local Encrypted   ]  >      |
|  [  Kira Cloud        ]  >      |
|                                  |
|  You can change this later in    |
|  Settings.                       |
+----------------------------------+
```

The user selects one primary storage provider. Additional providers can be
added later. "Local Encrypted" keeps files on-device with AES-256-GCM
encryption and does not require an account.

### Step 3: Login to Storage Provider

For cloud providers, the app initiates the OAuth 2.0 + PKCE flow:

1. The app opens the system browser to the provider's consent page.
2. The user logs into their account (Google, Dropbox, Microsoft, Box, or
   Kira) and grants Kira access.
3. The browser redirects back to the app with an authorization code.
4. The app exchanges the code for access and refresh tokens.
5. Tokens are stored securely in Keychain (iOS) / Keystore (Android).

**The user never sees or enters API keys, client secrets, or tokens.**
The entire flow is transparent and handled by the app.

For "Local Encrypted," this step is replaced by setting an encryption
passphrase (or using device biometrics to derive the key).

### Step 4: Configure Sync Settings

```
+----------------------------------+
|  Sync Settings                   |
|                                  |
|  Sync frequency:                 |
|    ( ) Real-time                 |
|    (*) Every 15 minutes          |
|    ( ) Hourly                    |
|    ( ) Manual only               |
|                                  |
|  Sync over:                      |
|    [x] Wi-Fi                     |
|    [ ] Cellular data             |
|                                  |
|  Background sync:                |
|    [x] Enabled                   |
|                                  |
+----------------------------------+
```

### Step 5: Backfill

After authentication succeeds, the app initiates backfill of all existing
local receipts to the newly connected storage provider. See the Backfill
section below for details.

---

## Backfill

Backfill is the process of uploading all locally-stored trial receipts to
the user's chosen remote storage after upgrade. It is designed to be safe,
idempotent, and non-destructive.

### Triggering Conditions

Backfill runs automatically when:
- The user completes the upgrade flow (Step 5 above).
- The user connects a new storage provider in Settings.
- The app detects local receipts that have no corresponding `sync_queue`
  entry for the active adapter (e.g., after a reinstall with database
  restore).

### Deduplication Rules

Before uploading each receipt, the backfill engine checks for duplicates:

1. **By `receipt_id`:** Query the remote storage for a file named
   `<receipt_id>.jpg` in the expected folder path. If found, compare
   checksums:
   - Checksums match: Receipt is already synced. Skip. Mark as committed.
   - Checksums differ: This should not happen (no-overwrite policy). Log an
     integrity warning and skip the upload. Do NOT overwrite the remote file.

2. **By checksum:** If no file matches by `receipt_id`, compute a checksum
   index of remote files (if available via the adapter's API). If a remote
   file with the same SHA-256 checksum exists under a different name, treat
   it as a duplicate:
   - Log the duplicate detection.
   - Link the local receipt to the existing remote file.
   - Do NOT upload a second copy.

3. **No match:** The receipt is genuinely new to the remote store. Proceed
   with upload via the standard two-step commit protocol.

### Upload Protocol

Each backfill upload follows the same two-step commit used by normal sync:

```
1. Enqueue: Insert into sync_queue with operation = upload, status = pending.
2. Prepare: Upload the file to the remote storage adapter.
3. Verify: Confirm the remote file exists and its checksum matches the local
   checksum.
4. Commit: Mark the sync_queue entry as committed. Update sync_state cursor.
```

If any step fails:
- The upload is retried with exponential backoff (up to 5 attempts).
- After max retries, the entry is marked as failed and the user is notified.
- Failed backfill items can be retried manually from Settings.

### No-Overwrite During Backfill

The no-overwrite policy applies strictly during backfill:

- If a remote file exists at the target path, it is NEVER overwritten,
  regardless of age, size, or content.
- If the local file's checksum matches the remote file's checksum, the
  upload is skipped (idempotent).
- If the checksums differ, the conflict is logged and the upload is skipped.
  The user is notified of the conflict.

### Integrity Verification After Backfill

After all backfill uploads complete, the Integrity Auditor runs a full
consistency check:

1. **Completeness check:** Every receipt in the local database has a
   corresponding file in remote storage. Any gaps are flagged.
2. **Checksum verification:** A random sample (or all, if the count is small)
   of remote files are downloaded temporarily and their checksums are verified
   against the local database.
3. **Mirror consistency:** The local mirror is verified against the database
   (no orphans, no missing files).
4. **Report:** A summary is shown to the user:
   - Total receipts backfilled.
   - Duplicates skipped.
   - Failures (if any) with retry option.
   - Integrity verification result (pass / warnings / failures).

### Progress Indication

During backfill, the app shows:
- A progress bar with `N of M receipts uploaded`.
- Estimated time remaining (based on average upload speed).
- A "Pause" button to defer remaining uploads to background sync.
- The app remains usable during backfill; new captures proceed normally
  and are enqueued for sync alongside backfill items.

### Background Backfill

If the user backgrounds the app during backfill:
- On Android, backfill continues via WorkManager.
- On iOS, backfill continues via BGProcessingTask (large transfers).
- A persistent notification (Android) or background activity indicator (iOS)
  shows progress.
- When backfill completes in the background, a local notification informs
  the user.
