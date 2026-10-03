import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
const source = readFileSync(new URL('../web/app_loader.js', import.meta.url), 'utf8');
function setup() {
  const events = {}, elements = {}, timers = [];
  for (const id of ['app-loading', 'loading-message', 'loading-retry']) {
    elements[id] = {hidden: true, addEventListener(name, fn) {this[name] = fn;}, remove() {this.removed = true;}};
  }
  const context = {
    document: {getElementById: (id) => elements[id]},
    window: {addEventListener: (name, fn) => events[name] = fn, isSecureContext: false},
    navigator: {onLine: true}, location: {reload() {}},
    setTimeout: (fn) => timers.push(fn), clearTimeout() {},
  };
  runInNewContext(source, context);
  return {events, elements, timers, context};
}
test('slow or failed startup offers an actionable retry', () => {
  const {timers, elements} = setup();
  timers[0]();
  assert.equal(elements['loading-retry'].hidden, false);
  assert.match(elements['loading-message'].textContent, /أعد المحاولة/);
});
test('first frame removes loading UI; later errors never cover the app', () => {
  const {events, elements, timers} = setup();
  events['flutter-first-frame']();
  timers[0]();
  assert.equal(elements['app-loading'].removed, true);
  assert.equal(elements['loading-retry'].hidden, true);
});
test('offline startup explains the connection problem', () => {
  const {events, context, elements} = setup();
  context.navigator.onLine = false;
  events.offline();
  assert.match(elements['loading-message'].textContent, /لا يوجد اتصال/);
});
test('notification clicks remain on our origin and reject untrusted identifiers', async () => {
  const events = {}, opened = [];
  runInNewContext(readFileSync(new URL('../web/firebase-messaging-sw.js', import.meta.url), 'utf8'), {
    self: {addEventListener: (name, fn) => events[name] = fn,
      location: {origin: 'https://ejarz-pro-20260624.web.app'},
      clients: {openWindow: (url) => {opened.push(url); return Promise.resolve();}}},
    importScripts() {}, firebase: {initializeApp() {}, messaging() {}}, URL,
  });
  events.notificationclick({notification: {close() {}, data: {FCM_MSG: {data: {contractId: 'https://evil.example/', notificationId: 'valid-id'}}}},
    stopImmediatePropagation() {}, waitUntil() {}});
  const url = new URL(opened[0]);
  assert.equal(url.origin, 'https://ejarz-pro-20260624.web.app');
  assert.equal(url.searchParams.get('contractId'), null);
  assert.equal(url.searchParams.get('notificationId'), 'valid-id');
});
