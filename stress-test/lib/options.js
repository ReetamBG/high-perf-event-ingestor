// Builds k6 options shared by all scenarios.
//
// Per-scenario thresholds with generous bounds are declared up front purely
// so k6 emits per-scenario sub-metrics (request counts, failure rate, status
// class counts) in the end-of-test summary data. Real "pass/fail" flagging
// happens in lib/report.js based on configurable thresholds, so the run never
// aborts because of these bounds.
//
// summaryTrendStats makes p(99) available for every duration metric, which
// k6 does not include by default.

import { jwtToken, maxVUs } from './config.js';
import { STATUS_CLASSES } from './http.js';

export function vuBudget(rate) {
  // Enough VUs to sustain `rate` eps assuming single-digit-ms latency,
  // capped by MAX_VUS. Tune MAX_VUS if the server slows down badly.
  return Math.max(10, Math.min(maxVUs(), Math.ceil(rate / 20) + 10));
}

export function arrivalRateScenario(rate, durationStr, startTimeMs, extra = {}) {
  return {
    executor: 'constant-arrival-rate',
    rate,
    timeUnit: '1s',
    duration: durationStr,
    startTime: `${startTimeMs}ms`,
    preAllocatedVUs: vuBudget(rate),
    gracefulStop: '0s',
    ...extra,
  };
}

const BIG = 'count<1000000000';

export function buildOptions(scenarios) {
  if (!jwtToken()) {
    throw new Error(
      'JWT_TOKEN env var is required (generate one with scripts/generate-jwt.sh).'
    );
  }
  const thresholds = {};
  for (const name of Object.keys(scenarios)) {
    thresholds[`http_reqs{scenario:${name}}`] = [BIG];
    thresholds[`http_req_failed{scenario:${name}}`] = ['rate<1.01'];
    // Forcing these thresholds makes k6 emit the per-scenario duration
    // trend (avg/p95/p99) in end-of-test summary data.
    thresholds[`http_req_duration{scenario:${name}}`] = [
      'p(95)<600000',
      'p(99)<600000',
    ];
    for (const cls of STATUS_CLASSES) {
      thresholds[`${cls}{scenario:${name}}`] = [BIG];
    }
  }
  return {
    scenarios,
    thresholds,
    summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  };
}
