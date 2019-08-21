import Ember from 'ember';
import {goToDefinition} from '../../utils/go-to-definition';

export default Ember.Controller.extend({
  store : Ember.inject.service('store'),
  actions : {
    goToDefinition (locationInfo,event) {
      goToDefinition(this.get('store'),
                     locationInfo,
                     event.which,
                     null);
      return false;
    }
  }
});
