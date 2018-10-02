import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';

export default Ember.Component.extend({  
  store : Ember.inject.service('store'),
  downloadedDocumentation : null,
  didInsertElement () {
    const onmouseup = (event) => {
      if(event.target.dataset.location) {
        let location;
        try {
          location = JSON.parse(event.target.dataset.location);
        } catch (e) {
          console.log(e);
        }
        if(location) {
          goToDefinition(this.get('store'),location,event.which,this.get('currentLineNumber'));
        }
      }
    };
    this.element.addEventListener('mouseup',onmouseup);
    this._onmouseup = onmouseup;
  },
  willDestroyElement : function () {
    if(this._onmouseup) {
      this.element.removeEventListener('mouseup',this._onmouseup);
    }
  },
  //Naughty record selectors : 
  //https://github.com/ghc/ghc/blob/ced2cb5e8fbf4493488d1c336da7b00d174923ce/compiler/typecheck/TcTyDecls.hs#L940-L961
  isNaughtyRecSel : Ember.computed('identifierInfo',function () {
    const idInfo = this.get('identifierInfo');
    return idInfo ? (idInfo.details === "RecSelIdNaughty") : false;   
  }),
  isExternalIdentifier : Ember.computed('identifierInfo',function () {
    const idInfo = this.get('identifierInfo');
    return idInfo ? (idInfo.sort === "External") : false; 
  }),
  identifierObserver : Ember.observer('identifierInfo',function () {
    this.set("downloadedDocumentation","");
    const idInfo = this.get('identifierInfo');
    if(idInfo) {      
      const locationInfo = idInfo.locationInfo;
      if(locationInfo.tag === "ApproximateLocation") {
        const packageId = locationInfo.packageId.name + "-" + locationInfo.packageId.version;
        const currentIdentifier = idInfo;
        
        this.get('store').loadDefinitionSite(packageId,
                                             locationInfo.moduleName,
                                             locationInfo.componentId,
                                             locationInfo.entity,
                                             locationInfo.name)
          .then((definitionSite) => {
            Ember.run.next(this,() => {
              if(currentIdentifier === this.get('identifierInfo')) {                
                this.set('downloadedDocumentation',definitionSite.documentation);
              }});
          });
      }
    }
  })
});
