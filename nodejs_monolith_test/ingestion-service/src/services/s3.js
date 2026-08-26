import crypto from 'crypto';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { config } from '../config/index.js';

const s3 = new S3Client({
  endpoint: config.s3.endpoint,
  region: config.s3.region,
  forcePathStyle: true,
  credentials: {
    accessKeyId: config.s3.accessKeyId,
    secretAccessKey: config.s3.secretAccessKey,
  },
});

// The naive part: one blocking PUT per event, no batching/compression.
// Trailing newline keeps record counting exact for the stress-test scripts.
export async function putEvent(event) {
  await s3.send(
    new PutObjectCommand({
      Bucket: config.s3.bucket,
      Key: `${crypto.randomUUID()}.json`,
      Body: JSON.stringify(event) + '\n',
      ContentType: 'application/json',
    })
  );
}
