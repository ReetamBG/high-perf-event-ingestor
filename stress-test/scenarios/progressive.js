// Progressive (staged) load test.
// Ramps through configurable stages, e.g. 1k -> 5k -> 10k -> 15k -> 20k eps.
// Each stage is its own k6 scenario so per-stage throughput, p95, p99 and
// error rate are reported separately. Stages that cannot sustain the target
// rate, show elevated errors, or unstable latency are flagged in the summary
// (the run itself keeps going so you get the full picture).

import { ingestScenario } from '../lib/http.js';
import { stages } from '../lib/config.js';
import { buildOptions, arrivalRateScenario } from '../lib/options.js';
import { buildSummary } from '../lib/report.js';

const cfg = stages();

const scenarioDefs = {};
let offset = 0;
cfg.forEach((s, i) => {
  const name = `stage-${i + 1}`;
  scenarioDefs[name] = arrivalRateScenario(s.rate, s.duration, offset);
  offset += ms(s.duration);
});

function ms(d) {
  const m = String(d).trim().match(/^(\d+(?:\.\d+)?)(ms|s|m|h)$/);
  if (!m) throw new Error(`invalid duration: ${d}`);
  return parseFloat(m[1]) * { ms: 1, s: 1000, m: 60000, h: 3600000 }[m[2]];
}

export const options = buildOptions(scenarioDefs);

export default function () {
  ingestScenario();
}

export function handleSummary(data) {
  const meta = cfg.map((s, i) => ({
    name: `stage-${i + 1}`,
    label: `${s.rate} eps (${s.duration})`,
    targetRate: s.rate,
    durationStr: s.duration,
  }));
  return buildSummary(data, meta, 'Progressive Load Test');
}
