import Ember from 'ember';
import {goToDefinition} from '../utils/go-to-definition';
import {initializeLineSelection} from '../utils/line-selection';
import {addLinksToLanguageExtensionsDocs} from '../utils/language-extensions';

function compareLocations (p1,p2) {
  if(p1.line === p2.line) {
    if(p1.column === p2.column) {
      return 0;
    } else if(p1.column > p2.column) {
      return 1;
    } else {
      return -1;
    }
  } else if(p1.line > p2.line) {
    return 1;
  } else {
    return -1;
  }
}

function buildSrcSpan(sourceCodeLines,start,end) {
  if(sourceCodeLines[start.line] && sourceCodeLines[end.line]) {
    if(start.line === end.line) {
      return sourceCodeLines[start.line].slice(start.column-1,end.column-1);
    } else {
      const firstLine = sourceCodeLines[start.line];
      let middleLines = [];
      for(let i = start.line + 1; i < end.line;i ++) {
        middleLines.push(sourceCodeLines[i]);
      }
      const lastLine = sourceCodeLines[end.line];
      const minOffset = Math.min(start.column,
                                 (middleLines.concat([lastLine]))
                                 .map((line) => line.search(/\S/))
                                 .reduce((min,value) => Math.min(min,value)));
      return firstLine.slice(start.column-1,firstLine.length) + "\n"
        + middleLines.map((line) => line.slice(minOffset,line.length)).join("\n")
        + (middleLines.length ? "\n" : "") + lastLine.slice(minOffset,end.column-1);
    }
  } else {
    return null;
  }
}

function modifyClass(element,on) {
  if(on) {
    element.classList.add('highlighted-identifier');
  } else {
    element.classList.remove('highlighted-identifier');
  }
}

function highlightIdentifiers(parentElement,identifierElement,on) {
  if(identifierElement.id) {
    const identifiers = Array.prototype.slice.call(parentElement.querySelectorAll("span[id='"+identifierElement.id+"']"));
    identifiers.forEach((identifier) => {
      modifyClass(identifier,on);
    });
  } else {
    modifyClass(identifierElement,on);//Literal
  }
}

//divident is a string
//divident may have any number of digits
function modulo(divident, divisor) {
  return Array.from(divident).map(c => parseInt(c))
    .reduce((acc, value) => {
      return (acc * 10 + value) % divisor;
    },0);
}

function isDefinedInCurrentModule(moduleName,modulePath,identifierInfo) {
  return (identifierInfo.sort === "External") &&
    (identifierInfo.locationInfo.modulePath === modulePath
     || identifierInfo.locationInfo.moduleName === moduleName)
}

function identifierStyle(identifierElement,
                         identifiers,
                         occurrences,
                         path,
                         colorTheme,
                         moduleName) {
  const idOcc = occurrences[identifierElement.dataset.occurrence];

  let color = colorTheme.defaultColor;
  let fontWeight;

  if(idOcc) {
    if(idOcc.sort.tag === 'TypeId') {
      color = colorTheme.typeColor;
    } else if(idOcc.description === "HsLit" ||
              idOcc.description === "HsOverLit"||
              idOcc.description === "LitPat" ||
              idOcc.description === "NPat" ||
              idOcc.description === "NPlusKPat" ||
              idOcc.description === "OverLit") {
      color = colorTheme.literalColor;
    } else {
      const idInfo = identifiers[identifierElement.dataset.identifier];
      if(idInfo) {
        if(isDefinedInCurrentModule(moduleName,path,idInfo)) {
          color = colorTheme.topLevelIdFromCurrentModule;
        } else if(idInfo.sort === "Internal" && idInfo.locationInfo.tag === "ExactLocation") {
          const colorNumber = modulo(identifierElement.id,colorTheme.localIdentifierColor.length);
          color = colorTheme.localIdentifierColor[colorNumber];
          fontWeight = "bold";
        }
      }
    }
  }

  return "color:"+color+";"
    +(fontWeight ? "font-weight:" + fontWeight : "")+";"
    +(idOcc.isBinder ? "text-decoration:underline;" : "");
}

