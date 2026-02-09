/// Centralised SQLite database helper for the Kira app.
///
/// Uses the singleton pattern so that every consumer shares a single
/// [Database] instance.  Schema migrations are handled via explicit
/// version-gated DDL in [_onUpgrade].
library;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Current schema version.  Bump this and add a migration block inside
/// [_onUpgrade] whenever the schema changes.
const int _kDatabaseVersion = 1;

/// Database file name on disk.
const String _kDatabaseName = 'kira.db';

class DatabaseHelper {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  DatabaseHelper._internal();

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  /// Returns the single [DatabaseHelper] instance.
  factory DatabaseHelper() => _instance;

  /// Visible-for-testing factory that returns the singleton.
  /// This exists so test harnesses can inject an in-memory database via
  /// [setTestDatabase].
  static DatabaseHelper get instance => _instance;

  Database? _database;

  /// Returns the open [Database], creating it on the first call.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Allows tests to inject a pre-configured (e.g. in-memory) database.
  void setTestDatabase(Database db) {
    _database = db;
  }

  /// Closes the database and resets the cached instance.  Useful in tests and
  /// during sign-out flows.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _database = null;
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _kDatabaseName);

    return openDatabase(
      path,
      version: _kDatabaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  /// Enable foreign-key enforcement for every connection.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // ---------------------------------------------------------------------------
  // Schema – v1  (initial)
  // ---------------------------------------------------------------------------

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ── receipts ──────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE receipts (
        receipt_id          TEXT PRIMARY KEY,
        captured_at         TEXT NOT NULL,
        timezone            TEXT NOT NULL,
        filename            TEXT NOT NULL,
        amount_tracked      REAL NOT NULL,
        currency_code       TEXT NOT NULL,
        country             TEXT NOT NULL,
        region              TEXT NOT NULL,
        category            TEXT NOT NULL,
        notes               TEXT,
        tax_applicable      INTEGER,
        checksum_sha256     TEXT NOT NULL,
        device_id           TEXT NOT NULL,
        capture_session_id  TEXT NOT NULL,
        source              TEXT NOT NULL DEFAULT 'camera',
        created_at          TEXT NOT NULL,
        updated_at          TEXT NOT NULL,
        conflict            INTEGER NOT NULL DEFAULT 0,
        supersedes_filename TEXT,
        sync_status         TEXT NOT NULL DEFAULT 'local',
        uploaded_at         TEXT,
        indexed_at          TEXT,
        local_path          TEXT,
        remote_path         TEXT,
        expired             INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_receipts_captured_at ON receipts (captured_at)',
    );
    batch.execute(
      'CREATE UNIQUE INDEX idx_receipts_filename ON receipts (filename)',
    );
    batch.execute(
      'CREATE INDEX idx_receipts_sync_status ON receipts (sync_status)',
    );
    batch.execute(
      'CREATE INDEX idx_receipts_country ON receipts (country)',
    );
    batch.execute(
      'CREATE INDEX idx_receipts_category ON receipts (category)',
    );
    batch.execute(
      'CREATE INDEX idx_receipts_region ON receipts (region)',
    );
    batch.execute(
      'CREATE INDEX idx_receipts_expired ON receipts (expired)',
    );

    // ── sync_queue ────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE sync_queue (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id    TEXT NOT NULL,
        action        TEXT NOT NULL,
        status        TEXT NOT NULL DEFAULT 'pending',
        retry_count   INTEGER NOT NULL DEFAULT 0,
        last_attempt  TEXT,
        error_message TEXT,
        created_at    TEXT NOT NULL
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_sync_queue_status ON sync_queue (status)',
    );
    batch.execute(
      'CREATE INDEX idx_sync_queue_receipt ON sync_queue (receipt_id)',
    );

    // ── integrity_alerts ──────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE integrity_alerts (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id  TEXT,
        alert_type  TEXT NOT NULL,
        description TEXT NOT NULL,
        file_path   TEXT,
        severity    TEXT NOT NULL DEFAULT 'warning',
        resolved           INTEGER NOT NULL DEFAULT 0,
        created_at         TEXT NOT NULL,
        resolved_at        TEXT,
        recommended_action TEXT
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_integrity_alerts_resolved ON integrity_alerts (resolved)',
    );
    batch.execute(
      'CREATE INDEX idx_integrity_alerts_type ON integrity_alerts (alert_type)',
    );

    // ── app_settings (key-value) ──────────────────────────────────────────
    batch.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // ── workspaces ────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE workspaces (
        workspace_id  TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        owner_user_id TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL
      )
    ''');

    // ── workspace_members ─────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE workspace_members (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id  TEXT NOT NULL,
        user_id       TEXT NOT NULL,
        role          TEXT NOT NULL,
        display_name  TEXT,
        email         TEXT,
        invited_at    TEXT NOT NULL,
        joined_at     TEXT,
        FOREIGN KEY (workspace_id) REFERENCES workspaces (workspace_id)
          ON DELETE CASCADE
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_workspace_members_ws ON workspace_members (workspace_id)',
    );
    batch.execute(
      'CREATE UNIQUE INDEX idx_workspace_members_unique '
      'ON workspace_members (workspace_id, user_id)',
    );

    // ── trips ─────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE trips (
        trip_id       TEXT PRIMARY KEY,
        workspace_id  TEXT NOT NULL,
        name          TEXT NOT NULL,
        description   TEXT,
        start_date    TEXT,
        end_date      TEXT,
        created_by    TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL,
        FOREIGN KEY (workspace_id) REFERENCES workspaces (workspace_id)
          ON DELETE CASCADE
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_trips_workspace ON trips (workspace_id)',
    );

    // ── expense_reports ───────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE expense_reports (
        report_id     TEXT PRIMARY KEY,
        workspace_id  TEXT NOT NULL,
        trip_id       TEXT,
        title         TEXT NOT NULL,
        status        TEXT NOT NULL DEFAULT 'draft',
        total_amount  REAL NOT NULL DEFAULT 0.0,
        currency_code TEXT NOT NULL DEFAULT 'CAD',
        submitted_by  TEXT,
        submitted_at  TEXT,
        approved_by   TEXT,
        approved_at   TEXT,
        notes         TEXT,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL,
        FOREIGN KEY (workspace_id) REFERENCES workspaces (workspace_id)
          ON DELETE CASCADE,
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id)
          ON DELETE SET NULL
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_expense_reports_workspace '
      'ON expense_reports (workspace_id)',
    );
    batch.execute(
      'CREATE INDEX idx_expense_reports_status ON expense_reports (status)',
    );
    batch.execute(
      'CREATE INDEX idx_expense_reports_trip ON expense_reports (trip_id)',
    );

    // ── audit_events ──────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE audit_events (
        event_id      TEXT PRIMARY KEY,
        workspace_id  TEXT NOT NULL,
        user_id       TEXT NOT NULL,
        action        TEXT NOT NULL,
        target_type   TEXT,
        target_id     TEXT,
        metadata      TEXT,
        created_at    TEXT NOT NULL,
        FOREIGN KEY (workspace_id) REFERENCES workspaces (workspace_id)
          ON DELETE CASCADE
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_audit_events_workspace ON audit_events (workspace_id)',
    );
    batch.execute(
      'CREATE INDEX idx_audit_events_created ON audit_events (created_at)',
    );

    // ── error_records ─────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE error_records (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        error_type  TEXT NOT NULL,
        message     TEXT NOT NULL,
        stack_trace TEXT,
        context     TEXT,
        device_id   TEXT,
        app_version TEXT,
        resolved    INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT NOT NULL
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_error_records_type ON error_records (error_type)',
    );
    batch.execute(
      'CREATE INDEX idx_error_records_created ON error_records (created_at)',
    );
    batch.execute(
      'CREATE INDEX idx_error_records_resolved ON error_records (resolved)',
    );

    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------------
  // Migrations
  // ---------------------------------------------------------------------------

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Each migration block is guarded so that upgrading from *any* prior
    // version applies exactly the right set of ALTER / CREATE statements.
    //
    // Example for a future v2:
    //
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE receipts ADD COLUMN foo TEXT');
    // }
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Deletes every row from every table.  Intended **only** for development /
  /// testing — never expose this through production UI.
  Future<void> deleteAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('error_records');
      await txn.delete('audit_events');
      await txn.delete('expense_reports');
      await txn.delete('trips');
      await txn.delete('workspace_members');
      await txn.delete('workspaces');
      await txn.delete('integrity_alerts');
      await txn.delete('sync_queue');
      await txn.delete('receipts');
      await txn.delete('app_settings');
    });
  }
}
