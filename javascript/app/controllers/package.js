import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';
import {urls} from '../utils/api-urls';

export default Ember.Controller.extend({
  store : Ember.inject.service('store'),
  currentFile : null,
  loadItemsFunction : null,
  query : null,
  searchMode : "currentPackage",
  createSearchUrlFunction : Ember.computed("searchMode","model",function() {    
    const packageId = this.get('model.id');    
    if(this.get('searchMode') === "currentPackage") {
      return (query) => urls.identifierSearchUrl(packageId,query);
    } else {
      return (query) => urls.globalIdentifiersUrl(query);
    }
  }),
  actions : {
    searchIdentifier (query) {
      if(query) {
        this.set('currentFile',null);
        document.title = this.get('model.id');
        if(this.get('searchMode') === "currentPackage") {
          this.transitionToRoute('package.search',query);
        } else {
          this.transitionToRoute('search',query);
        }
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
