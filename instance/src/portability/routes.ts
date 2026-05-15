// Creator portability routes — migration export and import (spec §8).
//
// Both routes require a valid session (Authorization: Bearer <token>).
// A creator can only export or import their own data — the session proxy
// is used as the creator identity throughout.
//
// GET /creator/export
//   Returns the creator's minimum portable data set as a signed JSON bundle.
//   Includes: portability blob, content references, access grants, subscriber
//   list (from chain events), buyer list (from chain events), identity record.
//   503 if the portability blob hasn't been uploaded yet.
//
// POST /creator/import
//   Accepts a portable data bundle on a receiving instance.
//   Spec §8.2: verifies ALL access grant signatures before writing anything;
//   rejects the entire import if any signature fails.
//   After a successful import:
//     - GET /creator/blob returns { exists: false } — creator must re-upload
//       the operational blob via PUT /creator/blob (re-encrypted to this instance's key)
//     - GET /creator/grant/:tierId returns imported grants
//     - POST /access/key will work once the operational blob is uploaded
//
// Migration flow for a creator leaving instanceA and joining instanceB:
//   1. GET  instanceA/creator/export          → bundle.json
//   2. GET  instanceB/creator/blob-pubkey     → instanceB's per-creator pubkey
//   3. Client: decrypt portabilityBlob → re-encrypt to instanceB pubkey → operationalBlob
//   4. POST instanceB/creator/import          → body: bundle.json
//   5. PUT  instanceB/creator/blob            → { operationalBlob, portabilityBlob }
//   6. Creator registers new instance URL on-chain (DENIdentityImpl.updateInstanceURL)

import { Hono } from 'hono';
import { requireAuth } from '../auth/middleware.ts';
import { assemblePortableData, PortabilityError } from './export.ts';
import { importPortableData, ImportValidationError } from './import.ts';
import type { PortableDataBundle } from './export.ts';

type SessionEnv = {
  Variables: {
    proxy: string;
    wallet: string;
  };
};

export const portabilityRoutes = new Hono<SessionEnv>();

portabilityRoutes.get('/export', requireAuth, async (c) => {
  const proxy = c.get('proxy');

  try {
    const bundle = await assemblePortableData(proxy);
    return c.json(bundle);
  } catch (err) {
    if (err instanceof PortabilityError) {
      return c.json({ error: err.message }, 503);
    }
    throw err;
  }
});

portabilityRoutes.post('/import', requireAuth, async (c) => {
  let bundle: PortableDataBundle;
  try {
    bundle = await c.req.json();
  } catch {
    return c.json({ error: 'request body must be valid JSON' }, 400);
  }

  if (bundle.version !== 1) {
    return c.json({ error: 'unsupported bundle version (expected 1)' }, 400);
  }
  if (!bundle.creatorProxy || typeof bundle.creatorProxy !== 'string') {
    return c.json({ error: 'bundle.creatorProxy is required' }, 400);
  }
  if (!bundle.portabilityBlob || typeof bundle.portabilityBlob !== 'string') {
    return c.json({ error: 'bundle.portabilityBlob is required' }, 400);
  }
  if (!Array.isArray(bundle.accessGrants)) {
    return c.json({ error: 'bundle.accessGrants must be an array' }, 400);
  }
  if (!Array.isArray(bundle.contentReferences)) {
    return c.json({ error: 'bundle.contentReferences must be an array' }, 400);
  }

  const proxy = c.get('proxy');

  // Bundle must belong to the authenticated creator — prevents one creator from
  // overwriting another creator's data on a shared instance.
  if (bundle.creatorProxy.toLowerCase() !== proxy.toLowerCase()) {
    return c.json(
      { error: 'bundle.creatorProxy does not match authenticated session — import rejected' },
      403,
    );
  }

  try {
    const result = await importPortableData(bundle, proxy);
    return c.json({
      imported: true,
      grantsImported: result.grantsImported,
      contentReferencesImported: result.contentReferencesImported,
      portabilityBlobStored: result.portabilityBlobStored,
      next: 'upload operational blob via PUT /creator/blob to enable key delivery',
    });
  } catch (err) {
    if (err instanceof ImportValidationError) {
      return c.json({ error: err.message }, 422);
    }
    throw err;
  }
});
