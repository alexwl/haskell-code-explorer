import Ember from 'ember';

export default Ember.Route.extend({
  store : Ember.inject.service(),
  model : function (params) {
    const packageInfo = this.modelFor('package');    
    if(packageInfo.modules[params.filePath]) {      
      return this.get('store').loadHaskellModule(packageInfo.id,params.filePath)
        .catch((e) => {console.log(e);this.transitionTo("/not-found");});      
    } else {
      return this.get('store').loadFile(packageInfo.id,params.filePath)
        .then((result) => {          
          document.title = packageInfo.id;
          return result;
        })
        .catch((e) => {console.log(e);this.transitionTo("/not-found");});
    }
  },
  afterModel (model) {    
    document.title = model.id + " - " + this.modelFor('package').id;
  },
  actions : {
    didTransition : function () {            
      this.send("fileOpened",this.currentModel.id);    
    }    
  }
});
