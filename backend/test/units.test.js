/**
 * Pure-logic checks — no database, no server. These cover the bits that would
 * silently corrupt data if they broke: the AI response normaliser (untrusted
 * input crossing into our tables), the distance sort that picks a hospital, the
 * derived age, and the request validators.
 *
 *   npm test
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { chatPrompt, normaliseChatResponse, normaliseTriage } from '../src/lib/ai.js';
import { distanceKm } from '../src/lib/triage.js';
import { ageFrom, bool, enumOf, num, str, uuid, email } from '../src/lib/http.js';

test('normaliseTriage clamps urgency into the schema range', () => {
  assert.equal(normaliseTriage({ urgency: 9 }).urgency, 5);
  assert.equal(normaliseTriage({ urgency: 0 }).urgency, 1);
  assert.equal(normaliseTriage({ urgency: 3.4 }).urgency, 3);
  assert.equal(normaliseTriage({ urgency: 'high' }).urgency, null);
  assert.equal(normaliseTriage({}).urgency, null);
});

test('normaliseTriage refuses to invent a red flag', () => {
  assert.equal(normaliseTriage({ red_flag: 'yes' }).red_flag, false, 'only literal true counts');
  assert.equal(normaliseTriage({ red_flag: 1 }).red_flag, false);
  assert.equal(normaliseTriage({ red_flag: true }).red_flag, true);
});

test('normaliseTriage drops wrong-typed fields instead of storing them', () => {
  const t = normaliseTriage({
    specialty: 42,
    symptoms: 'fever',
    sources: { a: 1 },
    follow_up_questions: [{ id: 'q' }],
    status: 'exploded',
  });
  assert.equal(t.specialty, null);
  assert.equal(t.symptoms, null);
  assert.equal(t.sources, null);
  assert.deepEqual(t.follow_up_questions, [{ id: 'q' }]);
  assert.equal(t.status, 'ok', 'unknown status falls back, never passes through');
});

test('normaliseTriage survives garbage input', () => {
  for (const input of [null, undefined, 'nope', 7, []]) {
    const t = normaliseTriage(input);
    assert.equal(t.red_flag, false);
    assert.equal(t.urgency, null);
  }
});

test('the AI boundary sends only the deterministic chat request shape', () => {
  assert.deepEqual(
    chatPrompt({
      request_id: 'request-1',
      session_id: '11111111-1111-1111-1111-111111111111',
      user_query: ' It started this morning. ',
    }),
    {
      session_id: '11111111-1111-1111-1111-111111111111',
      user_query: 'It started this morning.',
      hospitals: [],
    },
  );
});

test('a chat response becomes the existing persistence contract without triage orchestration', () => {
  assert.deepEqual(
    normaliseChatResponse(
      {
        session_id: '11111111-1111-1111-1111-111111111111',
        response_type: 'mcq',
        content: { question: 'How severe is it?', options: ['Mild', 'Severe'] },
      },
      'request-1',
    ),
    {
      request_id: 'request-1',
      status: 'needs_more_info',
      reply: 'How severe is it?',
      follow_up_questions: [
        { id: 'q1', question: 'How severe is it?', options: ['Mild', 'Severe'], multi: false },
      ],
    },
  );
  assert.deepEqual(
    normaliseChatResponse({ response_type: 'text', content: 'Your report is ready.' }, 'request-2'),
    { request_id: 'request-2', status: 'ok', reply: 'Your report is ready.' },
  );
});

test('distanceKm measures and refuses incomplete coordinates', () => {
  // Bhubaneswar seed hospitals are roughly 6 km apart.
  const d = distanceKm({ lat: 20.2961, lng: 85.8245 }, { lat: 20.3499, lng: 85.8197 });
  assert.ok(d > 5 && d < 7, `expected ~6 km, got ${d}`);
  assert.equal(distanceKm({ lat: 20, lng: null }, { lat: 21, lng: 85 }), null);
  assert.equal(distanceKm(null, { lat: 21, lng: 85 }), null);
});

test('distanceKm sorts nearest first', () => {
  const me = { lat: 20.2961, lng: 85.8245 };
  const far = distanceKm(me, { lat: 28.6139, lng: 77.209 });   // Delhi
  const near = distanceKm(me, { lat: 20.3499, lng: 85.8197 });
  assert.ok(near < far);
});

test('ageFrom derives whole years and rejects nonsense', () => {
  const today = new Date();
  const iso = (y, m, d) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  // A birthday that has already happened this year.
  assert.equal(ageFrom(iso(today.getUTCFullYear() - 30, 1, 1)), 30);
  // A birthday still to come this year.
  assert.equal(ageFrom(iso(today.getUTCFullYear() - 30, 12, 31)), today.getUTCMonth() === 11 && today.getUTCDate() === 31 ? 30 : 29);
  assert.equal(ageFrom(null), null);
  assert.equal(ageFrom('not-a-date'), null);
});

test('validators reject what the schema would reject', () => {
  assert.throws(() => str({}, 'name', { required: true }), /name is required/);
  assert.throws(() => str({ name: '   ' }, 'name', { required: true }), /name is required/);
  assert.throws(() => str({ name: 'x'.repeat(20) }, 'name', { max: 5 }), /at most 5/);
  assert.equal(str({ name: ' ok ' }, 'name'), 'ok');

  assert.throws(() => num({ urgency: 'x' }, 'urgency'), /must be a number/);
  assert.throws(() => num({ urgency: 9 }, 'urgency', { max: 5 }), /<= 5/);

  assert.throws(() => enumOf({ k: 'nope' }, 'k', ['a', 'b']), /one of: a, b/);
  assert.equal(enumOf({ k: 'a' }, 'k', ['a', 'b']), 'a');

  assert.throws(() => uuid('123'), /must be a uuid/);
  assert.equal(uuid('11111111-1111-1111-1111-111111111111'), '11111111-1111-1111-1111-111111111111');

  assert.throws(() => email({ email: 'nope' }), /not valid/);
  assert.equal(email({ email: ' Foo@Bar.COM ' }), 'foo@bar.com', 'emails are lowercased for the unique index');

  assert.equal(bool({ f: 'true' }, 'f'), true);
  assert.equal(bool({}, 'f', true), true);
});
