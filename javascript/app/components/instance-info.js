import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';

export default Ember.Component.extend({
  store : Ember.inject.service('store'),
  style : Ember.computed('nestedLevel',function() {
    return new Ember.String.htmlSafe("margin-left :" + this.get('nestedLevel') * 10 + "px");
  }),
  nextNestedLevel : Ember.computed('nestedLevel',function () {
    return this.get('nestedLevel') + 1;
  }),
  actions : {
    goToDefinition (event) {      
      goToDefinition(this.get('store'),
                     this.get('instance.location'),
                     event.which,
                     this.get('currentLineNumber'));
      return false;
    }
  }
});
