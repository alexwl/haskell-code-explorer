{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}

module Main where

import Control.Exception (try)
import Control.Monad.Logger (runLoggingT)
import qualified Data.ByteString as BS
import qualified Data.Generics.Uniplate.Data as U
import qualified Data.HashMap.Strict as HM
import qualified Data.IntMap as IM
import qualified Data.IntervalMap.Strict as IVM
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import Data.Version
import HaskellCodeExplorer.AST.TypecheckedSource (removeOverlappingInterval)
import HaskellCodeExplorer.PackageInfo
import HaskellCodeExplorer.Preprocessor
import HaskellCodeExplorer.Types
import qualified HaskellCodeExplorer.Types as HCE
import System.Directory
  ( findExecutable
  , getCurrentDirectory
  , withCurrentDirectory
  )
import System.FilePath ((</>))
import System.Process (readProcess)
import Test.Hspec

testPackageDir :: FilePath
testPackageDir = "test/test-package"

main :: IO ()
main = do
  currentDir <- getCurrentDirectory
  hspec $ do
    packageInfoSpec currentDir
    sourceCodeTransformationSpec currentDir
    tokenizeSpec
    removeOverlappingIntervalSpec

packageInfoSpec :: FilePath -> Spec
packageInfoSpec currentDir = do
  eitherPackageInfo <- runIO $ buildAndIndexTestPackage currentDir
  case eitherPackageInfo of
    Right packageInfo -> do
      describe "createPackageInfo" $ do
        it "returns valid package id" $
          HCE.id (packageInfo :: PackageInfo ModuleInfo) `shouldBe`
          PackageId "test-package" (Version [0, 1, 0, 0] [])
        it "returns valid list of module paths" $ do
          let paths =
                HM.fromList
                  [ ( HaskellModulePath {getHaskellModulePath = "app/Main.hs"}
                    , ())
                  , ( HaskellModulePath {getHaskellModulePath = "src/Types.hs"}
                    , ())
                  , ( HaskellModulePath {getHaskellModulePath = "test/Spec.hs"}
                    , ())
                  , ( HaskellModulePath {getHaskellModulePath = "src/Lib.hs"}
                    , ())
                  ]
          (HM.map (const ()))
            (HCE.moduleMap (packageInfo :: PackageInfo ModuleInfo)) `shouldBe`
            paths
        it "returns valid list of module names" $ do
          let names =
                HM.fromList
                  [ ( HaskellModuleName {getHaskellModuleName = "Types"}
                    , HM.fromList
                        [ ( ComponentId {getComponentId = "lib"}
                          , HaskellModulePath
                              {getHaskellModulePath = "src/Types.hs"})
                        ])
                  , ( HaskellModuleName {getHaskellModuleName = "Main"}
                    , HM.fromList
                        [ ( ComponentId
                              {getComponentId = "exe-test-package-exe"}
                          , HaskellModulePath
                              {getHaskellModulePath = "app/Main.hs"})
                        , ( ComponentId
                              {getComponentId = "test-test-package-test"}
                          , HaskellModulePath
                              {getHaskellModulePath = "test/Spec.hs"})
                        ])
                  , ( HaskellModuleName {getHaskellModuleName = "Lib"}
                    , HM.fromList
                        [ ( ComponentId {getComponentId = "lib"}
                          , HaskellModulePath
                              {getHaskellModulePath = "src/Lib.hs"})
                        ])
                  ]
          (HCE.moduleNameMap (packageInfo :: PackageInfo ModuleInfo)) `shouldBe`
            names
      let mbModuleInfo =
            HM.lookup
              (HCE.HaskellModulePath "src/Lib.hs")
              (moduleMap (packageInfo :: HCE.PackageInfo HCE.ModuleInfo))
      case mbModuleInfo of
        Just modInfo -> moduleInfoSpec modInfo
        Nothing -> return ()
    Left e -> runIO $ putStrLn e >> return ()
  
