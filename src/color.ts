import { Handler } from 'aws-lambda';

export const handler: Handler = event => {
  console.log('request:', JSON.stringify(event, undefined, 2));
  return Promise.resolve({
    statusCode: 200,
    headers: { 'Content-Type': 'text/plain' },
    body: `Color ole ole ${event.path}\n`,
  });
};
