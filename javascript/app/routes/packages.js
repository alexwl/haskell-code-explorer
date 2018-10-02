import Ember from 'ember';
import {urls} from '../utils/api-urls';
import config from '../config/environment';

export default Ember.Route.extend({
  model () {
    return Ember.$.getJSON(urls.packagesUrl);
  },
  setupController(controller, model) {
    this._super(controller, model);
    controller.set('packages',model);
  },
  afterModel () {
    document.title = config.APP.title;
  }
});
