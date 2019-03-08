import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';

export default Ember.Controller.extend({
  store : Ember.inject.service('store'),
  queryObserver : Ember.observer("query",function() {    
    Ember.run.debounce(this, () => {
      const regExp = new RegExp(this.get('query'),"i");
      const packages = this.get('model').filter((p) => p.name.search(regExp) != -1);      
      Ember.run.next(() => {
        this.set('packages',packages);
      });
    }, 300);
  }),
  actions: {
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
