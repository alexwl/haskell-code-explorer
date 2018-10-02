import Ember from 'ember';
export default Ember.Controller.extend({
  modulesFiltered : Ember.computed('model','query',function () {
    const query = this.get('query');
    const modules = Object.keys(this.get('model.modules')).sort();    
    if(query) {
      const regExp = new RegExp(query,"i");
      return modules.filter((p) => p.search(regExp) != -1);
    } else {
      return modules;
    }
  })
});