function initializeIdentifiers (sourceCodeContainerElement,component) {
  const identifierElements = Array.prototype.slice.call(sourceCodeContainerElement.querySelectorAll("span.identifier"));
  if(identifierElements.length > 0) {
    const timeout = 250;//milliseconds
    let timer = null;

    identifierElements.forEach((identifierElement) => {

      const cssText = identifierStyle(identifierElement,
                                      component.get('identifiers'),
                                      component.get('occurrences'),
                                      component.get('path'),
                                      component.get('colorTheme'),
                                      component.get('name'));

      identifierElement.style.cssText = cssText;

      //go to definition
      identifierElement.onmouseup = (event) => {
        if(timer) {
          clearTimeout(timer);
        }

        if(!window.getSelection().isCollapsed) {
          return;
        }

        const identifierInfo = component.get('identifiers')[identifierElement.dataset.identifier];
        const idOccurrenceInfo = component.get('occurrences')[identifierElement.dataset.occurrence];

        const currentLineNumber = parseInt(identifierElement.parentNode.dataset.line);

        if(idOccurrenceInfo.sort.tag === "ModuleId") {
          goToDefinition(component.get('store'),
                         idOccurrenceInfo.sort.contents,
                         event.which,
                         currentLineNumber);
        }
        else {
          if(identifierInfo && (event.which === 1 || event.which === 2)) {
            if(!idOccurrenceInfo.isBinder) {
              goToDefinition(component.get('store'),
                             identifierInfo.locationInfo,
                             event.which,
                             currentLineNumber);
            } else {
              if(identifierInfo.sort === "External") {
                component.get('findReferences')(component.get('packageId'),
                                                identifierInfo.externalId,
                                                identifierInfo.demangledOccName,
                                                identifierInfo.locationInfo);

              }
            }
          }
        }
      }
      identifierElement.onmouseover = () => {
        highlightIdentifiers(sourceCodeContainerElement,identifierElement,true);
        if(timer) {
          clearTimeout(timer);
        }
        timer = setTimeout(() => {
          Ember.run.next(component,() => {
            const identifierInfo = component.get('identifiers')[identifierElement.dataset.identifier];
            const identifierOccurrence = component.get('occurrences')[identifierElement.dataset.occurrence];
            console.log(identifierOccurrence);
            console.log(identifierInfo);

            component.set('selectedIdentifier',identifierElement);
            component.set('currentLineNumber',parseInt(identifierElement.parentNode.dataset.line) || 1);
            component.set('identifierInfo',identifierInfo);
            component.set('identifierOccurrence',identifierOccurrence);
            component.set('hasSelectedExpression',false);
            component.set('isHoveredOverIdentifier',true);

          });
        },timeout);
      };

      identifierElement.onmouseout = () => {
        highlightIdentifiers(sourceCodeContainerElement,identifierElement,false);

        if(timer) {
          clearTimeout(timer);
        }

        timer = setTimeout (() => {
          Ember.run.next(component,() => {
            component.set('isHoveredOverIdentifier',false);
          });
        },timeout);
      };
    });
    component.timer = timer;
  }
}



function contains (node, other) {
  return node === other || !!(node.compareDocumentPosition(other) & 16);
}

