import Ember from 'ember';
function loadItems(store,component,url) {
  store.loadFromUrlPaginated(url).then((result) => {
    Ember.run.next(() => {
      component.set('total',result.total);
      component.set('items',result.items);
      component.set('first',result.linkHeader.first);
      component.set('next',result.linkHeader.next);
      component.set('prev',result.linkHeader.prev);
      component.set('last',result.linkHeader.last);

      const pageMatch = url.match(/(&|\?)page=(\d+)/);
      const perPageMatch = url.match(/(&|\?)per_page=(\d+)/);

      const page = pageMatch ? pageMatch[2] : 1;
      const perPage = perPageMatch ? perPageMatch[2] : 20;

      if(result.linkHeader.next || result.linkHeader.prev) {
        component.set('firstItemOnPage',(page - 1) * perPage + 1);
        if(!result.linkHeader.last) {
          component.set('lastItemOnPage',result.total);
        } else {
          component.set('lastItemOnPage',page * perPage);
        }
      }
    });
  });
}

export default Ember.Component.extend({
  store : Ember.inject.service('store'),
  init() {
    this._super(...arguments);
    if(this.get('url')) {
      loadItems(this.get('store'),this,this.get('url'));
    }
  },
  urlObserver : Ember.observer('url',function () {
    loadItems(this.get('store'),this,this.get('url'));
    this.element.querySelector(".paginated-list-content").scrollTop = 0;
  }),
  actions : {
    update(url) {
      this.element.querySelector(".paginated-list-content").scrollTop = 0;
      loadItems(this.get('store'),this,url);
    }
  }
});
