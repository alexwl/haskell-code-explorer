function initializeLineSelection(sourceCodeContainerElement,component) {
  const lineNumbers = Array.prototype.slice.call(sourceCodeContainerElement.querySelectorAll("td.line-number"));
  if(lineNumbers.length > 0) {
    const onhashchange = function () {
      highlightSelectedLines(sourceCodeContainerElement);
    }
    window.addEventListener("hashchange",onhashchange);
    component._onhashchange = onhashchange;

    let shiftPressed;
    const onkeydown = function (event) {
      if(event.keyCode === 16) { shiftPressed = true; }
    };
    const onkeyup = function (event) {
      if(event.keyCode === 16) { shiftPressed = false; }
    };

    document.addEventListener('keydown',onkeydown);
    document.addEventListener('keyup',onkeyup);
    component._onkeydown = onkeydown;
    component._onkeyup = onkeyup;

    let selectedLine1,selectedLine2;
    lineNumbers.forEach((lineNumberElement) => {
      lineNumberElement.onclick = function()  {
        const number = parseInt(this.textContent);
        if(shiftPressed && selectedLine1) {
          if(selectedLine1 != number) {
            selectedLine2 = number;
            if(selectedLine1 < selectedLine2) {
              highlightLines(sourceCodeContainerElement,selectedLine1,selectedLine2);
              window.location.hash = "L"+selectedLine1+"-L"+selectedLine2;
            } else {
              highlightLines(sourceCodeContainerElement,selectedLine2,selectedLine1);
              window.location.hash = "L"+selectedLine2+"-L"+selectedLine1;
            }
          }
        } else {
          selectedLine1 = number;
          selectedLine2 = null;
          highlightLines(sourceCodeContainerElement,selectedLine1,selectedLine1);
          window.location.hash = "L"+number;
        }
      }
    });
    const lines = highlightSelectedLines(sourceCodeContainerElement);
    if(lines.length) {
      selectedLine1 = lines[0];
      selectedLine2 = lines[1];
    }
  }
}

function highlightSelectedLines (sourceCodeContainerElement) {
  const lineInfo = window.location.hash.slice(1);
  if(lineInfo) {
    if(lineInfo.includes('-')) {
      const lines = lineInfo.split("-");
      const lineNumber1 = parseInt(lines[0].substring(1));
      const lineNumber2 = parseInt(lines[1].substring(1));
      if(lineNumber1 && lineNumber2 && lineNumber1 <= lineNumber2) {
        highlightLines(sourceCodeContainerElement,lineNumber1,lineNumber2);
        const line = sourceCodeContainerElement.querySelector("td#LC"+lineNumber1);
        if(line) {
          scrollLineIntoView(line,sourceCodeContainerElement);
        }
        return [lineNumber1,lineNumber2];
      }
    } else {
      const lineNumber = parseInt(lineInfo.substring(1));
      if(lineNumber) {
        highlightLines(sourceCodeContainerElement,lineNumber,lineNumber);
        const line = sourceCodeContainerElement.querySelector("td#LC"+lineNumber);
        if(line) {
          scrollLineIntoView(line,sourceCodeContainerElement);
        }
        return [lineNumber];
      }
    }
  } else {
    highlightLines(sourceCodeContainerElement,0,0);
    return [];
  }
}

function scrollLineIntoView(lineElement,sourceCodeContainerElement) {
  lineElement.parentNode.scrollIntoView();
  const container = sourceCodeContainerElement.parentNode.parentNode;
  const windowHeight = container.offsetHeight;
  const fullHeight = sourceCodeContainerElement.offsetHeight;

  if(fullHeight - container.scrollTop > windowHeight) {
    container.scrollTop = container.scrollTop - (windowHeight/2 - 20);
  }
}

function highlightLines(parentElement,startLine,endLine) {
  const lineElements = Array.prototype.slice.call(parentElement.querySelectorAll("td.line-content"));
  lineElements.forEach((lineElement) => {
    const number = parseInt(lineElement.id.substring(2)); //<td "id"="LC10">...</td>
    if(number >= startLine && number <= endLine) {
      lineElement.classList.add('highlighted-line');
    } else {
      lineElement.classList.remove('highlighted-line');
    }
  });
}

export {
  initializeLineSelection,highlightLines,highlightSelectedLines
}