function initializeExpressionInfo(sourceCodeContainerElement,component) {
  const lineElements = Array.prototype.slice.call(sourceCodeContainerElement.querySelectorAll("td.line-content"));
  if(lineElements.length > 0) {

    //Line numbers start with 1
    let sourceCodeLines = [""];

    lineElements.forEach((el) => {
      sourceCodeLines.push(el.textContent);
    });

    const allowedNodeNames = ["#text","SPAN","TD"];
    let isLoading = false;
    let shouldWait = false;
    const timeout = 400;//milliseconds

    const onmouseup = function()  {
      Ember.run.next(() => {
        if(isLoading || shouldWait) {
          return;
        }
        shouldWait = true;
        setTimeout(() => {shouldWait = false;},timeout);

        component.set('hasSelectedExpression',false);

        const selection = window.getSelection();

        //Selection of multiple lines inside a table doesn't work in Firefox
        //https://bugzilla.mozilla.org/show_bug.cgi?id=365900

        if(!(selection.anchorNode && selection.focusNode)
           || !contains(sourceCodeContainerElement,selection.anchorNode)
           || !contains(sourceCodeContainerElement,selection.focusNode)
           || (allowedNodeNames.indexOf(selection.anchorNode.nodeName) === -1)
           || (allowedNodeNames.indexOf(selection.focusNode.nodeName) === -1)
           || selection.isCollapsed) {
          return;
        }

        // Detects whether the selection is backwards
        const detectionRange = document.createRange();
        detectionRange.setStart(selection.anchorNode, selection.anchorOffset);
        detectionRange.setEnd(selection.focusNode, selection.focusOffset);
        const isBackward = detectionRange.collapsed;

        let startNode,startNodeOffset,endNode,endNodeOffset;

        if(isBackward) {
          startNode = selection.focusNode;
          startNodeOffset = selection.focusOffset;
          endNode = selection.anchorNode;
          endNodeOffset = selection.anchorOffset;
        } else {
          startNode = selection.anchorNode;
          startNodeOffset = selection.anchorOffset;
          endNode = selection.focusNode;
          endNodeOffset = selection.focusOffset;
        }

        let lineStart,columnStart,lineEnd,columnEnd;
        let infoWindowTargetElement;


        //HTML inside source code container :
        //<tr><td><span data-start="1" date-end="3">abc</span><span>...</span></td></tr>
        //<tr>...</tr>
        if(startNode.nodeName === "#text") {
          const parent = startNode.parentNode;//<span>
          columnStart = parseInt(parent.dataset.start) + startNodeOffset;
          lineStart = parseInt(parent.parentNode.dataset.line);

          if(startNodeOffset === startNode.textContent.length && parent.nextSibling === null) {
            const tr = startNode.parentNode.parentNode.parentNode;// span -> td -> tr

            //Skipping empty lines
            let nextLine = tr.nextSibling;
            while(nextLine.children[1].textContent === "") {
              nextLine = nextLine.nextSibling;
            }
            infoWindowTargetElement = nextLine.children[1].children[0];

          } else {
            if(!(startNodeOffset === 0) && (parent.nextSibling)) {
              infoWindowTargetElement = parent.nextSibling;
            } else {
              infoWindowTargetElement = parent;
            }
          }
        } else if(startNode.nodeName === "SPAN") {
          columnStart = 1;
          lineStart = parseInt(startNode.parentNode.dataset.line);

          const tr = startNode.parentNode.parentNode; // td -> tr
          let nextLine = tr.nextSibling;
          while(nextLine.children[1].textContent === "") {
            nextLine = nextLine.nextSibling;
          }
          infoWindowTargetElement = nextLine.children[1].children[0];

        } else if(startNode.nodeName === "TD") {
          if(startNodeOffset > 0) {
            const child = startNode.children[startNodeOffset-1];
            columnStart = parseInt(child.dataset.start);
          } else {
            columnStart = 1;
          }
          lineStart = parseInt(startNode.id.slice(2));
          infoWindowTargetElement = startNode.children[0];
        }

        if(endNode.nodeName === "#text") {
          columnEnd = parseInt(endNode.parentNode.dataset.start) + endNodeOffset;
          lineEnd = parseInt(endNode.parentNode.parentNode.dataset.line);
        } else if(endNode.nodeName === "SPAN") {
          columnEnd = 1;
          lineEnd = parseInt(endNode.parentNode.dataset.line);
        } else if(endNode.nodeName === "TD"){
          if(endNodeOffset > 0) {
            const child = endNode.children[endNodeOffset-1];
            columnEnd = parseInt(child.dataset.start);
          } else {
            columnEnd = 1;
          }
          lineEnd = parseInt(endNode.id.slice(2));
        }

        const loadExprPromise = component.get('store').loadExpressions(
          component.get('packageId'),
          component.get('path'),
          lineStart,
          columnStart,
          lineEnd,
          columnEnd);
        isLoading = true;

        loadExprPromise.then((expressions) => {
          Ember.run.next(() => {
            if(expressions && expressions.length > 0) {
              expressions.sort(function(expr1,expr2) {
                if( compareLocations(expr1.srcSpan.start,expr2.srcSpan.start) <= 0
                    && compareLocations(expr1.srcSpan.end,expr2.srcSpan.end) >= 0 ) {
                  return -1;
                } else {
                  return 1;
                }
              });

              const expressionsWithSourceCode = expressions.reduce((result,expression) => {
                const object = Ember.copy(expression);
                const srcSpan = buildSrcSpan(sourceCodeLines,
                                             expression.srcSpan.start,
                                             expression.srcSpan.end);
                if(srcSpan) {
                  object.sourceCode = srcSpan;
                  return result.concat(object);
                } else {
                  return result;
                }
              },[]);

              if(expressionsWithSourceCode.length > 0) {
                component.set('selectedIdentifier',infoWindowTargetElement);
                component.set('expressions',expressionsWithSourceCode);
                component.set('currentLineNumber',parseInt(infoWindowTargetElement.parentNode.dataset.line) || 1);
                component.set('hasSelectedExpression',true);

              }
            }
            isLoading = false;
          });
        });
      });
    };

    sourceCodeContainerElement.addEventListener('mouseup',onmouseup);
    component._onmouseup = onmouseup;
  }
}

