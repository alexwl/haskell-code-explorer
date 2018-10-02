import Ember from 'ember';
export default Ember.Component.extend({
  store : Ember.inject.service('store'),  
  highlightedItemIndex: -1,
  items : [],
  query: null,
  didInsertElement() {
    const $input = Ember.$(this.element).find(".search-input");
    const $autocompleteContainer = Ember.$(this.element).find(".autocomplete-container");    
    this.$input = $input;        
    this.$autocompleteContainer = $autocompleteContainer;    
    const width = $input.width() + 300;
    $autocompleteContainer.css({
      "width" : width+"px",
      "top" : $input.outerHeight()
    });
    $input.keyup((e) => {
      if(e.which === 13) {
        this.onEnter();
      } else if(e.which === 27) {
        this.onEsc();
      } else if(e.which === 40) {
        this.onDown();
      } else if(e.which === 38) {
        this.onUp();
      } 
    });
    $input.focusin(() => {      
      this.showAutocompleteList();
    });
    $input.focusout(() => {
      //Timeout is needed to make sure that click event fires
      Ember.run.later((() => {
        this.hideAutocompleteList();
      }), 100);
    });
  },
  willDestroyElement() {
    this._super(...arguments);
    this.$input.off('keyup');
    this.$input.off('focusin');
    this.$input.off('focusout');
  },
  onEnter() {
    if(this.get('highlightedItemIndex') !== -1) {
      const item = this.get('items')[this.get('highlightedItemIndex')];
      if(item) {
        this.hideAutocompleteList();
        this.get('selectItem')(item);
      }
    } else {
      this.hideAutocompleteList();
      this.get('onSubmit')(this.get('query'));
    }
  },
  onEsc() {
    this.hideAutocompleteList();
  },
  onDown() {
    this.showAutocompleteList();
    const index = this.get('highlightedItemIndex');
    const items = this.get('items');
    const itemsCount = items.length;
    if(itemsCount > 0) {
      if(index !== -1) {
        if(index === itemsCount - 1) {
          this.set('highlightedItemIndex',0);
        } else {
          this.set('highlightedItemIndex',index+1);
        }
      } else {
        this.set('highlightedItemIndex',0);
      }
    }
  },
  onUp() {
    this.showAutocompleteList();
    const index = this.get('highlightedItemIndex');
    const items = this.get('items');
    const itemsCount = items.length;
    if(itemsCount > 0) {
      if(index !== -1) {
        if(index === 0) {
          this.set('highlightedItemIndex',itemsCount - 1);
        } else {
          this.set('highlightedItemIndex',index - 1);
        }
      } else {
        this.set('highlightedItemIndex',itemsCount - 1);
      }
    }
  },
  hideAutocompleteList() {
    this.set('highlightedItemIndex',-1);
    this.$autocompleteContainer.css({
      "display":"none",
    });
  },
  showAutocompleteList() {
    this.$autocompleteContainer.css({
      "display":"block"
    });
  },
  queryObserver : Ember.observer("query",function() {
    if(this.get('query')) {
      const perPage = this.get('maxItems') ? this.get('maxItems') : 10;
      const url = this.get('createSearchUrlFunction')(this.get('query')) + "?per_page=" + perPage;
      Ember.run.debounce(this, () => {
        this.get('store').loadFromUrlPaginated(url).then((result) => {
          Ember.run.next(() => {
            this.set('items',result.items);
          });
        });
      }, 400);
      this.showAutocompleteList();
    } else {
      this.hideAutocompleteList();
      this.set('items',[]);
    }
  }),
  actions : {
    onSubmit() {
      this.hideAutocompleteList();
      this.get('onSubmit')(this.get('query'));
    },
    goToDefinition (item) {
      this.hideAutocompleteList();
      this.get('selectItem')(item);
    }
  }
});
