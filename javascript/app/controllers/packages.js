import Ember from 'ember';
export default Ember.Controller.extend({  
  queryObserver : Ember.observer("query",function() {    
    Ember.run.debounce(this, () => {
      const regExp = new RegExp(this.get('query'),"i");
      const packages = this.get('model').filter((p) => p.name.search(regExp) != -1);      
      Ember.run.next(() => {
        this.set('packages',packages);
      });
    }, 300);
  })
});