moduleInfoSpec :: ModuleInfo -> Spec
moduleInfoSpec modInfo =
  describe "createModuleInfo" $ do
    it "returns valid module name" $
      HCE.name (modInfo :: HCE.ModuleInfo) `shouldBe`
      HCE.HaskellModuleName "Lib"
    it "returns valid list of declarations " $
      HCE.declarations (modInfo :: HCE.ModuleInfo) `shouldBe` testDeclarations
    it "returns valid source code " $ do
      let sourceCodeLines =
            V.fromList
              [ "module Lib"
              , "    ( someFunc"
              , "    ) where"
              , ""
              , "import Types(Test(..))"
              , ""
              , "-- | someFunc documentation"
              , "someFunc :: IO ()"
              , "someFunc = putStrLn \"someFunc\""
              , ""
              , "-- | mkTest documentation"
              , "mkTest :: Int -> Test"
              , "mkTest i = Test i"
              , ""
              ]
      HCE.source (modInfo :: HCE.ModuleInfo) `shouldBe` sourceCodeLines
    it "returns valid map of expressions" $
      HCE.exprInfoMap (modInfo :: HCE.ModuleInfo) `shouldBe` testExprInfoMap
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)      
    it "returns valid map of identifiers " $
      let removeLocationInfo :: HCE.LocationInfo -> HCE.LocationInfo
          removeLocationInfo _ = HCE.UnknownLocation ""
          removePackageVersionFromExternalId :: HCE.ExternalId -> HCE.ExternalId
          removePackageVersionFromExternalId extId@(HCE.ExternalId textId) = case T.splitOn "|" textId of
            packageId:rest -> case T.splitOn "-" packageId of
              packageIdParts@(_:_) -> HCE.ExternalId $ T.intercalate "|" ((T.intercalate "-" (init packageIdParts)) : rest)
              _ -> extId
            _ ->  extId
          cleanup :: HCE.IdentifierInfoMap -> HCE.IdentifierInfoMap
          cleanup = U.transformBi removeLocationInfo . U.transformBi removePackageVersionFromExternalId
       in 
        cleanup (HCE.idInfoMap (modInfo :: HCE.ModuleInfo)) `shouldBe` cleanup testIdInfoMap
#endif          
    it "returns valid map of identifier occurrences" $
      HCE.idOccMap (modInfo :: HCE.ModuleInfo) `shouldBe` testIdOccMap

stackYamlArg :: [String]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,4,0)
stackYamlArg = []
#elif MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
stackYamlArg = ["--stack-yaml=stack-8.6.3.yaml"]
#elif MIN_VERSION_GLASGOW_HASKELL(8,4,4,0)
stackYamlArg = ["--stack-yaml=stack-8.4.4.yaml"]
#elif MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
stackYamlArg = ["--stack-yaml=stack-8.4.3.yaml" ]
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
stackYamlArg = ["--stack-yaml=stack-8.2.2.yaml" ]
#else
stackYamlArg = ["--stack-yaml=stack-8.0.2.yaml" ]
#endif

buildAndIndexTestPackage ::
     FilePath -> IO (Either String (PackageInfo ModuleInfo))
buildAndIndexTestPackage currentDir = do
  mbStackExecutable <- findExecutable "stack"
  case mbStackExecutable of
    Just stackExecutable -> do
      let removeEndOfLine str
            | null str = str
            | otherwise = init str
      (eitherDistDir :: Either IOError String) <-
        try .
        fmap removeEndOfLine .
        readProcess stackExecutable (["path", "--dist-dir"] ++ stackYamlArg) $
        ""
      case eitherDistDir of
        Right distDir -> do
          packageInfo <-
            let testPackageDirectoryPath = currentDir </> testPackageDir
             in withCurrentDirectory testPackageDirectoryPath $ do
                  _ <-
                    readProcess
                      stackExecutable
                      (["build", "--test","--force-dirty"] ++ stackYamlArg)
                      ""
                  runLoggingT
                    (createPackageInfo
                       testPackageDirectoryPath
                       (Just distDir)
                       HCE.BeforePreprocessing
                       []
                       [])
                    (\_ _ _ _ -> return ())
          return . Right $ packageInfo
        Left ex -> return . Left $ show ex
    Nothing ->
      return . Left $
      "Cannot find stack executable. Stack executable is required to build the test package."
    
