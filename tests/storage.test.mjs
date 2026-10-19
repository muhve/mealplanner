import { it } from 'node:test';
import assert from 'node:assert/strict';
import { backupDocument, loadDocument, saveDocument } from '../src/data/storage.web.ts';

it('keeps raw recovery backups when the active document is replaced, including timestamp collisions', t => {
  const values = new Map();
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
  } });
  t.after(() => {
    if (descriptor) Object.defineProperty(globalThis, 'localStorage', descriptor);
    else delete globalThis.localStorage;
  });
  t.mock.method(Date, 'now', () => 12345);
  const raw = '  {unreadable\n';
  saveDocument(raw);
  backupDocument(loadDocument());
  backupDocument('another broken document');
  saveDocument('{"replacement":true}');
  assert.equal(values.get('ruokalista-v1-backup-12345'), raw);
  assert.equal(values.get('ruokalista-v1-backup-12346'), 'another broken document');
  assert.equal(loadDocument(), '{"replacement":true}');
});
