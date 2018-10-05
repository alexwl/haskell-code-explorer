function exactLocationToUrl(exactLocation) {
  const modulePath = exactLocation.modulePath;
  const packageId = exactLocation.packageId.name + "-" + exactLocation.packageId.version;
  let hash = "";
  if(exactLocation.startLine != 1) {
    hash = "#L" + exactLocation.startLine;
  }
  return "/package/"+packageId+"/show/"+modulePath+hash;
}

function hackageUrl(packageId,locationInfo) {
  let hash = "";
  if (locationInfo.entity !== "Mod") {
    hash = "#" + encodeURIComponent(locationInfo.name);
  }
  return "https://hackage.haskell.org/package/"+packageId+"/docs/src/"+locationInfo.moduleName+".html"+hash;
}

function openUrl(buttonId,url) {
  if(buttonId === 2) {//middle mouse button
    window.open(url, '_blank');
  } else if(buttonId == 1) {//left mouse button
    window.location = url;
  }
  return false;
}

function saveCurrentLocation(currentLineNumber) {  
  if(currentLineNumber) {
    const url = window.location.origin + window.location.pathname + "#L" + currentLineNumber;    
    if(location.href != url) {      
      window.location.hash = "#L" + currentLineNumber;
    }
  }
}

function goToDefinition(store,locationInfo,buttonId,currentLineNumber) {
  if(locationInfo.tag === "ExactLocation") {
    const url = exactLocationToUrl(locationInfo);
    if(locationInfo.startLine !== currentLineNumber) {
      saveCurrentLocation(currentLineNumber);
    }
    openUrl(buttonId,url);
  } else if(locationInfo.tag === "ApproximateLocation") {    
    const packageId = locationInfo.packageId.name+"-"+locationInfo.packageId.version;    
    if(locationInfo.entity === "Mod") {
      store.loadDefinitionSite(packageId,
                               locationInfo.moduleName,
                               locationInfo.componentId,
                               locationInfo.entity,
                               locationInfo.moduleName)
        .then((defSite) => {
          const packageId = defSite.location.packageId.name + "-" + defSite.location.packageId.version;
          openUrl(buttonId,"/package/" + packageId + "/show/" + defSite.location.modulePath);
        }).catch(() => {
          openUrl(buttonId,hackageUrl(packageId,locationInfo));
        });      
    } else {
    store.loadDefinitionSite(packageId,
                            locationInfo.moduleName,
                            locationInfo.componentId,
                            locationInfo.entity,
                            locationInfo.name)
      .then((definitionSite) => {
        if(definitionSite.location.tag === "ExactLocation") {
          const url = exactLocationToUrl(definitionSite.location);
          if(locationInfo.startLine !== currentLineNumber) {
            saveCurrentLocation(currentLineNumber);
          }
          openUrl(buttonId,url);
        } else {
          saveCurrentLocation(currentLineNumber);
          openUrl(buttonId,hackageUrl(packageId,locationInfo));
        }
      }).catch((e) => {
        console.log(e);
        saveCurrentLocation(currentLineNumber);
        openUrl(buttonId,hackageUrl(packageId,locationInfo));
      });
    }    
  } else {
    alert('No location info');
  }  
}

export {
  goToDefinition,openUrl
}
