import Ember from 'ember';
import {themes} from '../utils/color-themes';

export default Ember.Service.extend({
  init() {
    this._super(...arguments);
    if(localStorage) {
      const colorThemeId = localStorage.getItem("colorThemeId");
      const colorTheme = themes[colorThemeId];
      if(colorThemeId) {
        this.set('colorTheme',colorTheme);
      }
    }
  },
  colorTheme : themes["darkTheme"],
  settingsObserver : Ember.observer("colorTheme",function() {
    if(localStorage) {      
      localStorage.setItem("colorThemeId",this.get('colorTheme').id);
    }
  })
});
