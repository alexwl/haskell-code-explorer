import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';

export default Ember.Component.extend({
  store : Ember.inject.service('store'),
  tagName : 'span',
  classNames: ["type-component"],
  contextMenu() {//right mouse button click to show kind of a type constructor or type variable
    if(this.get('identifiers') && this.get('internalId')) {
      this.set('expanded',true);
    }
    return false;
  },
  linkClass : Ember.computed('identifierInfo',function() {
    return this.get('identifierInfo') ? "link" : "";
  }),
  identifierInfo : Ember.computed('internalId',function() {
    return this.get('internalId') ? this.get('identifiers')[this.get('internalId')] : null;
  }),
  actions : {
    onmouseup (event) {
      if(this.get('identifierInfo') && (event.which !== 3 )) {
        const locationInfo = this.get('identifierInfo').locationInfo;
        goToDefinition(this.get('store'),locationInfo,event.which,this.get('currentLineNumber'));
        return false;
      }
    }
  }
});