sourceCodeTransformationSpec :: FilePath -> Spec
sourceCodeTransformationSpec currentDir = do
  sourceCodeAfterPreprocessor <-
    runIO $ BS.readFile $ currentDir </> "test/data/FileAfterPreprocessor.hs"
  let sourceCodeTransformation =
        fst $
        createSourceCodeTransformation
          (HaskellModulePath "File.hs")
          (TE.decodeUtf8 sourceCodeAfterPreprocessor)
          (TE.decodeUtf8 sourceCodeAfterPreprocessor)
  describe "createSourceCodeTransformation" $ do
    it "returns valid list of pragmas" $ do
      let pragmas =
            S.fromList
              [ LinePragma (HaskellFilePath "File1.hs") 8 1
              , LinePragma (HaskellFilePath "File1.hs") 11 14
              , LinePragma (HaskellFilePath "File2.hs") 12 1
              , LinePragma (HaskellFilePath "File1.hs") 18 15
              , LinePragma (HaskellFilePath "File.hs") 21 9
              , LinePragma (HaskellFilePath "File.hs") 23 18
              , LinePragma (HaskellFilePath "File3.hs") 26 1
              , LinePragma (HaskellFilePath "File.hs") 30 21
              ]
      linePragmas sourceCodeTransformation `shouldBe` pragmas
    it "returns valid file index" $
      let index =
            HM.fromList
              [ ( HaskellFilePath {getHaskellFilePath = "File1.hs"}
                , S.fromList
                    [ FileLocation {lineStart = 1, lineEnd = 2, offset = 8}
                    , FileLocation {lineStart = 15, lineEnd = 16, offset = 4}
                    ])
              , ( HaskellFilePath {getHaskellFilePath = "File2.hs"}
                , S.fromList
                    [FileLocation {lineStart = 1, lineEnd = 5, offset = 12}])
              , ( HaskellFilePath {getHaskellFilePath = "File3.hs"}
                , S.fromList
                    [FileLocation {lineStart = 1, lineEnd = 3, offset = 26}])
              , ( HaskellFilePath {getHaskellFilePath = "File.hs"}
                , S.fromList
                    [ FileLocation {lineStart = 1, lineEnd = 8, offset = 0}
                    , FileLocation {lineStart = 9, lineEnd = 9, offset = 13}
                    , FileLocation {lineStart = 18, lineEnd = 19, offset = 6}
                    , FileLocation {lineStart = 21, lineEnd = 21, offset = 10}
                    ])
              ]
       in fileIndex sourceCodeTransformation `shouldBe` index
  describe "fromOriginalLineNumber" $ do
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File.hs", 1) (Right 1)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File.hs", 4) (Right 4)    
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File1.hs", 1) (Right 9)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File1.hs", 2) (Right 10)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File2.hs", 1) (Right 13)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File2.hs", 3) (Right 15)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File2.hs", 5) (Right 17)    
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File1.hs", 15) (Right 19)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File1.hs", 16) (Right 20)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File3.hs", 1) (Right 27)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File3.hs", 2) (Right 28)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File3.hs", 3) (Right 29)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File.hs", 9) (Right 22)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File.hs", 18) (Right 24)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File.hs", 19) (Right 25)
    test fromOriginalLineNumber sourceCodeTransformation (HaskellFilePath "File.hs", 21) (Right 31)

test ::
     forall a t t1. (Show t1, Show t, Show a, Eq a)
  => (t1 -> t -> a)
  -> t1
  -> t
  -> a
  -> Spec
test fun arg1 arg2 result =
  it (show arg1 ++ " " ++ show arg2) $ fun arg1 arg2 `shouldBe` result

tokenizeSpec :: Spec
tokenizeSpec =
  describe "tokenize" $ do
    test tokenize "" ([] :: [((Int, Int), String)]) []
    test
      tokenize
      "--comment"
      ([] :: [((Int, Int), String)])
      [("--comment", (1, 10), Nothing)]
    test
      tokenize
      ("abcd" :: T.Text)
      [((1, 5), "abcdIdentifier")]
      [("abcd", (1, 5), Just "abcdIdentifier")]
    test
      tokenize
      ("data Test" :: T.Text)
      [((6, 10), "TestIdentifier")]
      [("data ", (1, 6), Nothing), ("Test", (6, 10), Just "TestIdentifier")]
    test
      tokenize
      ("abc = xyz" :: T.Text)
      [((1, 4), "abcIdentifier"), ((7, 10), "xyzIdentifier")]
      [ ("abc", (1, 4), Just "abcIdentifier")
      , (" = ", (4, 7), Nothing)
      , ("xyz", (7, 10), Just "xyzIdentifier")
      ]
    test
      tokenize
      ("abc = xyz --comment" :: T.Text)
      [((1, 4), "abcIdentifier"), ((7, 10), "xyzIdentifier")]
      [ ("abc", (1, 4), Just "abcIdentifier")
      , (" = ", (4, 7), Nothing)
      , ("xyz", (7, 10), Just "xyzIdentifier")
      , (" --comment", (10, 20), Nothing)
      ]
    test
      tokenize
      ("   abc = xyz --comment" :: T.Text)
      [((4, 7), "abcIdentifier"), ((10, 13), "xyzIdentifier")]
      [ ("   ", (1, 4), Nothing)
      , ("abc", (4, 7), Just "abcIdentifier")
      , (" = ", (7, 10), Nothing)
      , ("xyz", (10, 13), Just "xyzIdentifier")
      , (" --comment", (13, 23), Nothing)
      ]

