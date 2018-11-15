import Ember from 'ember';
export default Ember.Controller.extend({
  settings : Ember.inject.service('settings'),
  actions : {
    findReferences(packageId,externalId,occName,locationInfo) {
      this.send('updateReferences',packageId,externalId,occName,locationInfo);
    }
  }
});
