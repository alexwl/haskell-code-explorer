import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';

export default Ember.Component.extend({
  store : Ember.inject.service('store'),
  name : Ember.computed('identifierElement',function() {
    const element = this.get('identifierElement');
    if(element) {
      return element.innerText;
    }
  }),
  style : Ember.computed('identifierElement',function() {
    const element = this.get('identifierElement');
    if(element) {      
      return new Ember.String.htmlSafe("color:"+element.style.color);
    }
  }),
  locationInfo : Ember.computed('identifierInfo','identifierOccurrence',function() {
    if(this.get('identifierOccurrence.sort.tag') === "ModuleId") {
      return this.get('identifierOccurrence.sort.contents');
    } else {
      return this.get('identifierInfo.locationInfo');
    }
  }),
  location : Ember.computed('locationInfo',function() {
    const loc = this.get('locationInfo');
    if(loc) {
      if(loc.tag === "ExactLocation") {
        return loc.modulePath;
      } else if(loc.tag === "ApproximateLocation") {
        if(loc.entity === "Mod") {
          return loc.packageId.name + "-" + loc.packageId.version;
        } else {
          return loc.packageId.name + "-" + loc.packageId.version + " " + loc.moduleName;
        }
      } else {
        return loc.contents;
      }
    } else {
      return "";
    }
  }),
  isExternalIdentifier : Ember.computed('identifierInfo',function () {
    return (this.get('identifierInfo.sort') === "External");
  }),
  actions : {
    goToDefinition (event) {      
      goToDefinition(this.get('store'),
                     this.get('locationInfo'),
                     event.which,
                     this.get('currentLineNumber'));
      return false;
    },
    findReferences (identifierInfo,currentPackageId) {
      this.get('findReferences')(currentPackageId,
                                 identifierInfo.externalId,
                                 identifierInfo.demangledOccName);
    }
  }
});
