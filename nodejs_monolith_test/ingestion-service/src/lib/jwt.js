import crypto from 'crypto';
import { config } from '../config/index.js';

const b64urlDecode = (s) => Buffer.from(s, 'base64url');

// Hand-rolled HS256 verification; matches stress-test/scripts/generate-jwt.sh.
export function verifyJwt(token) {
  const [h, p, sig] = token.split('.');
  if (!h || !p || !sig) return null;

  const header = JSON.parse(b64urlDecode(h).toString('utf8'));
  if (header.alg !== 'HS256') return null;

  const expected = crypto.createHmac('sha256', config.jwtSecret).update(`${h}.${p}`).digest('base64url');
  const got = Buffer.from(sig);
  const want = Buffer.from(expected);
  if (got.length !== want.length || !crypto.timingSafeEqual(got, want)) return null;

  const claims = JSON.parse(b64urlDecode(p).toString('utf8'));
  if (claims.exp && Date.now() / 1000 > claims.exp) return null;

  return claims;
}
