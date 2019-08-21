import config from '../config/environment';

// "." and ".." is a special case because of the Path Segment Normalization:
// https://tools.ietf.org/html/rfc3986#section-6.2.2.3
// The segments “..” and “.” can be removed from a URL by a browser.
// https://stackoverflow.com/questions/3856693/a-url-resource-that-is-a-dot-2e
function fixDots(string) {
  if(string === ".") {
    return "%20%2E";
  }
  else if(string === "..")  {
    return "%20%2E%2E";
  } else {
    return string.replace(/\./g, '%2E');
  }
}

export const urls = {
  packageInfoUrl : function(packageId) {
    return config.APP.staticUrlPrefix+"/"+packageId+"/"+config.APP.haskellCodeExplorerDirectory+"/packageInfo.json";
  },
  fileUrl : function(packageId,filePath) {
    return config.APP.staticUrlPrefix+"/"+packageId+"/"+filePath;
  },
  haskellModuleUrl : function (packageId,filePath) {
    return config.APP.staticUrlPrefix+"/"+packageId+"/"+config.APP.haskellCodeExplorerDirectory+"/"+encodeURIComponent(encodeURIComponent(filePath))+ ".json";
  },
  packagesUrl : config.APP.apiUrlPrefix + "/packages",
  identifierDefinitionSiteUrl : function(packageId,moduleName,componentId,entity,name) {
    return config.APP.apiUrlPrefix + "/definitionSite/" + packageId+"/"+componentId+"/"+moduleName+"/"+entity+"/"+fixDots(encodeURIComponent(name));
  },
  modulePathUrl : function (packageId,moduleName,componentId) {
    return config.APP.apiUrlPrefix + "/modulePath/"+packageId+"/"+componentId+"/"+moduleName;
  },
  expressionsUrl : function (packageId,modulePath,lineStart,columnStart,lineEnd,columnEnd) {
    return config.APP.apiUrlPrefix + "/expressions/"+packageId+"/"+encodeURIComponent(modulePath) +"/"+lineStart+"/"+columnStart+"/"+lineEnd+"/"+columnEnd;
  },
  referencesUrl : function (packageId,externalId) {
    return config.APP.apiUrlPrefix + "/references/"+packageId+"/"+encodeURIComponent(externalId);
  },
  identifierSearchUrl : function (packageId,query) {
    return config.APP.apiUrlPrefix + "/identifiers/"+packageId+"/"+fixDots(encodeURIComponent(query));
  },
  globalReferencesUrl : function (externalId) {
    return config.APP.apiUrlPrefix + "/globalReferences/"+encodeURIComponent(externalId);
  },
  globalIdentifiersUrl : function (query) {
    return config.APP.apiUrlPrefix + "/globalIdentifiers/"+fixDots(encodeURIComponent(query));
  },
  hoogleDocsUrl : function (packageId,moduleName,entity,name) {
    return config.APP.apiUrlPrefix + "/hoogleDocs/"+packageId+"/"+encodeURIComponent(moduleName)+"/"+entity+"/"+fixDots(encodeURIComponent(name));
  }
}
