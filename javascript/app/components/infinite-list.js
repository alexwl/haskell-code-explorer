import Component from '@ember/component';
import { run } from '@ember/runloop';
import { observer } from '@ember/object';

let pageNumber;
let updating = false;

function initialize(component) {
  component.set('renderedElements',component.get('elements').slice(0,component.get('perPage')));
  pageNumber = 1;
}

export default Component.extend({
  renderedElements : [],
  init() {
    this._super(...arguments);
    initialize(this);
  },
  elementsObserver : observer('elements',function() {
    initialize(this);
    const containerElement = document.getElementById(this.get('containerElementId'));
    if(containerElement) {
      containerElement.scrollTop = 0;
    }
  }),
  didInsertElement() {
    const containerElement = document.getElementById(this.get('containerElementId'));
    if(containerElement) {
      const component = this;
      containerElement.onscroll = function() {
        const perPage = component.get('perPage');
        const elements = component.get('elements');

        if(!updating &&
           (pageNumber * perPage < elements.length) &&
           (containerElement.scrollTop + containerElement.offsetHeight
            > component.element.offsetHeight - 100)) {

          updating = true;
          run.next(component,() => {
            const newElements = elements.slice(pageNumber * perPage,(pageNumber + 1) * perPage);
            component.get('renderedElements').pushObjects(newElements);
            pageNumber ++;
            updating = false;
          });
        }
      }
    }
  }
});
