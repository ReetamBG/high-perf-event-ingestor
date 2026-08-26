import express from 'express';
import { jwtAuth } from '../middleware/auth.js';
import { isValidEvent } from '../utils/validate.js';
import { putEvent } from '../services/s3.js';

const router = express.Router();

router.post('/ingest', jwtAuth, async (req, res) => {
  const event = req.body;

  if (!isValidEvent(event)) {
    return res.status(400).json({ error: 'invalid request body' });
  }

  try {
    await putEvent(event);
  } catch (err) {
    console.error('S3 write failed:', err.message);
    return res.status(500).json({ error: 'internal server error' });
  }

  res.status(202).end();
});

export default router;
