// Burst test.
//
// Pattern: normal load -> short high-rate burst -> return to normal load,
// then observe recovery. The point of the burst is to exercise the
// backend's buffering/backpressure: during the burst the API may accept
// everything (2xx) while a backlog forms downstream. Whether that backlog
// drains (and how fast) is verified AFTER this test with the separate
// lag-inspection and storage-verification procedures in the README.

import { ingestScenario } from '../lib/http.js';
import { burstConfig } from '../lib/config.js';
import { buildOptions, arrivalRateScenario } from '../lib/options.js';
import { buildSummary, parseDurationMs } from '../lib/report.js';

const cfg = burstConfig();

const baselineMs = parseDurationMs(cfg.baselineDuration);
const burstMs = parseDurationMs(cfg.burstDuration);

export const options = buildOptions({
  baseline: arrivalRateScenario(cfg.baselineRate, cfg.baselineDuration, 0),
  burst: arrivalRateScenario(cfg.burstRate, cfg.burstDuration, baselineMs),
  recovery: arrivalRateScenario(
    cfg.baselineRate,
    cfg.recoveryDuration,
    baselineMs + burstMs
  ),
});

export default function () {
  ingestScenario();
}

export function handleSummary(data) {
  return buildSummary(
    data,
    [
      {
        name: 'baseline',
        label: `baseline ${cfg.baselineRate} eps (${cfg.baselineDuration})`,
        targetRate: cfg.baselineRate,
        durationStr: cfg.baselineDuration,
      },
      {
        name: 'burst',
        label: `BURST ${cfg.burstRate} eps (${cfg.burstDuration})`,
        targetRate: cfg.burstRate,
        durationStr: cfg.burstDuration,
      },
      {
        name: 'recovery',
        label: `recovery ${cfg.baselineRate} eps (${cfg.recoveryDuration})`,
        targetRate: cfg.baselineRate,
        durationStr: cfg.recoveryDuration,
      },
    ],
    'Burst Load Test'
  );
}
