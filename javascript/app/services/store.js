import Ember from 'ember';
import RSVP from 'rsvp';
import {urls} from '../utils/api-urls';


//********************************************************************************
//https://coderwall.com/p/zrlulq/parsing-a-link-header-in-javascript
function unquote(value) {
  if (value.charAt(0) == '"' && value.charAt(value.length - 1) == '"') {
    return value.substring(1, value.length - 1);
  } else {
    return value;
  }
}

function parseLinkHeader(header) {
  if(!header) {return {}}
  var linkexp = /<[^>]*>\s*(\s*;\s*[^\(\)<>@,;:"\/\[\]\?={} \t]+=(([^\(\)<>@,;:"\/\[\]\?={} \t]+)|("[^"]*")))*(,|$)/g;
  var paramexp = /[^\(\)<>@,;:"\/\[\]\?={} \t]+=(([^\(\)<>@,;:"\/\[\]\?={} \t]+)|("[^"]*"))/g;

  var matches = header.match(linkexp);
  var rels = new Object();
  for (let i = 0; i < matches.length; i++) {
    var split = matches[i].split('>');
    var href = split[0].substring(1);
    var ps = split[1];
    var link = new Object();
    link.href = href;
    var s = ps.match(paramexp);
    for (let j = 0; j < s.length; j++) {
      var p = s[j];
      var paramsplit = p.split('=');
      var name = paramsplit[0];
      link[name] = unquote(paramsplit[1]);
    }

    if (link.rel != undefined) {
      rels[link.rel] = link;
    }
  }
  return rels;
}
//********************************************************************************


export default Ember.Service.extend({
  init() {    
    this.packages = {};
    this.files = {};
    this.haskellModules = {};
    this.definitionSites = {};
    this.modulePaths = {};
    this.expressions = {};
    this.references = {};
  },
  loadPackage(packageId) {
    const packageInfo = this.packages[packageId];
    if(packageInfo) {
      return new RSVP.Promise((resolve) => {resolve(packageInfo);});
    } else {
      const url = urls.packageInfoUrl(packageId);
      return Ember.$.getJSON(url).then((packageInfo) => {
        this.packages[packageId] = packageInfo;
        return packageInfo;
      });
    }
  },
  loadFile(packageId,filePath) {
    const fileId = packageId + "/" + filePath;
    const file = this.files[fileId];    
    if(file) {
      return new RSVP.Promise((resolve) => {resolve(file);});
    } else {
      const url = urls.fileUrl(packageId,filePath);      
      return Ember.$.get({url:url,dataType:"text"}).then((text) => {        
        const file = {};
        file.text = text;
        file.packageId = packageId;
        file.isHaskellModule = false;
        file.id = filePath;
        this.files[fileId] = file;
        return file;
      });
    }
  },
  loadHaskellModule(packageId,filePath) {    
    const moduleId = packageId + "/" + filePath ;
    const module = this.haskellModules[moduleId];
    if(module) {
      return new RSVP.Promise((resolve)=>{resolve(module);});
    } else {
      const url = urls.haskellModuleUrl(packageId,filePath);
      return Ember.$.getJSON(url).then((module) => {
        module.packageId = packageId;        
        module.isHaskellModule = true;
        this.haskellModules[moduleId] = module;
        return module;
      });
    }
  },
  loadDefinitionSite(packageId,moduleName,componentId,entity,name) {
    const id = packageId + "/"+ componentId + "/" + moduleName + "/" + entity + "/" + name;
    const definitionSite = this.definitionSites[id];
    if(definitionSite) {
      return new RSVP.Promise((resolve)=>{resolve(definitionSite);});
    } else {
      const url = urls.identifierDefinitionSiteUrl(packageId,moduleName,componentId,entity,name);
      return Ember.$.getJSON(url).then((definitionSite) => {
        this.definitionSites[id] = definitionSite;
        return definitionSite;
      });
    }
  },  
  loadExpressions(packageId,modulePath,lineStart,columnStart,lineEnd,columnEnd) {
    const id = packageId + "/" + encodeURIComponent(modulePath)
          + "/" + lineStart + "/" + columnStart + "/" + lineEnd + "/" + columnEnd;
    const exprs = this.expressions[id];
    if(exprs) {
      return new RSVP.Promise((resolve)=>{resolve(exprs);}); 
    } else {
      const url = urls.expressionsUrl(packageId,modulePath,lineStart,columnStart,lineEnd,columnEnd);      
      return Ember.$.getJSON(url).then((exprs) => {        
        this.expressions[id] = exprs;
        return exprs;
      });     
    }
  },
  loadFromUrlPaginated(url) {      
    return Ember.$.getJSON(url).then((items,textStatus,jqXHR) => {      
      const linkHeaderText = jqXHR.getResponseHeader('Link');
      const totalCountHeaderText = jqXHR.getResponseHeader('x-total-count');
      const linkHeader = parseLinkHeader(linkHeaderText);
      const total = parseInt(totalCountHeaderText);
      return {
        items:items,
        total:total,
        linkHeader:linkHeader
      };
    });
  }
});
