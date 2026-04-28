// k6 压测：模拟用户调用 chat completions
// 用法：
//   k6 run --vus 100 --duration 5m chat-completions.js
//   k6 run --vus 200 --duration 10m chat-completions.js  // 高负载
//   k6 run -e BASE_URL=https://api.example.com -e API_KEY=sk-xxx chat-completions.js

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const BASE = __ENV.BASE_URL || "https://api-staging.example.com";
const KEY = __ENV.API_KEY || "sk-test-token-must-set";
const MODEL = __ENV.MODEL || "gpt-4o-mini";

const errorRate = new Rate("errors");
const ttfbTrend = new Trend("ttfb_ms");
const totalTrend = new Trend("total_ms");

export const options = {
  scenarios: {
    constant_load: {
      executor: "constant-vus",
      vus: 100,
      duration: "5m",
    },
  },
  thresholds: {
    "http_req_duration": ["p(95)<5000", "p(99)<10000"],
    "errors": ["rate<0.02"], // 错误率 < 2%
    "http_req_failed": ["rate<0.02"],
  },
};

const PROMPTS = [
  "Hello, how are you?",
  "What is the capital of France?",
  "Explain RAG in one sentence.",
  "Write a haiku about coding.",
  "Translate '你好' to English.",
  "What is 17 * 23?",
];

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];
  const payload = JSON.stringify({
    model: MODEL,
    messages: [{ role: "user", content: prompt }],
    max_tokens: 50,
    temperature: 0.5,
  });

  const params = {
    headers: {
      Authorization: `Bearer ${KEY}`,
      "Content-Type": "application/json",
    },
    timeout: "30s",
  };

  const start = Date.now();
  const res = http.post(`${BASE}/v1/chat/completions`, payload, params);
  totalTrend.add(Date.now() - start);

  const ok = check(res, {
    "status is 200": (r) => r.status === 200,
    "has content": (r) => {
      try {
        const j = r.json();
        return j.choices && j.choices[0].message.content;
      } catch (e) {
        return false;
      }
    },
  });

  errorRate.add(!ok);

  // 模拟用户思考时间
  sleep(Math.random() * 2 + 1);
}

export function handleSummary(data) {
  return {
    stdout: textSummary(data),
    "report.json": JSON.stringify(data, null, 2),
    "report.html": htmlReport(data),
  };
}

// 简洁文本摘要（无依赖）
function textSummary(data) {
  const m = data.metrics;
  return `
========================================
压测结果 (${data.state.testRunDurationMs}ms)
========================================
请求数：${m.http_reqs.values.count}
RPS：${m.http_reqs.values.rate.toFixed(2)}
失败率：${(m.http_req_failed.values.rate * 100).toFixed(2)}%
延迟 p50：${m.http_req_duration.values["p(50)"].toFixed(0)}ms
延迟 p95：${m.http_req_duration.values["p(95)"].toFixed(0)}ms
延迟 p99：${m.http_req_duration.values["p(99)"].toFixed(0)}ms
========================================
`;
}

function htmlReport(_data) {
  return "<html><body><h1>报告见 report.json</h1></body></html>";
}
