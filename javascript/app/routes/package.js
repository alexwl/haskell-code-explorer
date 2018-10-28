import Ember from 'ember';
import {urls} from '../utils/api-urls';

export default Ember.Route.extend({
  store : Ember.inject.service('store'),
  model (params) {    
    return this.get('store').loadPackage(params.packageId)
      .catch((e) => {console.log(e);this.transitionTo("/package-not-found");});
  },
  setupController(controller, model) {
    this._super(controller, model);
    const packageId = this.modelFor('package').id;
    controller.set('bottomPanelVisible',false);
    controller.set('createSearchUrlFunction',(query) => {
      return urls.identifierSearchUrl(packageId,query);
    });
  },  
  actions : {
    openFile  (filePath) {
      this.transitionTo('package.show.file',filePath);
    },
    fileOpened (filePath) {
      if(this.get('controller')) {
        this.set('controller.currentFile',filePath);
      }
    },
    updateReferences(packageId,externalId,occName) {
      this.set('controller.packageId',packageId);
      this.set('controller.externalId',externalId);
      this.set('controller.occName',occName);
      this.set('controller.bottomPanelVisible',true);
      this.set('controller.referencesUrl',urls.referencesUrl(packageId,externalId)+"?per_page=50");
    },
    didTransition() {
      document.title = this.currentModel.id;
      return true;
    }
  }
});