removeOverlappingIntervalSpec :: Spec
removeOverlappingIntervalSpec =
  describe "removeOverlappingInterval" $ do
    test removeOverlappingInterval [((1, 2), "a")] [] [((1, 2), "a")]
    test
      removeOverlappingInterval
      [((3, 4), "b")]
      [((1, 2), "a")]
      [((1, 2), "a"), ((3, 4), "b")]
    test
      removeOverlappingInterval
      [((2, 3), "b")]
      [((1, 5), "a")]
      [((2, 3), "b")]
    test
      removeOverlappingInterval
      [((1, 5), "b")]
      [((2, 3), "a")]
      [((2, 3), "a")]
    test
      removeOverlappingInterval
      [((1, 5), "b")]
      [((2, 7), "a")]
      [((1, 5), "b")]
    test
      removeOverlappingInterval
      [((1, 3), "b")]
      [((1, 3), "a")]
      [((1, 3), "a")]

testDeclarations :: [Declaration]
testDeclarations =
  [ Declaration
      { sort = ValD
      , name = "someFunc"
      , declType =
          Just
            (Type
               { components =
                   [ TyCon {internalId = HCE.InternalId "0", name = "IO"}
                   , Text " ()"
                   ]
               , componentsExpanded = Nothing
               })
      , isExported = True
      , lineNumber = 9
      }
  , Declaration
      { sort = ValD
      , name = "mkTest"
      , declType =
          Just
            (Type
               { components =
                   [ TyCon {internalId = HCE.InternalId "9", name = "Int"}
                   , Text " -> "
                   , TyCon {internalId = HCE.InternalId "1", name = "Test"}
                   ]
               , componentsExpanded = Nothing
               })
      , isExported = False
      , lineNumber = 13
      }
  ]

testExprInfoMap :: IVM.IntervalMap (Int,Int) HCE.ExpressionInfo
testExprInfoMap =
  IVM.fromList
    [ ( IVM.OpenInterval (9, 12) (9, 31)
      , ExpressionInfo
          { description = "HsApp"
          , exprType =
              Just
                (Type
                   { components =
                       [ TyCon {internalId = InternalId {getInternalId = "0"}, name = "IO"}
                       , Text " ()"
                       ]
                   , componentsExpanded = Nothing
                   })
          })
    , ( IVM.OpenInterval (13, 12) (13, 18)
      , ExpressionInfo
          { description = "HsApp"
          , exprType =
              Just
                (Type
                   { components =
                       [ TyCon
                           {internalId = InternalId {getInternalId = "1"}, name = "Test"}
                       ]
                   , componentsExpanded = Nothing
                   })
          })
    ]


