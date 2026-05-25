// SQLite database setup for the DEN instance.
//
// Bun ships with a built-in SQLite driver (bun:sqlite) — no npm package needed, no separate
// database process to manage. For this early stage, SQLite is the right call: zero config,
// fast reads, and easy to inspect with standard tools. If the instance ever needs to scale
// horizontally (multiple instance processes), this would be the point to migrate to Postgres.
//
// Two functions are exported:
//   initDb() — call this once at startup; creates the file and all tables if they don't exist
//   getDb()  — call this anywhere else; returns the live database connection
//
// WAL (Write-Ahead Logging) mode is enabled so that reads don't block writes — important
// once the instance is handling concurrent subscriber requests alongside creator uploads.

import { Database } from 'bun:sqlite';

const DB_PATH = process.env.DB_PATH ?? './den-instance.db';

let db: Database;

export function initDb(): void {
  db = new Database(DB_PATH, { create: true });

  // WAL mode: readers don't block writers and vice versa.
  db.run('PRAGMA journal_mode = WAL');
  // Enforce foreign key constraints (SQLite ignores them by default).
  db.run('PRAGMA foreign_keys = ON');

  // Sessions: issued after successful wallet-signature authentication.
  // Each session is tied to a proxy address (the stable DEN identity) and the wallet
  // that authenticated. Token is a 32-byte random hex string; expires after 24h.
  db.run(`
    CREATE TABLE IF NOT EXISTS sessions (
      token      TEXT    PRIMARY KEY,
      proxy      TEXT    NOT NULL,
      wallet     TEXT    NOT NULL,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    )
  `);

  // Master secret blobs: ECIES-encrypted copies of the creator's master secret.
  //
  // Dual-blob model (spec §4.1):
  //   blob                      — operational blob, encrypted to the instance-derived per-creator pubkey.
  //                               The instance decrypts this on demand at key delivery time. Creator cannot
  //                               decrypt it (they don't hold the instance's private key).
  //                               NULL when only a portability blob has been stored (migration import state —
  //                               creator must re-upload operational blob via PUT /creator/blob).
  //   portability_blob          — portability blob, encrypted to the creator's primary wallet pubkey.
  //                               The instance cannot decrypt this. Only the creator can, using their wallet.
  //                               Used for migration and recovery (spec §8.1).
  //   emergency_portability_blob — portability blob encrypted to the creator's emergency wallet pubkey.
  //                               NULL until an emergency wallet is registered and the blob uploaded.
  //                               Only the emergency wallet can decrypt this.
  //
  // All blobs are always ECIES ciphertext. Plaintext never persists in the database.
  db.run(`
    CREATE TABLE IF NOT EXISTS master_secret_blobs (
      creator_proxy              TEXT    PRIMARY KEY,
      blob                       BLOB,
      portability_blob           BLOB,
      emergency_portability_blob BLOB,
      oracle_url                 TEXT,    -- unused in V1; retained for schema compatibility
      updated_at                 INTEGER NOT NULL
    )
  `);

  type ColInfo = { name: string; notnull: number };

  // Migration: add portability_blob column to existing databases.
  const blobCols = db.query<ColInfo, []>('PRAGMA table_info(master_secret_blobs)').all();
  if (!blobCols.some((c) => c.name === 'portability_blob')) {
    db.run('ALTER TABLE master_secret_blobs ADD COLUMN portability_blob BLOB');
  }

  // Migration: add emergency_portability_blob column (spec §4.1 emergency wallet support).
  if (!blobCols.some((c) => c.name === 'emergency_portability_blob')) {
    db.run('ALTER TABLE master_secret_blobs ADD COLUMN emergency_portability_blob BLOB');
  }

  // Migration: add oracle_url column — unused in V1 (threshold split removed); retained for
  // schema compatibility with databases written before the oracle model was removed.
  if (!blobCols.some((c) => c.name === 'oracle_url')) {
    db.run('ALTER TABLE master_secret_blobs ADD COLUMN oracle_url TEXT');
  }

  // Migration: make blob column nullable (needed for migration import where only the
  // portability blob is provided; the creator re-uploads the operational blob separately).
  // SQLite cannot alter column constraints in-place — requires table recreation.
  const blobColInfo = blobCols.find((c) => c.name === 'blob');
  if (blobColInfo?.notnull === 1) {
    db.run('BEGIN');
    try {
      db.run(`
        CREATE TABLE master_secret_blobs_new (
          creator_proxy    TEXT    PRIMARY KEY,
          blob             BLOB,
          portability_blob BLOB,
          updated_at       INTEGER NOT NULL
        )
      `);
      db.run('INSERT INTO master_secret_blobs_new SELECT creator_proxy, blob, portability_blob, updated_at FROM master_secret_blobs');
      db.run('DROP TABLE master_secret_blobs');
      db.run('ALTER TABLE master_secret_blobs_new RENAME TO master_secret_blobs');
      db.run('COMMIT');
    } catch (err) {
      db.run('ROLLBACK');
      throw err;
    }
  }

  // Creator profiles: instance-side display name metadata (spec §6.2).
  // The handle (pseudonymous name) lives on-chain; bio lives here.
  // Upserted via PUT /creator/profile.
  db.run(`
    CREATE TABLE IF NOT EXISTS creator_profile (
      creator_proxy TEXT    PRIMARY KEY,
      bio           TEXT,
      updated_at    INTEGER NOT NULL
    )
  `);

  // Content: metadata and ciphertext for each piece of encrypted content hosted on this instance.
  // The fingerprint (SHA-256 hash of the ciphertext) is the stable content identifier —
  // the same fingerprint registered on-chain in DENContentRegistry.
  // ciphertext is nullable: NULL for migration references (is_reference=1) where the
  // actual bytes live on IPFS and have not yet been retrieved by this instance.
  // is_public=1 means the creator has designated this content publicly visible (spec §6.3).
  // public_key holds the 32-byte content decryption key when is_public=1 — intentionally
  // public, so storing it here does not violate the "no stored keys" rule (§4.2).
  db.run(`
    CREATE TABLE IF NOT EXISTS content (
      fingerprint   TEXT    PRIMARY KEY,
      creator_proxy TEXT    NOT NULL,
      tier_id       TEXT    NOT NULL,
      ciphertext    BLOB,
      timestamp     INTEGER NOT NULL,
      warnings      TEXT,
      is_reference  INTEGER NOT NULL DEFAULT 0,
      is_public     INTEGER NOT NULL DEFAULT 0,
      public_key    BLOB
    )
  `);

  const contentCols = db.query<ColInfo, []>('PRAGMA table_info(content)').all();

  // Migration: add ciphertext column to databases predating Phase 3.
  if (!contentCols.some((c) => c.name === 'ciphertext')) {
    db.run('ALTER TABLE content ADD COLUMN ciphertext BLOB');
  }

  // Migration: add is_reference column (Phase 4 — migration support).
  // Existing rows are local uploads (is_reference=0).
  if (!contentCols.some((c) => c.name === 'is_reference')) {
    db.run('ALTER TABLE content ADD COLUMN is_reference INTEGER NOT NULL DEFAULT 0');
  }

  // Migration: add is_public and public_key columns (spec §6.3 — public preview content).
  // Existing rows are private by default (is_public=0, public_key=NULL).
  if (!contentCols.some((c) => c.name === 'is_public')) {
    db.run('ALTER TABLE content ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0');
  }
  if (!contentCols.some((c) => c.name === 'public_key')) {
    db.run('ALTER TABLE content ADD COLUMN public_key BLOB');
  }

  // Access grants: creator-signed declarations mapping tier IDs to key derivation paths.
  // These tell the instance which derivation path to use when a subscriber requests access
  // to a given tier. The signature is stored alongside the declaration and verified before
  // any key is derived (both here and live against the on-chain DENAccessGrant contract).
  db.run(`
    CREATE TABLE IF NOT EXISTS access_grants (
      creator_proxy TEXT    NOT NULL,
      tier_id       TEXT    NOT NULL,
      declaration   TEXT    NOT NULL,
      signature     TEXT    NOT NULL,
      version       INTEGER NOT NULL,
      PRIMARY KEY (creator_proxy, tier_id)
    )
  `);

  // Subscriber state: local mirror of on-chain subscription state, written on every
  // successful key delivery (spec §4.2 — instances MUST mirror subscriber state locally).
  // Expiry is Unix seconds (uint256 on chain, fits safely in SQLite INTEGER for any
  // plausible subscription period). Updated on every successful access request so the
  // record reflects the subscriber's most recently observed active expiry.
  db.run(`
    CREATE TABLE IF NOT EXISTS subscriber_state (
      subscriber_proxy TEXT    NOT NULL,
      creator_proxy    TEXT    NOT NULL,
      tier_id          TEXT    NOT NULL,
      expiry           INTEGER NOT NULL,
      updated_at       INTEGER NOT NULL,
      PRIMARY KEY (subscriber_proxy, creator_proxy, tier_id)
    )
  `);

  // Report evidence: off-chain evidence submitted by subscribers for protocol floor reports.
  // The subscriber stores evidence here to get an evidenceHash (keccak256 of evidence bytes)
  // before calling DENReportRegistry.fileReport on-chain with that hash (spec §12.2).
  // Stored so the creator can be notified with full report contents on suspension (spec §12.4).
  // evidence_hash is 0x-prefixed keccak256 hex; category: 0=CSAM, 1=NON_CONSENT.
  db.run(`
    CREATE TABLE IF NOT EXISTS report_evidence (
      evidence_hash  TEXT    PRIMARY KEY,
      fingerprint    TEXT    NOT NULL,
      reporter_proxy TEXT    NOT NULL,
      category       INTEGER NOT NULL,
      evidence       BLOB    NOT NULL,
      submitted_at   INTEGER NOT NULL
    )
  `);
}

export function getDb(): Database {
  if (!db) throw new Error('Database not initialized — call initDb() at startup before using getDb()');
  return db;
}
