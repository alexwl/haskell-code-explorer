import {updateColorThemeCss,themes} from '../utils/color-themes';
import Ember from 'ember';

export default Ember.Controller.extend({
  settings : Ember.inject.service('settings'),
  themes: Object.values(themes),
  init() {
    this._super(...arguments);
    updateColorThemeCss(this.get('settings').get('colorTheme'));
  },
  currentTheme: Ember.computed('settings',function() {
    return this.get('settings.colorTheme.id');
  }),
  actions : {
    themeChanged (themeId) {
      const theme = themes[themeId];
      this.get('settings').set('colorTheme',theme);
      updateColorThemeCss(theme);
    }
  }
});
