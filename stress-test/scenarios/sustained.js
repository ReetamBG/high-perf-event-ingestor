// Sustained constant-rate test.
// Measures baseline throughput and latency at a single load level.

import { sendIngest } from '../lib/http.js';
import { sustainedConfig } from '../lib/config.js';
import { buildOptions, arrivalRateScenario } from '../lib/options.js';
import { buildSummary } from '../lib/report.js';

const cfg = sustainedConfig();

export const options = buildOptions({
  load: arrivalRateScenario(cfg.rate, cfg.duration, 0),
});

export default function () {
  sendIngest();
}

export function handleSummary(data) {
  return buildSummary(
    data,
    [{ name: 'load', label: 'sustained', targetRate: cfg.rate, durationStr: cfg.duration }],
    'Sustained Load Test'
  );
}
