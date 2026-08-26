import express from 'express';
import healthRouter from './routes/health.js';
import eventsRouter from './routes/events.js';

export function createApp() {
  const app = express();

  app.use('/', healthRouter);
  app.use('/events', express.json({ limit: '64kb' }), eventsRouter);

  return app;
}
