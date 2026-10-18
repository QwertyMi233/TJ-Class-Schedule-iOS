const responseHeaders = {
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: responseHeaders })
}

function validCount(row) {
  return Number.isSafeInteger(row?.count) && row.count >= 0
}

export async function onRequestGet({ env }) {
  if (!env.DB) return json({ error: "统计未启用" }, 503)
  try {
    const row = await env.DB.prepare("SELECT count FROM download_counter WHERE id = 1").first()
    return validCount(row) ? json({ count: row.count }) : json({ error: "统计未初始化" }, 503)
  } catch {
    return json({ error: "统计暂不可用" }, 503)
  }
}

export async function onRequestPost({ env, request }) {
  const origin = request.headers.get("Origin")
  if (origin && origin !== new URL(request.url).origin) return json({ error: "请求来源无效" }, 403)
  if (request.headers.get("Sec-Fetch-Site") === "cross-site") return json({ error: "请求来源无效" }, 403)
  if (!env.DB) return json({ error: "统计未启用" }, 503)
  try {
    const row = await env.DB.prepare("UPDATE download_counter SET count = count + 1 WHERE id = 1 RETURNING count").first()
    return validCount(row) ? json({ count: row.count }) : json({ error: "统计未初始化" }, 503)
  } catch {
    return json({ error: "统计暂不可用" }, 503)
  }
}
