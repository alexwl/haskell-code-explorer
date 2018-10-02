/* eslint-env node */
'use strict';

const packages = [
  {
    "versions": [
      "0.1.0.0"
    ],
    "name": "test-package"
  }
];

const testPackage = {
  "directoryTree": {
    "tag": "Dir",
    "contents": [
      {
        "tag": "File",
        "path": "Setup.hs",
        "isHaskellModule": false,
        "name": "Setup.hs"
      },
      {
        "tag": "File",
        "path": "stack-8.0.2.yaml",
        "isHaskellModule": false,
        "name": "stack-8.0.2.yaml"
      },
      {
        "tag": "File",
        "path": "stack.yaml",
        "isHaskellModule": false,
        "name": "stack.yaml"
      },
      {
        "tag": "Dir",
        "contents": [
          {
            "tag": "File",
            "path": "src/Lib.hs",
            "isHaskellModule": true,
            "name": "Lib.hs"
          },
          {
            "tag": "File",
            "path": "src/Types.hs",
            "isHaskellModule": true,
            "name": "Types.hs"
          }
        ],
        "name": "src"
      },
      {
        "tag": "Dir",
        "contents": [
          {
            "tag": "File",
            "path": "app/Main.hs",
            "isHaskellModule": true,
            "name": "Main.hs"
          }
        ],
        "name": "app"
      },
      {
        "tag": "Dir",
        "contents": [
          {
            "tag": "File",
            "path": "test/Spec.hs",
            "isHaskellModule": true,
            "name": "Spec.hs"
          }
        ],
        "name": "test"
      },
      {
        "tag": "File",
        "path": "package.yaml",
        "isHaskellModule": false,
        "name": "package.yaml"
      },
      {
        "tag": "File",
        "path": "test-package.cabal",
        "isHaskellModule": false,
        "name": "test-package.cabal"
      }
    ],
    "name": "test-package"
  },
  "modules": {
    "app/Main.hs": [],
    "src/Types.hs": [],
    "test/Spec.hs": [],
    "src/Lib.hs": []
  },
  "id": "test-package-0.1.0.0"
};

