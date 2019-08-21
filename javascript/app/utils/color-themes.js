function colorThemeToCss(colorTheme) {
  const css = `
   body {
     color: ${colorTheme.defaultColor} !important;
     background-color: ${colorTheme.backgroundColor} !important;
   }
   input {
     color: ${colorTheme.defaultColor} !important;
     background-color: ${colorTheme.backgroundColor} !important;
     border-color: ${colorTheme.borderColor} !important;
   }
   .package-content {
     border-top: 1px solid ${colorTheme.borderColor} !important;
   }
   .header a {
      color : ${colorTheme.menuLinkColor} !important;
   }
   a {
    color: ${colorTheme.typeColor} !important;
   }
   span.link {
      color: ${colorTheme.typeColor} !important;
   }
   .header {
     background-color: ${colorTheme.menuColor} !important;
     border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   .declarations-content {
     background-color: ${colorTheme.navigationPanelColor} !important;
     border: 1px solid ${colorTheme.borderColor} !important;
   }
   .declarations-header {
     background-color: ${colorTheme.navigationPanelColor} !important;
     border: 1px solid ${colorTheme.borderColor} !important;
   }
   li.declaration {
     border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   .left-panel {
     background-color: ${colorTheme.navigationPanelColor} !important;
     border-right: 1px solid ${colorTheme.borderColor} !important;
   }
   .show-left-panel-button {
     background-color: ${colorTheme.navigationPanelColor} !important;
     border-right:1px solid ${colorTheme.borderColor} !important;
     border-bottom:1px solid ${colorTheme.borderColor} !important;
   }
   .right-panel {
     background-color: ${colorTheme.backgroundColor} !important;
   }
   a.jstree-anchor {
     color: ${colorTheme.defaultColor} !important;
   }
   .declaration > a {
     color: ${colorTheme.defaultColor} !important;
   }
   .highlighted-line {
     background : ${colorTheme.highlightedLineColor} !important;
   }
   table.source-code {
     background-color: ${colorTheme.backgroundColor} !important;
     color: ${colorTheme.defaultColor} !important;
   }
   .jstree-clicked {
     background-color: ${colorTheme.backgroundColor} !important;
   }
   .jstree-hovered {
     background-color: ${colorTheme.backgroundColor} !important;
   }
   ul.autocomplete-items {
     background-color: ${colorTheme.backgroundColor} !important;
     border-top: 1px solid ${colorTheme.borderColor} !important;
     border-left: 1px solid ${colorTheme.borderColor} !important;
     border-right: 1px solid ${colorTheme.borderColor} !important;
   }
   ul.autocomplete-items > li {
     border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   ul.autocomplete-items > li:hover {
     background-color: ${colorTheme.highlightedLineColor} !important;
   }
   ul.autocomplete-items > li.highlighted {
     background-color: ${colorTheme.highlightedLineColor} !important;
   }
   .source-code-snippet {
      color: ${colorTheme.defaultColor} !important;
      border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   .source-code-snippet:hover {
      background-color: ${colorTheme.highlightedLineColor} !important;
   }
   .bottom-panel {
      background-color: ${colorTheme.backgroundColor} !important;
      border-top: 1px solid ${colorTheme.borderColor} !important;
   }
   .bottom-panel-header {
      border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   .paginated-list-header {
      border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   li.search-result {
      border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   .search-results-header {
      border-bottom: 1px solid ${colorTheme.borderColor} !important;
   }
   .info-window-content {
      border-top: 1px solid ${colorTheme.borderColor} !important;
   }
   .info-window {
      border: 1px solid ${colorTheme.borderColor} !important;
      background-color:${colorTheme.infoWindowColor} !important;
      color: ${colorTheme.defaultColor} !important;
   }
   .type-info {
      border-top: 1px solid ${colorTheme.borderColor} !important;
   }
   .references-packages  {
      border-right:1px solid ${colorTheme.borderColor} !important;
   }`;
  return css;
}

const darkTheme = {
  id: "darkTheme",
  name: "Dark theme",
  description: "Dark theme (Monokai based)",
  defaultColor: "#F8F8F2",
  backgroundColor: "#272822",
  typeColor: "#66D9EF",
  literalColor: "#E6DB74",
  topLevelIdFromCurrentModule : "#A6E22E",
  localIdentifierColor: ["#F0A3FF","#0075DC","#993F00",
                         "#2BCE48","#FFCC99","#808080","#94FFB5","#8F7C00",
                         "#C20088","#FFA405","#FFA8BB","#426600","#FF0010",
                         "#5EF1F2","#00998F","#E0FF66","#FFFF80",
                         "#FFFF00","#FF5005"],
  menuColor: "#3c3b37",
  menuLinkColor : "#F8F8F2",
  infoWindowColor: "#3c3b37",
  navigationPanelColor: "#3c3b37",
  linkColor : "#0366d6",
  borderColor: "#535557",
  highlightedLineColor: "#4a4a4a"
};

const lightTheme = {
  id: "lightTheme",
  name: "Light theme",
  description: "Light theme (Github based)",
  defaultColor: "#24292e",
  backgroundColor: "#ffffff",
  typeColor: "#005cc5",
  literalColor: "#032f62",
  topLevelIdFromCurrentModule : "#6f42c1",
  localIdentifierColor: ["#005C31",
                     "#2BCE48","#808080","#8F7C00",
                     "#C20088","#FFA405","#ffa8bb","#426600","#FF0010",
                     "#09d7d8","#00998F","#990000","#FF5005"],
  menuColor: "#f2f4f8",
  menuLinkColor : "#24292e",
  infoWindowColor: "#f2f4f8",
  navigationPanelColor: "#f2f4f8",
  linkColor : "#0366d6",
  borderColor: "#e1e4e8",
  highlightedLineColor: "#eaeaea"
};

function updateColorThemeCss (colorTheme) {
  const newStyle = document.createElement('style');
  newStyle.type = 'text/css';
  newStyle.innerHTML = colorThemeToCss(colorTheme);
  newStyle.id = 'color-theme';
  const oldStyle = document.querySelector("style#color-theme");
  if(oldStyle) {
    oldStyle.parentElement.removeChild(oldStyle);
  }
  document.getElementsByTagName('head')[0].appendChild(newStyle);
}

const themes = {
  darkTheme: darkTheme,
  lightTheme: lightTheme
};

export {
  updateColorThemeCss,
  colorThemeToCss,
  themes
}
