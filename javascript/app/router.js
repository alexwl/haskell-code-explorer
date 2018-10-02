import Ember from 'ember';
import config from './config/environment';

var Router = Ember.Router.extend({
  location: config.locationType
});

Router.map(function() {
  this.route('packages',{path:''});
  this.route('package', {path:'/package/:packageId'}, function() {
    this.route('show',function() {
      this.route('file', {path:'*filePath'}, function() {
      });
    });
    this.route('search',{path:'/search/:query'});
  });
  this.route('bad-url', { path: '/*badurl' });
});

export default Router;