testIdOccMap :: IM.IntMap [((Int, Int), IdentifierOccurrence)]
testIdOccMap =
  IM.fromList
    [ ( 2
      , [ ( (7, 15)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "2"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "3"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "IE"
              , sort = ValueId
              })
        ])
    , ( 5
      , [ ( (8, 13)
          , IdentifierOccurrence
              { internalId = Nothing
              , internalIdFromRenamedSource = Nothing
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "ImportDecl"
              , sort =
                  ModuleId
                    (ExactLocation
                       { packageId =
                           PackageId
                             { name = "test-package"
                             , version =
                                 Version
                                   { versionBranch = [0, 1, 0, 0]
                                   , versionTags = []
                                   }
                             }
                       , modulePath =
                           HaskellModulePath
                             {getHaskellModulePath = "src/Types.hs"}
                       , moduleName =
                           HaskellModuleName {getHaskellModuleName = "Types"}
                       , startLine = 1
                       , endLine = 1
                       , startColumn = 1
                       , endColumn = 1
                       })
              })
        , ( (14, 18)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "1"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "1"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "IE"
              , sort = TypeId
              })
        ])
    , ( 8
      , [ ( (1, 9)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "2"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "3"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "TypeSig"
              , sort = ValueId
              })
        , ( (13, 15)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "0"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "0"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "HsTyVar"
              , sort = TypeId
              })
        , ( (16, 18)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "4"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "4"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "HsTupleTy"
              , sort = TypeId
              })
        ])
    , ( 9
      , [ ( (1, 9)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "2"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "3"})
              , isBinder = True
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "Match"
              , sort = ValueId
              })
        , ( (12, 20)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "5"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "5"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "HsVar"
              , sort = ValueId
              })
        , ( (21, 31)
          , IdentifierOccurrence
              { internalId = Nothing
              , internalIdFromRenamedSource = Nothing
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType =
                  Just
                    (Type
                       { components =
                           [ Text "["
                           , TyCon
                               { internalId = InternalId {getInternalId = "6"}
                               , name = "Char"
                               }
                           , Text "]"
                           ]
                       , componentsExpanded = Nothing
                       })
              , typeArguments = Nothing
              , description = "HsLit"
              , sort = ValueId
              })
        ])
    , ( 12
      , [ ( (1, 7)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "7"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "8"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "TypeSig"
              , sort = ValueId
              })
        , ( (11, 14)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "9"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "9"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "HsTyVar"
              , sort = TypeId
              })
        , ( (18, 22)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "1"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "1"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "HsTyVar"
              , sort = TypeId
              })
        ])
    , ( 13
      , [ ( (1, 7)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "7"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "8"})
              , isBinder = True
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "Match"
              , sort = ValueId
              })
        , ( (8, 9)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "10"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "11"})
              , isBinder = True
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "VarPat"
              , sort = ValueId
              })
        , ( (12, 16)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "12"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "13"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "HsVar"
              , sort = ValueId
              })
        , ( (17, 18)
          , IdentifierOccurrence
              { internalId = Just (InternalId {getInternalId = "10"})
              , internalIdFromRenamedSource =
                  Just (InternalId {getInternalId = "11"})
              , isBinder = False
              , instanceResolution = Nothing
              , idOccType = Nothing
              , typeArguments = Nothing
              , description = "HsVar"
              , sort = ValueId
              })
        ])
    ]
  
