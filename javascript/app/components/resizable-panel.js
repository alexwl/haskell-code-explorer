import Ember from 'ember';

function hide (component,byUser) {
  component.$alsoResizeElement.css({left: 0});
  component.$().css({width:0});
  component.set('hidden',true);
  component.$(".show-left-panel-button").show();
  if(byUser) {
    component.set('hiddenByUser',true);
  }
}

function show (component,byUser) {
  component.$alsoResizeElement.css({left: 300});
  component.$().css({width:300});
  component.set('hidden',false);
  component.$(".show-left-panel-button").hide();
  if(byUser) {
    component.set('hiddenByUser',false);
  }
}

export default Ember.Component.extend({
  hidden:false,
  hiddenByUser:false,
  didInsertElement : function () {
    this._super(...arguments);
    Ember.run.next(this,() => {
      const onresize = () => {
        if(!this.get('hiddenByUser')) {
          const width = window.innerWidth;
          if(!this.get('hidden') && width < 700) {
            hide(this,false);
          } else if(this.get('hidden') && width > 700) {
            show(this,false);
          }
        }
      };
      this._onresize = onresize;
      window.addEventListener('resize', onresize);
      const $alsoResizeElement = Ember.$(this.get('alsoResizeElementId'));
      Ember.$(this.element).resizable({
        maxWidth: 800,
        minWidth: 200,
        handles: 'e',
        resize: (event,ui) => {
          Ember.run.next(this,() => {
            $alsoResizeElement.css({left: ui.size.width});
          });
        }
      });
      this.$alsoResizeElement = $alsoResizeElement;
    });
  },
  hideButtonLabel : Ember.computed('hidden',function() {
    return this.get('hidden') ? "&gt;" : "&lt;";
  }),
  willDestroyElement() {
    if(this._onresize) {
      window.removeEventListener('resize',this._onresize);
    }
  },
  actions : {
    hide() {
      if(this.get('hidden')) {
        show(this,true);
      } else {
        hide(this,true);
      }
    }
  }
});