const testModuleInfo = {
  "occurrences": {
    "3-8-11": {
      "sort": {
        "tag": "ModuleId",
        "contents": {
          "packageId": {
            "name": "test-package",
            "version": "0.1.0.0"
          },
          "tag": "ApproximateLocation",
          "moduleName": "Lib",
          "name": "Lib",
          "componentId": "exe-test-package-exe",
          "entity": "Mod"
        }
      },
      "description": "ImportDecl"
    },
    "6-8-16": {
      "internalId": "4",
      "sort": {
        "tag": "ValueId"
      },
      "description": "HsVar"
    },
    "5-1-5": {
      "internalId": "0",
      "sort": {
        "tag": "ValueId"
      },
      "description": "TypeSig"
    },
    "5-9-11": {
      "internalId": "2",
      "sort": {
        "tag": "TypeId"
      },
      "description": "HsTyVar"
    },
    "6-1-5": {
      "isBinder": true,
      "internalId": "0",
      "sort": {
        "tag": "ValueId"
      },
      "description": "Match"
    },
    "5-12-14": {
      "internalId": "3",
      "sort": {
        "tag": "TypeId"
      },
      "description": "HsTupleTy"
    }
  },
  "identifiers": {
    "7": {
      "isExported": false,
      "idType": {
        "components": [
          {
            "tag": "TyCon",
            "name": "RuntimeRep",
            "internalId": "6"
          }
        ]
      },
      "locationInfo": {
        "packageId": {
          "name": "ghc-prim",
          "version": "0.5.1.1"
        },
        "tag": "ApproximateLocation",
        "haddockAnchorId": "LiftedRep",
        "moduleName": "GHC.Types",
        "name": "LiftedRep",
        "componentId": "lib",
        "entity": "Val"
      },
      "nameSpace": "DataName",
      "internalId": "7",
      "sort": "External",
      "occName": "LiftedRep",
      "externalId": "ghc-prim-0.5.1.1|GHC.Types|Val|LiftedRep",
      "demangledOccName": "LiftedRep"
    },
    "0": {
      "isExported": true,
      "idType": {
        "components": [
          {
            "tag": "TyCon",
            "name": "IO",
            "internalId": "2"
          },
          {
            "tag": "Text",
            "contents": " ()"
          }
        ]
      },
      "locationInfo": {
        "packageId": {
          "name": "test-package",
          "version": "0.1.0.0"
        },
        "tag": "ExactLocation",
        "moduleName": "Main",
        "startLine": 6,
        "endLine": 6,
        "modulePath": "app/Main.hs",
        "startColumn": 1,
        "endColumn": 5
      },
      "nameSpace": "VarName",
      "internalId": "0",
      "details": "VanillaId",
      "sort": "External",
      "occName": "main",
      "externalId": "test-package-0.1.0.0|Main|Val|main",
      "demangledOccName": "main"
    },
    "4": {
      "isExported": false,
      "idType": {
        "components": [
          {
            "tag": "TyCon",
            "name": "IO",
            "internalId": "2"
          },
          {
            "tag": "Text",
            "contents": " ()"
          }
        ]
      },
      "doc": "<p><span>someFunc documentation</span></p>",
      "locationInfo": {
        "packageId": {
          "name": "test-package",
          "version": "0.1.0.0"
        },
        "tag": "ExactLocation",
        "moduleName": "Lib",
        "startLine": 9,
        "endLine": 9,
        "modulePath": "src/Lib.hs",
        "startColumn": 1,
        "endColumn": 9
      },
      "nameSpace": "VarName",
      "internalId": "4",
      "details": "VanillaId",
      "sort": "External",
      "occName": "someFunc",
      "externalId": "test-package-0.1.0.0|Lib|Val|someFunc",
      "demangledOccName": "someFunc"
    },
    "2": {
      "isExported": false,
      "idType": {
        "components": [
          {
            "tag": "Text",
            "contents": "* -> *"
          }
        ]
      },
      "locationInfo": {
        "packageId": {
          "name": "ghc-prim",
          "version": "0.5.1.1"
        },
        "tag": "ApproximateLocation",
        "haddockAnchorId": "IO",
        "moduleName": "GHC.Types",
        "name": "IO",
        "componentId": "lib",
        "entity": "Typ"
      },
      "nameSpace": "TcClsName",
      "internalId": "2",
      "sort": "External",
      "occName": "IO",
      "externalId": "ghc-prim-0.5.1.1|GHC.Types|Typ|IO",
      "demangledOccName": "IO"
    },
    "5": {
      "isExported": false,
      "idType": {
        "components": [
          {
            "tag": "TyCon",
            "name": "RuntimeRep",
            "internalId": "6"
          },
          {
            "tag": "Text",
            "contents": " -> *"
          }
        ]
      },
      "locationInfo": {
        "packageId": {
          "name": "ghc-prim",
          "version": "0.5.1.1"
        },
        "tag": "ApproximateLocation",
        "haddockAnchorId": "TYPE",
        "moduleName": "GHC.Prim",
        "name": "TYPE",
        "componentId": "lib",
        "entity": "Typ"
      },
      "nameSpace": "TcClsName",
      "internalId": "5",
      "sort": "External",
      "occName": "TYPE",
      "externalId": "ghc-prim-0.5.1.1|GHC.Prim|Typ|TYPE",
      "demangledOccName": "TYPE"
    },
    "3": {
      "isExported": false,
      "idType": {
        "components": [
          {
            "tag": "Text",
            "contents": "*"
          }
        ]
      },
      "locationInfo": {
        "packageId": {
          "name": "ghc-prim",
          "version": "0.5.1.1"
        },
        "tag": "ApproximateLocation",
        "haddockAnchorId": "-40--41-",
        "moduleName": "GHC.Tuple",
        "name": "()",
        "componentId": "lib",
        "entity": "Typ"
      },
      "nameSpace": "TcClsName",
      "internalId": "3",
      "sort": "External",
      "occName": "()",
      "externalId": "ghc-prim-0.5.1.1|GHC.Tuple|Typ|()",
      "demangledOccName": "()"
    }
  },
  "name": "Main",
  "sourceCodeHtml": "<table class=\"source-code\"><tbody><tr><td class=\"line-number\" id=\"LN1\">1</td><td class=\"line-content\" data-line=\"1\" id=\"LC1\"><span data-start=\"1\" data-end=\"18\">module Main where</span></td></tr><tr><td class=\"line-number\" id=\"LN2\">2</td><td class=\"line-content\" data-line=\"2\" id=\"LC2\"><span data-start=\"1\" data-end=\"1\"></span></td></tr><tr><td class=\"line-number\" id=\"LN3\">3</td><td class=\"line-content\" data-line=\"3\" id=\"LC3\"><span data-start=\"1\" data-end=\"8\">import </span><span class=\"identifier\" id=\"\" data-occurrence=\"3-8-11\" data-identifier=\"\" data-start=\"8\" data-end=\"11\">Lib</span></td></tr><tr><td class=\"line-number\" id=\"LN4\">4</td><td class=\"line-content\" data-line=\"4\" id=\"LC4\"><span data-start=\"1\" data-end=\"1\"></span></td></tr><tr><td class=\"line-number\" id=\"LN5\">5</td><td class=\"line-content\" data-line=\"5\" id=\"LC5\"><span class=\"identifier\" id=\"1\" data-occurrence=\"5-1-5\" data-identifier=\"0\" data-start=\"1\" data-end=\"5\">main</span><span data-start=\"5\" data-end=\"9\"> :: </span><span class=\"identifier\" id=\"2\" data-occurrence=\"5-9-11\" data-identifier=\"2\" data-start=\"9\" data-end=\"11\">IO</span><span data-start=\"11\" data-end=\"12\"> </span><span class=\"identifier\" id=\"3\" data-occurrence=\"5-12-14\" data-identifier=\"3\" data-start=\"12\" data-end=\"14\">()</span></td></tr><tr><td class=\"line-number\" id=\"LN6\">6</td><td class=\"line-content\" data-line=\"6\" id=\"LC6\"><span class=\"identifier\" id=\"1\" data-occurrence=\"6-1-5\" data-identifier=\"0\" data-start=\"1\" data-end=\"5\">main</span><span data-start=\"5\" data-end=\"8\"> = </span><span class=\"identifier\" id=\"4\" data-occurrence=\"6-8-16\" data-identifier=\"4\" data-start=\"8\" data-end=\"16\">someFunc</span></td></tr><tr><td class=\"line-number\" id=\"LN7\">7</td><td class=\"line-content\" data-line=\"7\" id=\"LC7\"><span data-start=\"1\" data-end=\"1\"></span></td></tr><tr><td class=\"line-number\" id=\"LN8\">8</td><td class=\"line-content\" data-line=\"8\" id=\"LC8\"><span data-start=\"1\" data-end=\"1\"></span></td></tr></tbody></table>",
  "id": "app/Main.hs",
  "declarations": [
    {
      "isExported": true,
      "lineNumber": 6,
      "declType": {
        "components": [
          {
            "tag": "TyCon",
            "name": "IO",
            "internalId": "2"
          },
          {
            "tag": "Text",
            "contents": " ()"
          }
        ]
      },
      "name": "main",
      "sort": "ValD"
    }
  ]
};

module.exports = function(app) {
  const express = require('express');
  let packagesRouter = express.Router();
  
  packagesRouter.get('/api/packages', function(req, res) {    
    res.send(packages);
  });  
  
  packagesRouter.get('/files/test-package-0.1.0.0/.haskell-code-explorer/packageInfo.json', function(req, res) {
    res.send(testPackage);
  });
  
  packagesRouter.get('/files/test-package-0.1.0.0/.haskell-code-explorer/app%252FMain.hs.json', function(req, res) {
    res.send(testModuleInfo);
  });

  app.use('/', packagesRouter);
};
