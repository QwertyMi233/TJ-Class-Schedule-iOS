import assert from "node:assert/strict"
import { test } from "node:test"
import { onRequestGet, onRequestPost } from "../functions/api/download-count.js"

function fixture() {
  let count = 0
  const env = {
    DB: {
      prepare(sql) {
        return {
          async first() {
            if (sql.startsWith("UPDATE")) count += 1
            return { count }
          },
        }
      },
    },
  }
  return { env, request: new Request("https://example.com/api/download-count", { method: "POST", headers: { Origin: "https://example.com" } }) }
}

test("reads the shared count and increments it once per accepted request", async () => {
  const context = fixture()
  assert.deepEqual(await (await onRequestGet(context)).json(), { count: 0 })
  assert.deepEqual(await (await onRequestPost(context)).json(), { count: 1 })
  assert.deepEqual(await (await onRequestGet(context)).json(), { count: 1 })
})

test("rejects cross-site requests and does not increase the count", async () => {
  const context = fixture()
  const response = await onRequestPost({ ...context, request: new Request("https://example.com/api/download-count", { method: "POST", headers: { Origin: "https://other.example" } }) })
  assert.equal(response.status, 403)
  assert.deepEqual(await (await onRequestGet(context)).json(), { count: 0 })
})

test("reports an unavailable counter when the database is not bound", async () => {
  const context = fixture()
  assert.equal((await onRequestGet({ ...context, env: {} })).status, 503)
  assert.equal((await onRequestPost({ ...context, env: {} })).status, 503)
})
