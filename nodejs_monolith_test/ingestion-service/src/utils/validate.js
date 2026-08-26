export const REQUIRED_FIELDS = [
  'eventId',
  'eventType',
  'timestamp',
  'userId',
  'sessionId',
  'gameId',
  'deviceId',
  'platform',
  'country',
  'appVersion',
];

export function isValidEvent(e) {
  if (typeof e !== 'object' || e === null || Array.isArray(e)) return false;
  if (REQUIRED_FIELDS.some((f) => typeof e[f] !== 'string' || e[f].length === 0)) return false;
  return !Number.isNaN(Date.parse(e.timestamp));
}
