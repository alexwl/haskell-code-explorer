import Ember from 'ember';

export default Ember.Route.extend({
  afterModel : function (model,transition) {
    transition.send("fileOpened",null);
  }
});
