// ============================================================
// SINGLE SOURCE OF TRUTH for the event payload.
// One representative event is used for every request in every
// scenario. Edit the template below to change what is sent.
//
// Uniqueness per iteration: eventId and sessionId are varied so
// downstream systems can de-duplicate / count accurately, but the
// shape and size of the payload stay constant (realistic load).
// ============================================================

const EVENT_TEMPLATE = {
  eventId: '',        // filled per-iteration
  eventType: 'game.session.heartbeat',
  timestamp: '',      // filled per-iteration (RFC3339)
  userId: 'user-loadtest-0001',
  sessionId: '',      // filled per-iteration
  gameId: 'game-prod-42',
  deviceId: 'device-lt-a1b2c3d4',
  platform: 'android',
  country: 'IN',
  appVersion: '2.14.3',
};

let seq = 0;

export function buildEvent() {
  seq += 1;
  return JSON.stringify({
    ...EVENT_TEMPLATE,
    eventId: `lt-${__VU}-${__ITER}-${Date.now()}`,
    sessionId: `sess-${__VU}-${seq % 1000}`,
    timestamp: new Date().toISOString(),
  });
}
