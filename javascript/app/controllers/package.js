import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';
export default Ember.Controller.extend({
  store : Ember.inject.service('store'),
  currentFile : null,
  loadItemsFunction : null,
  query : null,
  actions : {
    searchIdentifier (query) {
      if(query) {
        this.set('currentFile',null);
        document.title = this.get('model.id');        
        this.transitionToRoute('package.search',query);
      }
    },
    showIdentifier (identifierInfo) {
      goToDefinition(this.get('store'),
                     identifierInfo.locationInfo,
                     1,//left mouse button
                     null);
      return false;
    }
  }
});
