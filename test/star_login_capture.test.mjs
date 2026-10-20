import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../lib/import/star_login_capture.dart', import.meta.url), 'utf8');
const script = source.match(/const starCredentialCaptureScript = r'''([\s\S]*?)''';/)[1];
const origin = 'https://star.tongji.edu.cn';
const access = 'fixture-access-token';
const refresh = 'fixture-refresh-token';
const key = 'TONGJI_EXCELLENCE_STAR_APP__PRODUCTION__1.0.0__COMMON__LOCAL__KEY__';
const fixture = JSON.parse(readFileSync(new URL('./fixtures/star-login-cache.json', import.meta.url), 'utf8'));
const record = (value) => ({ value, time: Date.now() + 60000 });
const cache = (value, expire = Date.now() + 60000) => JSON.stringify({ value, expire });

function read(entries, currentOrigin = origin, reads = []) {
  const store = new Map(Object.entries(entries));
  const localStorage = {
    get length() { return store.size; },
    key: (i) => [...store.keys()][i],
    getItem: (key) => { reads.push(key); return store.get(key) ?? null; },
  };
  const result = runInNewContext(script, { location: { origin: currentOrigin }, localStorage });
  return result ? JSON.parse(result) : null;
}

test('保留官网加密快照及明文格式，交给本机解码', () => {
  for (const stored of [fixture.encrypted, JSON.stringify(fixture.valid)]) {
    assert.deepEqual(read({ [key]: stored }), { origin, snapshots: [stored] });
  }
});

test('统一认证页及相似域名不能读取登录态', () => {
  for (const current of ['https://iam.tongji.edu.cn', 'http://star.tongji.edu.cn',
    'https://star.tongji.edu.cn.example.org']) {
    assert.equal(read({ [key]: cache({ ACCESS_TOKEN__: record(access),
      REFRESH_TOKEN__: record(refresh) }) }, current), null);
  }
});

test('空值和超大缓存不传递，损坏或过期快照由解码层判断', () => {
  for (const stored of ['', 'x'.repeat(2 * 1024 * 1024 + 1)]) {
    assert.equal(read({ [key]: stored }), null);
  }
  for (const stored of ['broken-json', fixture.expiredEncrypted]) {
    assert.deepEqual(read({ [key]: stored }), { origin, snapshots: [stored] });
  }
});

test('不拼接不同缓存中的 access 和 refresh，不扫描其他站点缓存', () => {
  const first = cache({ ACCESS_TOKEN__: record(access) });
  const second = cache({ REFRESH_TOKEN__: record(refresh) });
  const reads = [];
  assert.deepEqual(read({
    [key]: first,
    [key.replace('1.0.0', '2.0.0')]: second,
    unrelated: JSON.stringify({ accessToken: access, refreshToken: refresh }),
  }, origin, reads), { origin, snapshots: [first, second] });
  assert.deepEqual(reads, [key, key.replace('1.0.0', '2.0.0')]);
});

test('缓存键的版本变化不影响读取，存储被禁用时返回空结果', () => {
  assert.equal(read({ [key.replace('1.0.0', '2.0.0')]: fixture.encrypted })
    .snapshots[0], fixture.encrypted);
  assert.equal(runInNewContext(script, { location: { origin },
    get localStorage() { throw new Error('storage disabled'); } }), '');
});