testIdInfoMap :: HM.HashMap InternalId IdentifierInfo
testIdInfoMap =
  HM.fromList
    [ ( InternalId {getInternalId = "7"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "mkTest"}
          , demangledOccName = "mkTest"
          , nameSpace = VarName
          , locationInfo =
              ExactLocation
                { packageId =
                    PackageId
                      { name = "test-package"
                      , version =
                          Version
                            {versionBranch = [0, 1, 0, 0], versionTags = []}
                      }
                , modulePath =
                    HaskellModulePath {getHaskellModulePath = "src/Lib.hs"}
                , moduleName = HaskellModuleName {getHaskellModuleName = "Lib"}
                , startLine = 13
                , endLine = 13
                , startColumn = 1
                , endColumn = 7
                }
          , idType =
              Type
                { components =
                    [ TyCon
                        { internalId = InternalId {getInternalId = "9"}
                        , name = "Int"
                        }
                    , Text " -> "
                    , TyCon
                        { internalId = InternalId {getInternalId = "1"}
                        , name = "Test"
                        }
                    ]
                , componentsExpanded = Nothing
                }
          , details = Just VanillaId
          , doc = Just "<p><span>mkTest documentation</span></p>"
          , internalId = InternalId {getInternalId = "7"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "test-package-0.1.0.0|Lib|Val|mkTest"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "14"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "TYPE"}
          , demangledOccName = "TYPE"
          , nameSpace = TcClsName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "ghc-prim"
                      , version =
                          Version
                            {versionBranch = [0, 5, 1, 1], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Prim"}
                , entity = Typ
                , name = "TYPE"
                , haddockAnchorId = Just "TYPE"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type
                { components =
                    [ TyCon
                        { internalId = InternalId {getInternalId = "15"}
                        , name = "RuntimeRep"
                        }
                    , Text " -> *"
                    ]
                , componentsExpanded = Nothing
                }
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "14"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "ghc-prim-0.5.1.1|GHC.Prim|Typ|TYPE"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "0"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "IO"}
          , demangledOccName = "IO"
          , nameSpace = TcClsName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "ghc-prim"
                      , version =
                          Version
                            {versionBranch = [0, 5, 1, 1], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Types"}
                , entity = Typ
                , name = "IO"
                , haddockAnchorId = Just "IO"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type {components = [Text "* -> *"], componentsExpanded = Nothing}
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "0"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "ghc-prim-0.5.1.1|GHC.Types|Typ|IO"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "12"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "Test"}
          , demangledOccName = "Test"
          , nameSpace = DataName
          , locationInfo =
              ExactLocation
                { packageId =
                    PackageId
                      { name = "test-package"
                      , version =
                          Version
                            {versionBranch = [0, 1, 0, 0], versionTags = []}
                      }
                , modulePath =
                    HaskellModulePath {getHaskellModulePath = "src/Types.hs"}
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "Types"}
                , startLine = 5
                , endLine = 5
                , startColumn = 13
                , endColumn = 21
                }
          , idType =
              Type
                { components =
                    [ TyCon
                        { internalId = InternalId {getInternalId = "9"}
                        , name = "Int"
                        }
                    , Text " -> "
                    , TyCon
                        { internalId = InternalId {getInternalId = "1"}
                        , name = "Test"
                        }
                    ]
                , componentsExpanded = Nothing
                }
          , details = Just DataConWorkId
          , doc = Nothing
          , internalId = InternalId {getInternalId = "12"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "test-package-0.1.0.0|Types|Val|Test"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "17"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "[]"}
          , demangledOccName = "[]"
          , nameSpace = TcClsName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "ghc-prim"
                      , version =
                          Version
                            {versionBranch = [0, 5, 1, 1], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Types"}
                , entity = Typ
                , name = "[]"
                , haddockAnchorId = Just "-91--93-"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type {components = [Text "* -> *"], componentsExpanded = Nothing}
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "17"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "ghc-prim-0.5.1.1|GHC.Types|Typ|[]"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "1"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "Test"}
          , demangledOccName = "Test"
          , nameSpace = TcClsName
          , locationInfo =
              ExactLocation
                { packageId =
                    PackageId
                      { name = "test-package"
                      , version =
                          Version
                            {versionBranch = [0, 1, 0, 0], versionTags = []}
                      }
                , modulePath =
                    HaskellModulePath {getHaskellModulePath = "src/Types.hs"}
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "Types"}
                , startLine = 5
                , endLine = 5
                , startColumn = 1
                , endColumn = 21
                }
          , idType =
              Type {components = [Text "*"], componentsExpanded = Nothing}
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "1"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "test-package-0.1.0.0|Types|Typ|Test"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "18"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "LiftedRep"}
          , demangledOccName = "LiftedRep"
          , nameSpace = DataName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "ghc-prim"
                      , version =
                          Version
                            {versionBranch = [0, 5, 1, 1], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Types"}
                , entity = Val
                , name = "LiftedRep"
                , haddockAnchorId = Just "LiftedRep"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type
                { components =
                    [ TyCon
                        { internalId = InternalId {getInternalId = "15"}
                        , name = "RuntimeRep"
                        }
                    ]
                , componentsExpanded = Nothing
                }
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "18"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "ghc-prim-0.5.1.1|GHC.Types|Val|LiftedRep"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "4"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "()"}
          , demangledOccName = "()"
          , nameSpace = TcClsName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "ghc-prim"
                      , version =
                          Version
                            {versionBranch = [0, 5, 1, 1], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Tuple"}
                , entity = Typ
                , name = "()"
                , haddockAnchorId = Just "-40--41-"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type {components = [Text "*"], componentsExpanded = Nothing}
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "4"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "ghc-prim-0.5.1.1|GHC.Tuple|Typ|()"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "16"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "String"}
          , demangledOccName = "String"
          , nameSpace = TcClsName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "base"
                      , version =
                          Version
                            {versionBranch = [4, 10, 1, 0], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Base"}
                , entity = Typ
                , name = "String"
                , haddockAnchorId = Just "String"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type {components = [Text "*"], componentsExpanded = Nothing}
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "16"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "base-4.10.1.0|GHC.Base|Typ|String"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "2"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "someFunc"}
          , demangledOccName = "someFunc"
          , nameSpace = VarName
          , locationInfo =
              ExactLocation
                { packageId =
                    PackageId
                      { name = "test-package"
                      , version =
                          Version
                            {versionBranch = [0, 1, 0, 0], versionTags = []}
                      }
                , modulePath =
                    HaskellModulePath {getHaskellModulePath = "src/Lib.hs"}
                , moduleName = HaskellModuleName {getHaskellModuleName = "Lib"}
                , startLine = 9
                , endLine = 9
                , startColumn = 1
                , endColumn = 9
                }
          , idType =
              Type
                { components =
                    [ TyCon
                        { internalId = InternalId {getInternalId = "0"}
                        , name = "IO"
                        }
                    , Text " ()"
                    ]
                , componentsExpanded = Nothing
                }
          , details = Just VanillaId
          , doc = Just "<p><span>someFunc documentation</span></p>"
          , internalId = InternalId {getInternalId = "2"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "test-package-0.1.0.0|Lib|Val|someFunc"})
          , isExported = True
          })
    , ( InternalId {getInternalId = "5"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "putStrLn"}
          , demangledOccName = "putStrLn"
          , nameSpace = VarName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "base"
                      , version =
                          Version
                            {versionBranch = [4, 10, 1, 0], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "System.IO"}
                , entity = Val
                , name = "putStrLn"
                , haddockAnchorId = Just "putStrLn"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type
                { components =
                    [ TyCon
                        { internalId = InternalId {getInternalId = "16"}
                        , name = "String"
                        }
                    , Text " -> "
                    , TyCon
                        { internalId = InternalId {getInternalId = "0"}
                        , name = "IO"
                        }
                    , Text " ()"
                    ]
                , componentsExpanded =
                    Just
                      [ Text "["
                      , TyCon
                          { internalId = InternalId {getInternalId = "6"}
                          , name = "Char"
                          }
                      , Text "] -> "
                      , TyCon
                          { internalId = InternalId {getInternalId = "0"}
                          , name = "IO"
                          }
                      , Text " ()"
                      ]
                }
          , details = Just VanillaId
          , doc = Nothing
          , internalId = InternalId {getInternalId = "5"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "base-4.10.1.0|System.IO|Val|putStrLn"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "6"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "Char"}
          , demangledOccName = "Char"
          , nameSpace = TcClsName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "ghc-prim"
                      , version =
                          Version
                            {versionBranch = [0, 5, 1, 1], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Types"}
                , entity = Typ
                , name = "Char"
                , haddockAnchorId = Just "Char"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type {components = [Text "*"], componentsExpanded = Nothing}
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "6"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "ghc-prim-0.5.1.1|GHC.Types|Typ|Char"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "9"}
      , IdentifierInfo
          { sort = External
          , occName = OccName {getOccName = "Int"}
          , demangledOccName = "Int"
          , nameSpace = TcClsName
          , locationInfo =
              ApproximateLocation
                { packageId =
                    PackageId
                      { name = "ghc-prim"
                      , version =
                          Version
                            {versionBranch = [0, 5, 1, 1], versionTags = []}
                      }
                , moduleName =
                    HaskellModuleName {getHaskellModuleName = "GHC.Types"}
                , entity = Typ
                , name = "Int"
                , haddockAnchorId = Just "Int"
                , componentId = ComponentId {getComponentId = "lib"}
                }
          , idType =
              Type {components = [Text "*"], componentsExpanded = Nothing}
          , details = Nothing
          , doc = Nothing
          , internalId = InternalId {getInternalId = "9"}
          , externalId =
              Just
                (ExternalId
                   {getExternalId = "ghc-prim-0.5.1.1|GHC.Types|Typ|Int"})
          , isExported = False
          })
    , ( InternalId {getInternalId = "10"}
      , IdentifierInfo
          { sort = Internal
          , occName = OccName {getOccName = "i"}
          , demangledOccName = "i"
          , nameSpace = VarName
          , locationInfo =
              ExactLocation
                { packageId =
                    PackageId
                      { name = "test-package"
                      , version =
                          Version
                            {versionBranch = [0, 1, 0, 0], versionTags = []}
                      }
                , modulePath =
                    HaskellModulePath {getHaskellModulePath = "src/Lib.hs"}
                , moduleName = HaskellModuleName {getHaskellModuleName = ""}
                , startLine = 13
                , endLine = 13
                , startColumn = 8
                , endColumn = 9
                }
          , idType =
              Type
                { components =
                    [ TyCon
                        { internalId = InternalId {getInternalId = "9"}
                        , name = "Int"
                        }
                    ]
                , componentsExpanded = Nothing
                }
          , details = Just VanillaId
          , doc = Nothing
          , internalId = InternalId {getInternalId = "10"}
          , externalId = Nothing
          , isExported = False
          })
    ]


