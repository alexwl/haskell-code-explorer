import Ember from 'ember';
export default Ember.Component.extend({
  tagName : "span",
  expandTypeSynonyms: false,
  expandTypeSynonymsLabel : Ember.computed('expandTypeSynonyms',function() {
    return this.get('expandTypeSynonyms') ? "Show type synonyms" : "Expand type synonyms";
  }),
  components : Ember.computed('type','expandTypeSynonyms',function() {
    if(this.get('expandTypeSynonyms') && this.get('type.componentsExpanded')) {
      return this.get('type.componentsExpanded');
    } else {
      return this.get('type.components');
    }
  }),
  typeObserver : Ember.observer('type',function() {
    this.set('expandTypeSynonyms',false);
  }),
  actions : {
    toggleExpandTypeSynonyms () {
      this.toggleProperty('expandTypeSynonyms');
    }
  }
});
