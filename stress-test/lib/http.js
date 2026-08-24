// Shared HTTP ingestion logic.
// The load generator ONLY speaks HTTP (POST + Bearer auth).
// It knows nothing about Kafka, storage, or any backend internals.
// HTTP 202 is treated strictly as "accepted by the API", NOT as
// "persisted". Downstream delivery/persistence is verified separately
// (see README: lag inspection + storage verification).

import http from 'k6/http';
import { Counter } from 'k6/metrics';
import exec from 'k6/execution';
import { buildEvent } from './event.js';
import { targetUrl, jwtToken } from './config.js';

export const sentEvents = new Counter('events_sent');
export const acceptedEvents = new Counter('events_accepted');

// One counter per HTTP status class. k6 tags every sample with the running
// scenario name automatically, so the end-of-test summary can break these
// down per stage via sub-metrics (forced in lib/options.js).
export const STATUS_CLASSES = [
  'http_2xx',
  'http_3xx',
  'http_4xx',
  'http_5xx',
  'network_error',
];

export const statusCounters = {};
for (const cls of STATUS_CLASSES) {
  statusCounters[cls] = new Counter(cls);
}

function classify(status) {
  if (!status || status === 0) return 'network_error';
  return `http_${Math.floor(status / 100)}xx`;
}

export function sendIngest() {
  const payload = buildEvent();
  sentEvents.add(1);

  const res = http.post(targetUrl(), payload, {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${jwtToken()}`,
    },
    tags: { name: 'POST /events/ingest' },
  });

  statusCounters[classify(res.status)].add(1);

  // 2xx means the API accepted the event for async processing.
  // It says nothing about what happens downstream.
  if (res.status >= 200 && res.status < 300) {
    acceptedEvents.add(1);
  }
}

export function ingestScenario(scenarioName) {
  // k6/execution exposes the running scenario's name at iteration time,
  // letting one shared function serve every scenario/stage.
  sendIngest(scenarioName || exec.scenario.name);
}
