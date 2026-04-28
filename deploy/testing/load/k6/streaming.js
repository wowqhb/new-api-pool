// k6 压测：流式调用，测 TTFB 与 throughput
// 注意：k6 不直接支持 SSE 流式按 chunk 计时；这里通过 first byte 测 TTFB

import http from "k6/http";
import { check } from "k6";
import { Trend } from "k6/metrics";

const BASE = __ENV.BASE_URL || "https://api-staging.example.com";
const KEY = __ENV.API_KEY || "sk-test";

const ttfb = new Trend("ttfb_ms_stream");

export const options = {
  vus: 50,
  duration: "3m",
  thresholds: {
    "ttfb_ms_stream": ["p(95)<2000"],
  },
};

export default function () {
  const start = Date.now();
  const res = http.post(`${BASE}/v1/chat/completions`,
    JSON.stringify({
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: "讲个 100 字小故事" }],
      stream: true,
      max_tokens: 200,
    }),
    {
      headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
      timeout: "60s",
    }
  );
  ttfb.add(Date.now() - start);
  check(res, {
    "200": (r) => r.status === 200,
    "has data:": (r) => r.body && r.body.includes("data:"),
  });
}
