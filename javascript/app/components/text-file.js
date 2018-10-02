/* global showdown */
import Ember from 'ember';
import {initializeLineSelection} from '../utils/line-selection';

function escapeHtml(text) {
  return text.replace(/[\"&<>]/g, function (a) {
    return { '"': '&quot;', '&': '&amp;', '<': '&lt;', '>': '&gt;' }[a];
  });
}

function addLineNumbers (text) {
  const start = "<table class='source-code'><tbody>";
  const end = "</tbody></table>";
  let lineNumber = 0;
  const lines = text.split("\n").map((line) => {
    lineNumber ++;
    const lineNumberHtml = "<td id='LN"+lineNumber+"' class='line-number'>"+lineNumber+"</td>";
    const lineContentHtml = "<td id='LC"+lineNumber+"' class='line-content'>"+escapeHtml(line)+"</td>";
    return "<tr>"+ lineNumberHtml + lineContentHtml + "</tr>";
  }).join("");
  return start + lines + end;
}

const markdownExtensions = ["markdown", "mdown", "mkdn", "mkd", "md"];

export default Ember.Component.extend({
  isMarkdown : Ember.computed('path',function() {
    const maybeExtension = this.get('path').split('.').pop();
    return markdownExtensions.any((extension) => (maybeExtension === extension));
  }),
  html : Ember.computed('path','isMarkdown',function() {
    if(this.get('isMarkdown')) {
      return this.markdownConverter.makeHtml(this.get('text'));
    } else {
      return addLineNumbers(this.get('text'));
    }
  }),
  init() {
    this._super(...arguments);
    this.markdownConverter = new showdown.Converter();    
  },
  didInsertElement() {
    const sourceCodeContainerElement = this.element.querySelector('.source-code-container');
    initializeLineSelection(sourceCodeContainerElement,this);
    this.element.parentNode.scrollTop = 0;
  },
  willDestroyElement : function () {
    this.cleanup();
  },
  cleanup() {
    if(this._onhashchange) {      
      window.removeEventListener('hashchange',this._onhashchange);
    }
    if(this._onkeydown) {
      document.removeEventListener('keydown',this._onkeydown);
    }
    if(this._onkeyup) {
      document.removeEventListener('keyup',this._onkeyup);
    }
  },
  pathObserver : Ember.observer('path',function() {
    Ember.run.next(this,() => {
      this.cleanup();
      this.didInsertElement();      
    });
  })
});
