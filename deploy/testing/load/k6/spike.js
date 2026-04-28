// k6 压测：尖峰（spike）— 测系统在突发流量下是否扛得住
// 用法：k6 run spike.js
// 模式：30s 100 → 10s 1000（10x） → 30s 100，看 SLO

import http from "k6/http";
import { check, sleep } from "k6";

const BASE = __ENV.BASE_URL || "https://api-staging.example.com";
const KEY = __ENV.API_KEY || "sk-test";

export const options = {
  stages: [
    { duration: "30s", target: 100 },
    { duration: "10s", target: 1000 },  // 尖峰
    { duration: "30s", target: 100 },
    { duration: "10s", target: 0 },
  ],
  thresholds: {
    "http_req_duration": ["p(99)<15000"],  // 尖峰下 p99 < 15s
    "http_req_failed": ["rate<0.10"],      // 失败率 < 10%（容忍）
  },
};

export default function () {
  const res = http.post(`${BASE}/v1/chat/completions`,
    JSON.stringify({
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: "hi" }],
      max_tokens: 20,
    }),
    {
      headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
      timeout: "20s",
    }
  );
  check(res, { "ok": (r) => r.status === 200 || r.status === 429 });
  sleep(0.5);
}
