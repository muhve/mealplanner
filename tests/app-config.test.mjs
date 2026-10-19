import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const { expo } = JSON.parse(readFileSync(new URL('../app.json', import.meta.url), 'utf8'));

test('app.json keeps the identifiers the deploy pipeline relies on', () => {
  assert.equal(expo.ios.bundleIdentifier, 'fi.muhve.mealplanner');
  assert.deepEqual(expo.runtimeVersion, { policy: 'fingerprint' });
  assert.ok(expo.plugins.includes('expo-updates'));
});
