// Central configuration for all stress-test scenarios.
// Everything is driven by environment variables with sensible defaults,
// so the same scripts work against any HTTP endpoint without code changes.

function env(name, fallback) {
  const v = __ENV[name];
  return v !== undefined && v !== '' ? v : fallback;
}

export function targetUrl() {
  return env('TARGET_URL', 'http://localhost:8080/events/ingest');
}

export function jwtToken() {
  return env('JWT_TOKEN', '');
}

export function maxVUs() {
  return parseInt(env('MAX_VUS', '500'), 10);
}

export function stages() {
  // Format: "rate:duration,rate:duration,..." e.g. "1000:30s,5000:30s"
  const raw = env(
    'STAGES',
    '1000:30s,5000:30s,10000:30s,15000:30s,20000:30s'
  );
  return raw.split(',').map((s) => s.trim()).filter(Boolean).map((part) => {
    const [rate, duration] = part.split(':');
    return { rate: parseInt(rate, 10), duration };
  });
}

export function sustainedConfig() {
  return {
    rate: parseInt(env('RATE', '1000'), 10),
    duration: env('DURATION', '60s'),
  };
}

export function burstConfig() {
  return {
    baselineRate: parseInt(env('BASELINE_RATE', '1000'), 10),
    baselineDuration: env('BASELINE_DURATION', '30s'),
    burstRate: parseInt(env('BURST_RATE', '20000'), 10),
    burstDuration: env('BURST_DURATION', '10s'),
    recoveryDuration: env('RECOVERY_DURATION', '60s'),
  };
}

// Thresholds used to flag unstable stages in the progressive test.
export function flagThresholds() {
  return {
    errorRatePct: parseFloat(env('ERROR_RATE_THRESHOLD', '1')),
    p99SpikeFactor: parseFloat(env('P99_SPIKE_FACTOR', '2')),
    throughputTolerance: parseFloat(env('THROUGHPUT_TOLERANCE', '0.95')),
  };
}
