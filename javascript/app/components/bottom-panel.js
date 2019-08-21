import Ember from 'ember';

function show(component) {
  const height = Math.floor(component.$containerElement.height() /2);
  component.$().css({
    "display":"block",
    "top" : height+"px"
  });
  component.$topPanelElement.css({
    "height":height+"px"
  });
}

function hide(component) {
  const height = Math.floor(component.$containerElement.height()/2);
  component.$().css({
    "display":"none",
    "height":height+"px"
  });
  component.$topPanelElement.css({
    "height":"100%"
  });
}

export default Ember.Component.extend({
  classNames:["bottom-panel"],
  didInsertElement : function () {
    this._super(...arguments);
    this.$topPanelElement = Ember.$(this.get('topPanelElementId'));
    this.$containerElement = Ember.$(this.get('containerElementId'));
    Ember.run.next(this,() => {
      Ember.$(this.element).resizable({
        handles:"n",
        maxHeight:700,
        minHeight:200,
        resize: (event,ui) => {
          Ember.run.next(this,() => {
            this.$topPanelElement.css({"height": this.$containerElement.height() - ui.size.height});
          });
        }
      });
    });
  },
  visibilityObserver : Ember.observer('visible',function () {
    this.get('visible') ? show(this) : hide(this);
  }),
  actions : {
    close () {
      this.set('visible',false);
    }
  }
});
