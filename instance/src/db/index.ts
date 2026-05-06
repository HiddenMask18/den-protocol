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

  // Master secret blobs: the creator's encrypted master secret, stored as an opaque blob.
  // The instance cannot read this — it's encrypted to the creator's wallet public key.
  // Only the creator (holding their private key) can decrypt it.
  db.run(`
    CREATE TABLE IF NOT EXISTS master_secret_blobs (
      creator_proxy TEXT    PRIMARY KEY,
      blob          BLOB    NOT NULL,
      updated_at    INTEGER NOT NULL
    )
  `);

  // Content: metadata for each piece of encrypted content hosted on this instance.
  // The fingerprint (SHA-256 hash of the ciphertext) is the stable content identifier —
  // the same fingerprint registered on-chain in DENContentRegistry.
  db.run(`
    CREATE TABLE IF NOT EXISTS content (
      fingerprint   TEXT    PRIMARY KEY,
      creator_proxy TEXT    NOT NULL,
      tier_id       TEXT    NOT NULL,
      timestamp     INTEGER NOT NULL,
      warnings      TEXT
    )
  `);

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
}

export function getDb(): Database {
  if (!db) throw new Error('Database not initialized — call initDb() at startup before using getDb()');
  return db;
}
