/* eslint-env node */
'use strict';

const EmberApp = require('ember-cli/lib/broccoli/ember-app');

module.exports = function(defaults) {
  let app = new EmberApp(defaults, {
    'ember-cli-bootstrap-4': {
      js: null
    },
    'ember-cli-babel': {
      includePolyfill: true
    }
  });
  app.import('vendor/jquery-ui-1.12.1.custom/jquery-ui.min.js')// only draggable and resizable    
  app.import('vendor/jquery-ui-1.12.1.custom/jquery-ui.structure.min.css')
  app.import('node_modules/jstree/dist/jstree.min.js');
  app.import('node_modules/jstree/dist/themes/default/style.min.css');
  app.import('node_modules/showdown/dist/showdown.min.js');
  return app.toTree();
};