export default Ember.Component.extend({
  store : Ember.inject.service('store'),
  selectedIdentifier : null,
  isHoveredOverIdentifier : false,
  hasSelectedExpression : false,
  showDeclarations : true,
  showDeclarationsLabel : Ember.computed('showDeclarations',function () {
    return this.get('showDeclarations') ? "Hide" : "Show";
  }),
  queryObserver : Ember.observer("query",function() {
    Ember.run.debounce(this, () => {
      const regExp = new RegExp(this.get('query'),"i");
      const filteredDeclarations = this.get('declarations').filter((d) => d.name.search(regExp) != -1);
      Ember.run.next(() => {
        this.set('filteredDeclarations',filteredDeclarations);
      });
    }, 300);
  }),
  identifierLocationInfo : Ember.computed('identifierInfo','identifierOccurrence',function() {
    const idOcc = this.get('identifierOccurrence');
    const idInfo = this.get('identifierInfo');
    if(idOcc) {
      if(idOcc.sort.tag === "ModuleId") {
        return idOcc.sort.contents;
      } else {
        if(idInfo) {
          return idInfo.locationInfo;
        } else {
          return null;
        }
      }
    }
  }),
  themeObserver : Ember.observer('colorTheme',function() {
    Ember.run.next(this,() => {
      this.cleanup();
      this.didInsertElement();
    });
  }),
  fileObserver : Ember.observer('path',function() {
    Ember.run.next(this,() => {
      this.cleanup();
      this.didInsertElement();
    });
  }),
  cleanup() {
    if(this.timer) {
      clearTimeout(this.timer);
    }
    if(this._onhashchange) {
      window.removeEventListener('hashchange',this._onhashchange);
    }
    if(this._onkeydown) {
      document.removeEventListener('keydown',this._onkeydown);
    }
    if(this._onkeyup) {
      document.removeEventListener('keyup',this._onkeyup);
    }
    if(this._onmouseup) {
      this.sourceCodeContainerElement.removeEventListener('mouseup',this._onmouseup);
    }
    this.set('selectedIdentifier',null);
    this.set('isHoveredOverIdentifier',false);
    this.set('hasSelectedExpression',false);
    this.set('showDeclarations',true);
  },
  didReceiveAttrs() {
    this.set('filteredDeclarations',this.get('declarations'));
  },
  didInsertElement() {
    this._super(...arguments);
    const sourceCodeContainerElement = this.element.querySelector('.source-code-container');
    sourceCodeContainerElement.innerHTML = this.get('html');
    this.sourceCodeContainerElement = sourceCodeContainerElement;

    // Add links to Haskell language extensions docs
    const lines = this.sourceCodeContainerElement.querySelectorAll("tr > td:nth-child(2)");
    const lineCount = lines.length;
    let i = 0;
    while(i < lineCount) {
      const line = lines.item(i);
      const lineText = line.textContent;
      if(lineText) {
        // A file-header pragma must precede the module keyword in the file.
        if(lineText.indexOf("module ") === 0) {
          break;
        } else {
          line.innerHTML = addLinksToLanguageExtensionsDocs(lineText);
        }
      }
      i = i + 1;
    }

    this.element.parentNode.scrollTop = 0;
    const declarations = this.element.querySelector('.declarations-content');
    this.set('query','');
    if(declarations) {
      declarations.scrollTop = 0;
    }
    Ember.run.next(this,() => {
      initializeIdentifiers(sourceCodeContainerElement,this);
      initializeLineSelection(sourceCodeContainerElement,this);
      initializeExpressionInfo(sourceCodeContainerElement,this);
    });
  },
  willDestroyElement() {
    this.cleanup();
  },
  actions : {
    goToLine(lineNumber) {
      window.location.hash = "L"+lineNumber;
    },
    toggleShowDeclarations() {
      this.toggleProperty('showDeclarations');
    }
  }
});
