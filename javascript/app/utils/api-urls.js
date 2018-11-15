import config from '../config/environment';

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
    return config.APP.apiUrlPrefix + "/definitionSite/" + packageId+"/"+componentId+"/"+moduleName+"/"+entity+"/"+encodeURIComponent(name).replace(/\./g, '%2E');
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
    return config.APP.apiUrlPrefix + "/identifiers/"+packageId+"/"+encodeURIComponent(query).replace(/\./g, '%2E');
  },
  globalReferencesUrl : function (externalId) {
    return config.APP.apiUrlPrefix + "/globalReferences/"+encodeURIComponent(externalId);
  }
}
