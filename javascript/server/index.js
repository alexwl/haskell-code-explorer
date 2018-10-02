/* eslint-env node */
'use strict';

//https://discuss.emberjs.com/t/how-to-disable-http-mock-server-within-environment-config-file/6660/9

//To use http mocks from server/mocks for testing:
//ember server
//To use real server:
//ember server --proxy=http://localhost:8080/

function usingProxy() {
  return !!process.argv.filter(function (arg) {
    return arg.indexOf('--proxy') === 0;
  }).length;
}

module.exports = function(app) {
  if (usingProxy()) { return; }
  
  const globSync   = require('glob').sync;
  const mocks      = globSync('./mocks/**/*.js', { cwd: __dirname }).map(require);
  const proxies    = globSync('./proxies/**/*.js', { cwd: __dirname }).map(require);

  // Log proxy requests
  const morgan = require('morgan');
  app.use(morgan('dev'));

  mocks.forEach(route => route(app));
  proxies.forEach(route => route(app));
};
