// Summary/report builder.
// Produces:
//   1. A human-readable markdown table on stdout (per stage: achieved
//      throughput, p95, p99, error rate, flags).
//   2. A structured JSON file under results/ with the same data, laid out
//      so a Prometheus/Grafana exporter can consume it later without
//      restructuring anything.

import { flagThresholds } from './config.js';
import { STATUS_CLASSES } from './http.js';

export function parseDurationMs(d) {
  const m = String(d).trim().match(/^(\d+(?:\.\d+)?)(ms|s|m|h)$/);
  if (!m) throw new Error(`invalid duration: ${d}`);
  const mult = { ms: 1, s: 1000, m: 60000, h: 3600000 }[m[2]];
  return parseFloat(m[1]) * mult;
}

function fmt(n, digits = 0) {
  return n === undefined || n === null ? 'n/a' : Number(n).toFixed(digits);
}

function round(v, d) {
  return v === undefined || v === null ? null : Number(Number(v).toFixed(d));
}

function statusDist(data, name) {
  const out = {};
  for (const cls of STATUS_CLASSES) {
    const m = data.metrics[`${cls}{scenario:${name}}`];
    if (m && m.values.count > 0) out[cls] = m.values.count;
  }
  return out;
}

// meta: [{ name, label, targetRate, durationStr }]
export function buildSummary(data, meta, title) {
  const th = flagThresholds();
  const stamp = new Date().toISOString();

  let firstP99 = null;
  const stages = [];

  for (const m of meta) {
    const reqs = data.metrics[`http_reqs{scenario:${m.name}}`];
    const dur = data.metrics[`http_req_duration{scenario:${m.name}}`];
    const fail = data.metrics[`http_req_failed{scenario:${m.name}}`];

    if (!reqs) continue; // scenario produced no samples

    const count = reqs.values.count;
    const wallSec = parseDurationMs(m.durationStr) / 1000;
    const achieved = count / wallSec;
    const errorRatePct = fail ? fail.values.rate * 100 : 100;
    const p95 = dur ? dur.values['p(95)'] : undefined;
    const p99 = dur ? dur.values['p(99)'] : undefined;
    if (firstP99 === null && p99 !== undefined && p99 > 0) firstP99 = p99;

    const flags = [];
    if (achieved < m.targetRate * th.throughputTolerance) {
      flags.push(
        `throughput shortfall (achieved ${fmt(achieved)} < ${fmt(m.targetRate * th.throughputTolerance)} eps)`
      );
    }
    if (errorRatePct > th.errorRatePct) {
      flags.push(`error rate ${fmt(errorRatePct, 2)}% > ${th.errorRatePct}%`);
    }
    if (firstP99 && p99 !== undefined && p99 > firstP99 * th.p99SpikeFactor) {
      flags.push(
        `latency instability (p99 ${fmt(p99)}ms > ${th.p99SpikeFactor}x baseline ${fmt(firstP99)}ms)`
      );
    }

    stages.push({
      stage: m.label,
      target_rate_eps: m.targetRate,
      achieved_throughput_eps: round(achieved, 1),
      total_requests: count,
      avg_latency_ms: round(dur ? dur.values.avg : undefined, 2),
      p95_latency_ms: round(p95, 2),
      p99_latency_ms: round(p99, 2),
      max_latency_ms: round(dur ? dur.values.max : undefined, 2),
      error_rate_pct: round(errorRatePct, 3),
      status_distribution: statusDist(data, m.name),
      flags,
    });
  }

  const report = {
    test: title,
    generated_at: stamp,
    target_url: __ENV.TARGET_URL || 'http://localhost:8080/events/ingest',
    counters: {
      events_sent: data.metrics.events_sent ? data.metrics.events_sent.values.count : 0,
      events_accepted_http_2xx: data.metrics.events_accepted
        ? data.metrics.events_accepted.values.count
        : 0,
      total_http_requests: data.metrics.http_reqs ? data.metrics.http_reqs.values.count : 0,
      status_distribution_total: STATUS_CLASSES.reduce((acc, cls) => {
        const m = data.metrics[cls];
        if (m && m.values.count > 0) acc[cls] = m.values.count;
        return acc;
      }, {}),
    },
    note:
      'events_accepted counts HTTP 2xx only (API-level acceptance for async processing). ' +
      'Downstream delivery and persistence must be verified externally: consumer-lag drain + storage object delta.',
    stages,
  };

  // ---- stdout (markdown) ----
  let out = `\n## ${title}\n\n`;
  out += `Target: ${report.target_url} | Generated: ${stamp}\n\n`;
  out += `| Stage | Target eps | Achieved eps | Reqs | avg ms | p95 ms | p99 ms | Err % | Statuses | Flags |\n`;
  out += `|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const s of stages) {
    const statStr =
      Object.entries(s.status_distribution)
        .map(([k, v]) => `${k}:${v}`)
        .join(' ') || '-';
    out += `| ${s.stage} | ${s.target_rate_eps} | ${s.achieved_throughput_eps} | ${s.total_requests} | ${fmt(s.avg_latency_ms, 1)} | ${fmt(s.p95_latency_ms, 1)} | ${fmt(s.p99_latency_ms, 1)} | ${fmt(s.error_rate_pct, 2)} | ${statStr} | ${s.flags.length ? 'FLAGGED: ' + s.flags.join('; ') : 'OK'} |\n`;
  }
  out += `\nCounters: sent=${report.counters.events_sent}, accepted(2xx)=${report.counters.events_accepted_http_2xx}, http_reqs=${report.counters.total_http_requests}\n`;
  out += `Reminder: HTTP 2xx != persisted. Verify downstream drained (lag ~0) and check the storage object delta after the run.\n`;

  const fileBase = title.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '-' + Date.now();
  return {
    stdout: out,
    [`results/${fileBase}.json`]: JSON.stringify(report, null, 2),
  };
}
