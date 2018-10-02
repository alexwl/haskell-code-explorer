import Ember from 'ember';

const directoryTreeToJsTree = function (packageId,directoryTree) {
  return directoryTree.contents.map((node) => {
    const jsTreeNode = {};
    jsTreeNode.text = node.name;
    jsTreeNode.data = node;
    if(node.path) {
      jsTreeNode.id = node.path;
      jsTreeNode.a_attr = {href:"/package/" + packageId + "/show/" + node.path};
    }
    if(node.tag === "Dir") {
      jsTreeNode.children = directoryTreeToJsTree(packageId,node);      
      jsTreeNode.state = {"opened" : containsHaskellModule(node)};
    } else {
      if(node.isHaskellModule) {
        jsTreeNode.icon = "/assets/haskell.ico";
        jsTreeNode.isHaskellModule = true;
      } else {
        jsTreeNode.icon = "jstree-file";
        jsTreeNode.isHaskellModule = false;
      }
    }
    return jsTreeNode;
  });
};

const containsHaskellModule = function(node) {  
  return node.contents.some((n) => {    
    if(n.tag === "File") {
      return n.isHaskellModule;
    } else {
      return containsHaskellModule(n);
    }
  });
}

export default Ember.Component.extend({
  query: null,
  didInsertElement : function () {
    this._super(...arguments);    
    const element = this.element.getElementsByClassName('file-tree')[0];
    
    const jstreeElement = Ember.$(element).jstree({
      'core' : {
        'data' : directoryTreeToJsTree(this.get('packageId'),this.get('directoryTree'))
      },
      "plugins" : [
        "search"
      ],
      "search": {
        "case_insensitive": true,
        "show_only_matches" : true,
        "show_only_matches_children": true
      }
    });
    
    jstreeElement.on("select_node.jstree",(event,data) => {
      const file = data.node.data;
      if(file.tag != "Dir") {
        this.sendAction('openFile',file.path);
      }
    });

    const jstree = jstreeElement.jstree(true);    
            
    if(this.get('currentFile')) {
      jstree.select_node(this.get('currentFile'));
      const node = jstree.get_node(this.get('currentFile'),true)[0];
      if(node) {
        node.scrollIntoView();
      }
    }
    this.jstree = jstree;
  },
  currentFileObserver : Ember.observer('currentFile',function() {
    Ember.run.next(() => {
      this.jstree.deselect_all();
      this.jstree.select_node(this.get('currentFile'));
    });
  }),
  queryObserver : Ember.observer('query',function() {
    if(this.get('query')) {
      this.jstree.search(this.get('query'));
    } else {
      this.jstree.clear_search();
    }
  }),
  actions : {
    hide() {      
      this.get('hide')();
    }
  }
});
