import { verifyJwt } from '../lib/jwt.js';

export function jwtAuth(req, res, next) {
  const [scheme, token] = (req.headers.authorization || '').split(' ');

  if (!token || scheme.toLowerCase() !== 'bearer') {
    return res.status(401).send('Invalid authorization format');
  }

  try {
    const claims = verifyJwt(token);
    if (!claims) return res.status(401).send('Invalid or expired token');
    req.claims = claims;
    next();
  } catch {
    res.status(401).send('Invalid or expired token');
  }
}
