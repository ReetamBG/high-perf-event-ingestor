import { Router } from 'express';

const router = Router();

router.get('/health', (_req, res) => {
  res.status(200).send('All good');
});

export default router;
