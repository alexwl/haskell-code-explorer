import Ember from 'ember';
import {urls} from '../utils/api-urls';
import {goToDefinition} from '../utils/go-to-definition';

export default Ember.Route.extend({
  store : Ember.inject.service('store'),
  model (params) {
    return {
      query: params.query,
      url: urls.globalIdentifiersUrl(params.query)+"?per_page=20"
    };
  },
  setupController(controller, model) {
    this._super(controller, model);    
    controller.set('createSearchUrlFunction',(query) => {
      return urls.globalIdentifiersUrl(query);
    });
  },
  afterModel () {    
    const onmouseup = (event) => {
      // This makes links in documentation clickable
      if(event.target.dataset.location) {
        let location;
        try {
          location = JSON.parse(event.target.dataset.location);
        } catch (e) {
          console.log(e);
        }
        if(location) {
          goToDefinition(this.get('store'),location,event.which);
        }
      }
    };
    this._onmouseup = onmouseup;
    document.addEventListener('mouseup',onmouseup);    
  },
  deactivate() {
    if(this._onmouseup) {
      document.removeEventListener('mouseup',this._onmouseup);
    }
  }  
});
