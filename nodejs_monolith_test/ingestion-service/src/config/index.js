const int = (v, fallback) => parseInt(v || fallback, 10);

export const config = {
  port: int(process.env.PORT, 8080),
  jwtSecret: process.env.JWT_SECRET || '',
  s3: {
    endpoint: process.env.S3_ENDPOINT || 'http://s3-storage:8333',
    bucket: process.env.S3_BUCKET || 'my-bucket',
    region: 'us-east-1',
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || '',
  },
};
