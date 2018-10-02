import Ember from 'ember';

let resizing = false;
let dragging = false;

function updatePosition(component) {
  const targetElement = component.get('targetElement');
  if(targetElement) {
    const infoWindowHeight = component.element.offsetHeight;
    const targetElementHeight = targetElement.offsetHeight;
    
    const parent = targetElement.parentNode;//<td> element    
    const containerElement = document.querySelector("#" + component.get('containerElementId'));    

    //getBoundingClientRect() returns the smallest rectangle which contains
    //the entire element, with read-only left, top, right, bottom, x, y, width,
    //and height properties describing the overall border-box in pixels. Properties
    //other than width and height are relative to the top-left of the *viewport*.
    const targetTopViewport = targetElement.getBoundingClientRect().top;
    
    let containerTopViewport;
    if (containerElement) {
      containerTopViewport = containerElement.getBoundingClientRect().top;
    } else {
      containerTopViewport = 0;
    }
    
    let infoWindowTop;
    if(targetTopViewport < infoWindowHeight + containerTopViewport) {
      //offsetTop is the number of pixels from the top of the closest relatively
      //positioned parent element.      
      infoWindowTop = targetElement.offsetTop + parent.offsetTop
        + targetElementHeight + 10 + "px";
    } else {
      infoWindowTop = targetElement.offsetTop + parent.offsetTop
        - infoWindowHeight + "px";
    }

    const infoWindowLeft = targetElement.offsetLeft + parent.offsetLeft + "px";
    
    component.$().css({
      top:infoWindowTop,
      left:infoWindowLeft
    });
  } else {
    component.set('isPinned',false);
  }
}

export default Ember.Component.extend({
  classNames : ["info-window-container"],
  attributeBindings: ['hidden'],
  isPinned : false,
  isFocused: false,
  didInsertElement () {
    const component = this;
    
    const $headerElement = Ember.$(component.element.querySelector(".info-window-header"));
    const $contentElement = Ember.$(component.element.querySelector(".info-window-content"));
    const $infoWindowElement = Ember.$(component.element.querySelector(".info-window"));
    const $infoWindowContainerElement = Ember.$(component.element);
    
    this.$headerElement = $headerElement;
    this.$contentElement = $contentElement;    

    this.$().resizable({    
      handles: "n,w",
      minHeight: 80,
      minWidth: 400,
      start: function() {
        resizing = true;
      },
      stop: function() {
        resizing = false;
      },
      resize : function() {
        const containerHeight = $infoWindowContainerElement.height();               
        $infoWindowElement.css({
          "height": containerHeight + 2 + "px"
        });        
        $contentElement.css({
          "max-height":(containerHeight - $headerElement.outerHeight(true)) + "px"
        });
      }
    });
    this.$().draggable({
      containment:"#" + this.get('containerElementId'),
      handle: $headerElement,
      start: function() {
        dragging = true;
      },
      stop: function() {
        dragging = false;
      }
    });
  },
  mouseEnter () {
    if(!this.get('hasSelectedExpression')) {
      this.set('isFocused',true);
    }
  },
  mouseLeave (event) {
    //Workaround for a bug in Chrome
    const element = document.elementFromPoint(event.clientX,event.clientY);
    if(element && element.classList.contains('link')) {
      return;
    }    
    if(!resizing
       && !dragging
       && !this.get('isPinned')
       && !this.get('hasSelectedExpression')) {
      this.set('isFocused',false);
    }
  },
  hidden : Ember.computed('isHoveredOverIdentifier',
                          'isFocused',
                          'hasSelectedExpression',
                          'isPinned', function() {
    if (this.$contentElement) {
       this.$contentElement.scrollTop(0);
    }
    if (this.get('isPinned')
        || this.get('isFocused')
        || this.get('isHoveredOverIdentifier')
        || this.get('hasSelectedExpression')) {      
      return false;
    } else {
      return true;
    }
  }),
  didUpdate() {
    updatePosition(this);
  },
  actions : {
    close() {
      this.set('isPinned',false);
      this.set('isFocused',false);
      this.set('hasSelectedExpression',false);
    },
    pin() {
      this.toggleProperty('isPinned');
    }
  }
});
