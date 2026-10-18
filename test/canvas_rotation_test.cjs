const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/../packages/canvas_session_bridge/android/src/main/assets/canvas_rotation.js', 'utf8');
const browser = vm.createContext({URL, module: {exports: {}}});
// 模拟学校 DateJS 覆盖原生 Date.parse 的行为。
vm.runInContext('Date.parse = value => { const date = new Date(value); return Number.isFinite(date.getTime()) ? date : null; }', browser);
vm.runInContext(source, browser);
const {run, listTokens} = browser.module.exports;
const ORIGIN = 'https://canvas.tongji.edu.cn';
const now = new Date('2026-10-17T10:00:00Z').getTime();
const fresh = 'b'.repeat(64);
const old = 'a'.repeat(64);
function fixture(options = {}) {
  const calls = [], events = [];
  const meta = {id: 7, user_id: 42, purpose: 'dedicated', workflow_state: 'active', scopes: [],
    expires_at: '2026-10-17T10:20:00.123Z', permanent_expires_at: null, ...options.meta};
  const config = {tokenId: '7', accountId: '42', purpose: 'dedicated', currentToken: old, credentialsOnly: true};
  const response = (data, status = 200) => ({ok: status === 200, status, json: async () => data,
    headers: {get: name => name.toLowerCase() === 'www-authenticate' && status === 401 ? 'Bearer' : null}});
  const io = {origin: ORIGIN, now: () => now, csrf: () => 'csrf',
    tokenLinks: () => ['/profile/tokens/7', ORIGIN + '/profile/tokens/7', 'https://other.example/profile/tokens/8', '/profile/tokens/8/extra'],
    saveCandidate: async record => { events.push('save'); assert.equal(record.token, fresh); },
    commitVerified: async () => events.push('verified'),
    fetch: async (url, init) => {
      calls.push({url, init});
      if (init.method === 'PUT') return response({...meta, visible_token: fresh, ...options.rotation});
      if (url.endsWith('/profile/tokens/7')) return response({...meta, visible_token: fresh});
      if (url.endsWith('/api/v1/users/self/profile')) {
        const auth = init.headers?.Authorization;
        if (auth === 'Bearer ' + fresh && options.newFailure) return response({}, 503);
        if (auth === 'Bearer ' + old && events.includes('save')) return response({}, 401);
        return response({id: !auth && options.cookieAccount ? options.cookieAccount : 42});
      }
      throw new Error('Unexpected request');
    }};
  return {io, config, calls, events};
}
test('Date.parse被覆盖时仍在到期前轮换，安全保存先于验证，结果不含凭证', async () => {
  const f = fixture(); const result = await run(f.io, f.config);
  assert.equal(result.rotated, true); assert.equal(result.oldStatus, 401);
  assert.deepEqual(f.events, ['save', 'verified']);
  assert.ok(!JSON.stringify(result).includes(fresh));
  assert.ok(!f.calls.some(c => c.url.includes('/courses')));
  assert.ok(f.calls.filter(c => c.init.headers?.Authorization).every(c => c.init.credentials === 'omit'));
});
test('健康凭证只验证，不重复生成', async () => {
  const f = fixture({meta: {expires_at: '2026-10-17T12:00:00Z'}});
  assert.equal((await run(f.io, f.config)).rotated, false);
  assert.ok(!f.calls.some(c => c.init.method === 'PUT'));
});
test('候选验证503仍先保存，不激活或重复生成', async () => {
  const f = fixture({newFailure: true});
  await assert.rejects(run(f.io, f.config), {code: 'http_503'});
  assert.deepEqual(f.events, ['save']);
  assert.equal(f.calls.filter(c => c.init.method === 'PUT').length, 1);
});
test('权限扩大拒绝激活候选', async () => {
  const f = fixture({rotation: {scopes: ['expanded']}});
  await assert.rejects(run(f.io, f.config), {code: 'rotation_identity_or_scope_changed'});
  assert.deepEqual(f.events, ['save']);
});
test('永久期限届满或坏日期不轮换', async () => {
  for (const meta of [{permanent_expires_at: '2026-10-16T00:00:00Z'}, {expires_at: ''}]) {
    const f = fixture({meta}); await assert.rejects(run(f.io, f.config));
    assert.ok(!f.calls.some(c => c.init.method === 'PUT'));
  }
});
test('Cookie账号变化不修改任何令牌', async () => {
  const f = fixture({cookieAccount: 99});
  await assert.rejects(run(f.io, f.config), {code: 'account_changed'});
  assert.ok(!f.calls.some(c => c.init.method === 'PUT'));
});
test('清单仅读取同源指定令牌，不返回完整凭证、不提交变更', async () => {
  const f = fixture(); const result = await listTokens(f.io);
  assert.equal(JSON.stringify(result), JSON.stringify({status: 'ok', accountId: '42', tokens: [{id: '7', purpose: 'dedicated'}]}));
  assert.equal(f.calls.length, 2);
  assert.ok(f.calls.every(c => c.url.startsWith(ORIGIN) && !c.init.method));
});
test('清单账号不符中止；外域页面不发请求', async () => {
  const f = fixture({meta: {user_id: 99}});
  await assert.rejects(listTokens(f.io), {code: 'account_changed'});
  f.io.origin = 'https://iam.tongji.edu.cn'; f.calls.length = 0;
  await assert.rejects(listTokens(f.io), {code: 'login_required'});
  assert.equal(f.calls.length, 0);
});
test('真实页面适配器从rel属性读取详情地址，发回桥接内容无完整Token', async () => {
  const f = fixture(); const messages = [];
  const page = vm.createContext({URL, location: {origin: ORIGIN}, fetch: f.io.fetch,
    document: {querySelectorAll: selector => {
      assert.equal(selector, '.access_token .show_token_link');
      return [{getAttribute: name => name === 'rel' ? '/profile/tokens/7' : '#'}];
    }}, CanvasLab: {postMessage: text => messages.push(JSON.parse(text))}});
  vm.runInContext(source, page);
  page.CanvasRotation.startList({nonce: 'test-placeholder'});
  for (let i = 0; !messages.length && i < 20; i++) await new Promise(resolve => setImmediate(resolve));
  assert.equal(messages[0].result.status, 'ok');
  assert.equal(messages[0].result.tokens[0].id, '7');
  assert.ok(!JSON.stringify(messages).includes(fresh));
});
