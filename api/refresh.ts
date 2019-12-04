import { NowRequest, NowResponse } from '@now/node';
import log from 'loglevel';
import * as Sentry from '@sentry/node';
import { MongoClient } from 'mongodb';
import got from 'got';
import { getConfig } from './_shared/config';
import { initSentry } from './_shared/sentry';
import { connect } from './_shared/mongodb';
import { allRepositories } from './_refresh/mongodb';
import { getRepositoriesStatus } from './_shared/repositories';
import { callIftttWebhook } from './_shared/ifttt';

log.enableAll();

export default async function refresh(_req: NowRequest, res: NowResponse) {
  const config = getConfig();
  initSentry(Sentry, config, log);
  let mongoClient: MongoClient | undefined;
  try {
    mongoClient = await connect(MongoClient, config.mongoDbUri);
    const repositories = await allRepositories(mongoClient);
    const overallStatus = getRepositoriesStatus(repositories);
    log.info(`Calling IFTTT webhook with "${overallStatus}" status`);
    const hookResponse = await callIftttWebhook(overallStatus, config, got);
    log.info(hookResponse);
    res.statusCode = 200;
    res.send(hookResponse);
  } catch (e) {
    Sentry.captureException(e);
  } finally {
    if (mongoClient) {
      mongoClient.close();
    }
  }
}