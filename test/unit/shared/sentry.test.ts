import { expect } from 'chai';
import sinon from 'sinon';
import * as Sentry from '@sentry/node';
import { Logger } from 'loglevel';
import { initSentry } from '../../../api/shared/sentry';
import { Config } from '../../../api/shared/config';

suite('sentry', function() {
  test('init sentry instance', function() {
    const init = sinon.fake();
    const sentry: Partial<typeof Sentry> = {
      init,
    };
    const config: Partial<Config> = {
      sentryDSN: 'https://123@sentry.io/456',
    };
    const logger: Partial<Logger> = {
      error: sinon.fake(),
    };
    initSentry(sentry as typeof Sentry, config as Config, logger as Logger);
    expect(init).to.have.been.calledWith({ dsn: 'https://123@sentry.io/456' });
  });
});
