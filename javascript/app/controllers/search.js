import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';

export default Ember.Controller.extend({
  store : Ember.inject.service('store'),
  actions : {
    goToDefinition (locationInfo,event) {      
      goToDefinition(this.get('store'),
                     locationInfo,
                     event.which,
                     null);
      return false;
    },
    searchIdentifier (query) {
      if(query) {
        document.title = "Haskell code explorer";
        this.transitionToRoute('search',query);
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
