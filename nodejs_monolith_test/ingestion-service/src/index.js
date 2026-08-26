import { config } from './config/index.js';
import { createApp } from './app.js';

const app = createApp();

app.listen(config.port, () => {
  console.log(`naive node ingestor listening on :${config.port}`);
});
