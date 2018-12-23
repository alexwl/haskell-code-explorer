{-# LANGUAGE CPP #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StrictData #-}

module HaskellCodeExplorer.ModuleInfo
  ( createModuleInfo
  , ModuleDependencies
  ) where

import qualified Data.Generics.Uniplate.Data as U
import Control.Monad.State.Strict (execState,evalState,get,put,State)
import qualified Data.Aeson as Aeson
import Data.Aeson.Text(encodeToLazyText)
import qualified Data.Vector as V
import qualified Data.HashMap.Strict as HM
import qualified Data.Map.Strict as M
import qualified Data.IntMap.Strict as IM
import qualified Data.IntervalMap.Strict as IVM
import qualified Data.List as L hiding (span)
import Data.Maybe (fromMaybe, mapMaybe)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
import HsExtension (GhcRn)
#endif
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Lazy (toStrict)
import Documentation.Haddock.Types (DocH)
import DynFlags(DynFlags)
import GHC
  ( GenLocated(..)
  , ModSummary
  , ModuleInfo
  , ModuleName
  , SrcSpan
  , TyThing(..)
  , Type
  , TypecheckedModule
  , getLoc
  , isGoodSrcSpan
  , modInfoExportsWithSelectors
  , modInfoInstances
  , moduleInfo
  , moduleNameString
  , ms_hspp_buf
  , ms_mod
  , renamedSource
  , tm_internals_
  , tm_typechecked_source
  , unLoc
  )
import Type(expandTypeSynonyms)
import TyCon (isFamInstTyCon,tyConName)
import HaskellCodeExplorer.AST.RenamedSource
import HaskellCodeExplorer.AST.TypecheckedSource
import HaskellCodeExplorer.GhcUtils
import HaskellCodeExplorer.Preprocessor (createSourceCodeTransformation)
import qualified HaskellCodeExplorer.Types as HCE
import HsBinds(HsBindLR)
import HsDecls
  ( ForeignDecl(..)
  , HsDecl(..)
  , HsGroup(..)
  , InstDecl
  , InstDecl(..)
  , TyClDecl
  , group_tyclds
  , tyClDeclLName
  , tcdName
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  , hsGroupInstDecls
#endif
  )
import HsDoc(HsDocString)
import HsImpExp (IE(..), ImportDecl(..))
import HsUtils(collectHsBindBinders)
import HscTypes
  ( ExternalPackageState
  , HomePackageTable
  , TypeEnv
  , eps_PTE
  , eps_inst_env
  , hm_details
  , md_types
  , mkTypeEnv
  , typeEnvElts
  )
import InstEnv (InstEnvs(..), is_dfun)
import Module(Module(..))
import Name (Name, OccName, getSrcSpan, nameOccName, nameSrcSpan, nameUnique)
import Prelude hiding(id,span)
import RdrName(GlobalRdrEnv)
import SrcLoc (isOneLineSpan)  
import TcRnTypes (tcVisibleOrphanMods, tcg_inst_env, tcg_rdr_env, tcg_type_env)
import qualified Text.Blaze.Html5 as H 
import qualified Text.Blaze.Html5.Attributes as A
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
import UniqDFM (eltsUDFM)
#else
import UniqFM (eltsUFM)
#endif
import Unique (getKey)
import Var (varName, varType,Id)
import VarEnv (emptyTidyEnv)

type ModuleDependencies
   = ( HM.HashMap HCE.HaskellFilePath HCE.HaskellModulePath
     , HM.HashMap HCE.HaskellModulePath HCE.DefinitionSiteMap
     , HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath))
  
type ModuleGhcData
   = ( DynFlags
     , TypecheckedModule
     , HomePackageTable
     , ExternalPackageState
     , ModSummary)
 
createModuleInfo ::
     ModuleDependencies -- ^ Modules that have already been indexed
  -> ModuleGhcData -- ^ Data types from GHC
  -> HCE.HaskellModulePath -- ^ Current module path
  -> HCE.PackageId -- ^ Current package id
  -> HCE.ComponentId -- ^ Current build component id
  -> (T.Text, HCE.SourceCodePreprocessing) -- ^ Source code
  -> (HCE.ModuleInfo, ModuleDependencies, [TypeError])
createModuleInfo (fileMap, defSiteMap, moduleNameMap) (flags, typecheckedModule, homePackageTable, externalPackageState, modSum) modulePath currentPackageId compId (originalSourceCode, sourceCodePreprocessing) =
  let globalRdrEnv = tcg_rdr_env . fst . tm_internals_ $ typecheckedModule
      modInfo = moduleInfo typecheckedModule
      (Just (hsGroup, _, _, _)) = renamedSource typecheckedModule
      exportedNamesSet = S.fromList $ modInfoExportsWithSelectors modInfo
      --------------------------------------------------------------------------------
      -- Preprocessed source
      --------------------------------------------------------------------------------
      (transformation, sourceCode') =
        prepareSourceCode
          sourceCodePreprocessing
          originalSourceCode
          modSum
          modulePath
      includedFiles = HM.keys $ HCE.fileIndex transformation
      --------------------------------------------------------------------------------
      -- Type environment
      --------------------------------------------------------------------------------
      (tcGblEnv, _) = tm_internals_ typecheckedModule
      currentModuleTyThings = typeEnvElts $ tcg_type_env tcGblEnv
      homePackageTyThings =
        concatMap (typeEnvElts . md_types . hm_details) $
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)        
        eltsUDFM homePackageTable
#else
        eltsUFM homePackageTable
#endif
      externalPackagesTyThings = typeEnvElts $ eps_PTE externalPackageState
      typeEnv =
        mkTypeEnv
          (currentModuleTyThings ++
           homePackageTyThings ++ externalPackagesTyThings)
      --------------------------------------------------------------------------------
      -- Exported entities
      --------------------------------------------------------------------------------
      dataFamTyCons =
        mapMaybe
          (\case
             ATyCon tc
               | isFamInstTyCon tc -> Just $ tyConName tc
             _ -> Nothing)
          currentModuleTyThings
      (defSites, allNames) =
        createDefinitionSiteMap
          flags
          currentPackageId
          compId
          defSiteMap
          fileMap          
          globalRdrEnv
          transformation
          modInfo
          dataFamTyCons
          hsGroup
      --------------------------------------------------------------------------------
      -- Instance environment
      --------------------------------------------------------------------------------
      homeInstEnv = tcg_inst_env tcGblEnv
      visOrphanModules = tcVisibleOrphanMods tcGblEnv
      packageInstEnv = eps_inst_env externalPackageState
      instEnv = InstEnvs packageInstEnv homeInstEnv visOrphanModules
      --------------------------------------------------------------------------------
      declarations =
        createDeclarations flags hsGroup typeEnv exportedNamesSet transformation
      environment =
        Environment
          { envDynFlags = flags
          , envInstEnv = instEnv
          , envTypeEnv = typeEnv
          , envTransformation = transformation
          , envCurrentModuleDefSites = defSites
          , envFileMap = fileMap
          , envDefSiteMap = defSiteMap
          , envModuleNameMap = moduleNameMap
          , envPackageId = currentPackageId
          , envComponentId = compId
          , envExportedNames = exportedNamesSet
          }
      externalIds =
        L.foldl'
          (\acc name ->
             maybe
               acc
               (\id -> (HCE.ExternalIdentifierInfo $ mkIdentifierInfo environment id (Just name)) : acc)
               (lookupIdInTypeEnv typeEnv name))
          []
          allNames
      currentModuleName =
        (\(Module _ name) ->
           HCE.HaskellModuleName . T.pack . moduleNameString $ name) .
        ms_mod $
        modSum
      SourceInfo {..} = foldAST environment typecheckedModule
   in (tidyInternalIds HCE.ModuleInfo
          { id = modulePath
          , transformation = transformation
          , name = currentModuleName
          , declarations = declarations
          , exprInfoMap = sourceInfoExprMap
          , idInfoMap = sourceInfoIdMap
          , idOccMap = sourceInfoIdOccMap
          , definitionSiteMap = defSites
          , source = V.fromList . T.splitOn "\n" $ sourceCode'
          , externalIds = externalIds
          }
      , if not $ isHsBoot modulePath
          then  (HM.union
                   (HM.fromList .
                    (( HCE.HaskellFilePath $ HCE.getHaskellModulePath modulePath
                     , modulePath) :) .
                    map (, modulePath) $
                    includedFiles)
                   fileMap
               , HM.union (HM.singleton modulePath defSites) defSiteMap
               , HM.insertWith HM.union currentModuleName
                   (HM.singleton compId modulePath) moduleNameMap)
          else (fileMap, defSiteMap, moduleNameMap)
       , sourceInfoTypeErrors)

data SourceInfo = SourceInfo
  { sourceInfoExprMap :: HCE.ExpressionInfoMap
  , sourceInfoIdMap :: HCE.IdentifierInfoMap
  , sourceInfoIdOccMap :: HCE.IdentifierOccurrenceMap
  , sourceInfoTypeErrors :: [TypeError]
  } deriving (Show, Eq)

tidyInternalIds :: HCE.ModuleInfo -> HCE.ModuleInfo
tidyInternalIds modInfo = evalState (U.transformBiM tidy modInfo) (HM.empty, 0)
  where
    tidy ::
         HCE.InternalId -> State (HM.HashMap T.Text T.Text, Int) HCE.InternalId
    tidy (HCE.InternalId text) = do
      (hmap, number) <- get
      case HM.lookup text hmap of
        Just val -> return $ HCE.InternalId val
        Nothing -> do
          let nextInternalId = T.pack . show $ number
          put (HM.insert text nextInternalId hmap, number + 1)
          return $ HCE.InternalId nextInternalId

prepareSourceCode ::
     HCE.SourceCodePreprocessing
  -> T.Text
  -> ModSummary
  -> HCE.HaskellModulePath
  -> (HCE.SourceCodeTransformation, T.Text)
prepareSourceCode sourceCodePreprocessing originalSourceCode modSum modulePath =
  let sourceCodeAfterPreprocessing =
        case TE.decodeUtf8' $
             maybe
               (error "ms_hspp_buf is Nothing")
               stringBufferToByteString
               (ms_hspp_buf modSum) of
          Right text -> T.replace "\t" "        " text
          Left err ->
            error $
            "decodeUtf8' : " ++ show err ++ " , file : " ++ show modulePath
   in case sourceCodePreprocessing of
        HCE.BeforePreprocessing ->
          let sourceCodeLines = T.splitOn "\n" originalSourceCode
           in ( HCE.SourceCodeTransformation
                  (length sourceCodeLines)
                  modulePath
                  S.empty
                  HM.empty
              , originalSourceCode)
        HCE.AfterPreprocessing ->
          createSourceCodeTransformation
            modulePath
            originalSourceCode
            sourceCodeAfterPreprocessing

createDefinitionSiteMap ::
     DynFlags
  -> HCE.PackageId
  -> HCE.ComponentId
  -> HM.HashMap HCE.HaskellModulePath HCE.DefinitionSiteMap
  -> HM.HashMap HCE.HaskellFilePath HCE.HaskellModulePath
  -> GlobalRdrEnv
  -> HCE.SourceCodeTransformation
  -> ModuleInfo
  -> [Name]
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
  -> HsGroup GhcRn
#else
  -> HsGroup Name
#endif
  -> (HCE.DefinitionSiteMap, [Name])
createDefinitionSiteMap flags currentPackageId compId defSiteMap fileMap globalRdrEnv transformation modInfo dataFamTyCons hsGroup =
  let
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
      allDecls :: [GenLocated SrcSpan (HsDecl GhcRn)]
#endif
      allDecls = L.sortOn getLoc . ungroup $ hsGroup
      (instanceDeclsWithDocs, valueAndTypeDeclsWithDocs) =
        L.partition
          (\(L _ decl, _) ->
             case decl of
               InstD {} -> True
               _ -> False) $
        collectDocs allDecls
      --------------------------------------------------------------------------------
      -- Instances
      --------------------------------------------------------------------------------
      -- No type instances or data instances here for now
      instanceDocMap :: M.Map SrcSpan [HsDocString]
      instanceDocMap =
        M.fromList .
        mapMaybe
          (\(L _n decl, docs) ->
             case decl of
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)               
               InstD _ (ClsInstD _ inst) -> Just (clsInstDeclSrcSpan inst, docs)
#else  
               InstD (ClsInstD inst) -> Just (clsInstDeclSrcSpan inst, docs)
#endif  
               _ -> Nothing) $
        instanceDeclsWithDocs
      nameLocation :: Maybe SrcSpan -> Name -> HCE.LocationInfo
      nameLocation =
        nameLocationInfo
          flags
          currentPackageId
          compId
          transformation
          fileMap
          defSiteMap
          Nothing
      docHToHtml :: DocH (ModuleName, OccName) Name -> HCE.HTML
      docHToHtml =
        docWithNamesToHtml
          flags
          currentPackageId
          compId
          transformation
          fileMap
          defSiteMap
      instancesWithDocumentation =
        HM.fromList .
        map
          (\clsInst ->
             ( instanceToText flags clsInst
             , let location =
                     nameLocation Nothing (Var.varName . is_dfun $ clsInst)
                in case M.lookup (getSrcSpan clsInst) instanceDocMap of
                     Just hsDocString ->
                       HCE.DefinitionSite
                         location
                         (Just . docHToHtml . hsDocsToDocH flags globalRdrEnv $
                          hsDocString)
                     Nothing -> HCE.DefinitionSite location Nothing)) $
        modInfoInstances modInfo -- all instances (including derived)
      --------------------------------------------------------------------------------
      -- Values and types
      --------------------------------------------------------------------------------
      mainDeclNamesWithDocumentation =
        concatMap
          (\(L span decl, docs) -> map (, docs, span) $ getMainDeclBinder decl)
          valueAndTypeDeclsWithDocs
      dataFamTyConsWithoutDocs =
        map (\name -> (name, [], nameSrcSpan name)) dataFamTyCons
      allNamesWithDocumentation =
        mainDeclNamesWithDocumentation ++
        subordinateNamesWithDocs allDecls ++ dataFamTyConsWithoutDocs
      (valuesWithDocumentation, typesWithDocumentation) =
        L.partition
          (\(name, _doc, _srcSpan) ->
             case occNameNameSpace . nameOccName $ name of
               HCE.VarName -> True
               HCE.DataName -> True
               _ -> False)
          allNamesWithDocumentation
      toHashMap ::
           [(Name, [HsDocString], SrcSpan)]
        -> HM.HashMap HCE.OccName HCE.DefinitionSite
      toHashMap =
        HM.fromListWith
          (\(HCE.DefinitionSite loc newDoc) (HCE.DefinitionSite _ oldDoc) ->
             (HCE.DefinitionSite loc $ mappend newDoc oldDoc)) .
        map
          (\(name, docs, srcSpan) ->
             let location = nameLocation (Just srcSpan) name
                 htmlDoc =
                   if not . null $ docs
                     then Just . docHToHtml . hsDocsToDocH flags globalRdrEnv $
                          docs
                     else Nothing
              in (HCE.OccName $ toText flags name, HCE.DefinitionSite location htmlDoc))
      --------------------------------------------------------------------------------
   in ( HCE.DefinitionSiteMap
          { HCE.values = toHashMap valuesWithDocumentation
          , HCE.types =
              toHashMap $ typesWithDocumentation ++ dataFamTyConsWithoutDocs
          , HCE.instances = instancesWithDocumentation
          }
      , map (\(n, _, _) -> n) allNamesWithDocumentation)

occNameToHtml ::
     DynFlags  
  -> HCE.PackageId
  -> HCE.ComponentId
  -> (ModuleName, OccName)
  -> H.Html
occNameToHtml flags packageId compId (modName, occName) =
  let location =
        H.textValue . toStrict . encodeToLazyText . Aeson.toJSON $
        occNameLocationInfo flags packageId compId (modName, occName)
   in (H.span H.! H.dataAttribute "location" location) H.! A.class_ "link" $
      H.toHtml (toText flags occName)

nameToHtml ::
     DynFlags
  -> HCE.PackageId
  -> HCE.ComponentId
  -> HCE.SourceCodeTransformation
  -> HM.HashMap HCE.HaskellFilePath HCE.HaskellModulePath
  -> HM.HashMap HCE.HaskellModulePath HCE.DefinitionSiteMap
  -> Name
  -> H.Html
nameToHtml flags packageId compId transformation files defSiteMap name =
  let location =
        H.textValue . toStrict . encodeToLazyText . Aeson.toJSON $
        nameLocationInfo
          flags
          packageId
          compId
          transformation
          files
          defSiteMap
          Nothing
          Nothing
          name
   in H.span H.! H.dataAttribute "location" location H.! A.class_ "link" $
      H.toHtml (nameToText name)
  
docWithNamesToHtml ::
     DynFlags
  -> HCE.PackageId
  -> HCE.ComponentId
  -> HCE.SourceCodeTransformation
  -> HM.HashMap HCE.HaskellFilePath HCE.HaskellModulePath
  -> HM.HashMap HCE.HaskellModulePath HCE.DefinitionSiteMap
  -> DocH (ModuleName, OccName) Name
  -> HCE.HTML
docWithNamesToHtml flags packageId compId transformation fileMap defSiteMap =
  HCE.docToHtml
    (occNameToHtml flags packageId compId)
    (nameToHtml flags packageId compId transformation fileMap defSiteMap)

createDeclarations ::
     DynFlags
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)           
  -> HsGroup GhcRn
#else
  -> HsGroup Name
#endif
  -> TypeEnv
  -> S.Set Name
  -> HCE.SourceCodeTransformation
  -> [HCE.Declaration]
createDeclarations flags hsGroup typeEnv exportedSet transformation =
  let lineNumber :: SrcSpan -> Int
      lineNumber srcSpan =
        case srcSpanToLineAndColNumbers transformation srcSpan of
          Just (_file,(lineNum, _), (_, _)) -> lineNum
          Nothing -> 1
      nameType :: Name -> Maybe HCE.Type
      nameType n =
        case lookupIdInTypeEnv typeEnv n of
          Just i -> Just . mkType flags . varType $ i
          Nothing -> Nothing
      -- | Top-level functions
      --------------------------------------------------------------------------------
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)      
      valToDeclarations :: GenLocated SrcSpan (HsBindLR GhcRn GhcRn) -> [HCE.Declaration]
#endif                           
      valToDeclarations (L loc bind) =
        map
          (\name ->
             HCE.Declaration
               HCE.ValD
               (toText flags name)
               (nameType name)
               (S.member name exportedSet)
               (lineNumber loc)) $
        collectHsBindBinders bind
      vals = concatMap valToDeclarations $ hsGroupVals hsGroup
      -- | Data, newtype, type, type family, data family or class declaration
      --------------------------------------------------------------------------------
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)            
      tyClToDeclaration :: GenLocated SrcSpan (TyClDecl GhcRn) -> HCE.Declaration
#endif                           
      tyClToDeclaration (L loc tyClDecl) =
        HCE.Declaration
          HCE.TyClD
          (T.append (tyClDeclPrefix tyClDecl) (toText flags $ tcdName tyClDecl))
          (nameType $ tcdName tyClDecl)
          (S.member (unLoc $ tyClDeclLName tyClDecl) exportedSet)
          (lineNumber loc)
      tyclds =
        map tyClToDeclaration .
        filter (isGoodSrcSpan . getLoc) . concatMap group_tyclds . hs_tyclds $
        hsGroup
      -- | Instances
      --------------------------------------------------------------------------------
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)                    
      instToDeclaration :: GenLocated SrcSpan (InstDecl GhcRn) -> HCE.Declaration
#endif                           
      instToDeclaration (L loc inst) =
        HCE.Declaration
          HCE.InstD
          (instanceDeclToText flags inst)
          Nothing
          True
          (lineNumber loc)
      insts =
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)        
        map instToDeclaration . filter (isGoodSrcSpan . getLoc) . hsGroupInstDecls $
#else
        map instToDeclaration . filter (isGoodSrcSpan . getLoc) . hs_instds $
#endif
        hsGroup
      -- | Foreign functions
      --------------------------------------------------------------------------------
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)                            
      foreignFunToDeclaration ::
           GenLocated SrcSpan (ForeignDecl GhcRn) -> HCE.Declaration
#endif           
      foreignFunToDeclaration (L loc fd) =
        let name = unLoc $ fd_name fd
         in HCE.Declaration
              HCE.ForD
              (toText flags name)
              (nameType name)
              True
              (lineNumber loc)
      fords = map foreignFunToDeclaration $ hs_fords hsGroup
      --------------------------------------------------------------------------------
   in L.sortOn HCE.lineNumber $ vals ++ tyclds ++ insts ++ fords

foldAST :: Environment -> TypecheckedModule -> SourceInfo
foldAST environment typecheckedModule =
  let (Just renamed@(_, importDecls, mbExported, _)) =
        renamedSource typecheckedModule
      emptyASTState =
        ASTState IVM.empty IM.empty M.empty emptyTidyEnv Nothing environment []
      ASTState {..} =
        execState
          (foldTypecheckedSource $ tm_typechecked_source typecheckedModule)
          emptyASTState
      -- A few things that are not in the output of the typechecker:
      --     - the export list
      --     - the imports
      --     - type signatures
      --     - type/data/newtype declarations
      --     - class declarations
      
      -- Both typechecked source and renamed source are used to populate
      -- 'IdentifierInfoMap' and 'IdentifierOccurrenceMap'
      (idInfoMap, idOccMap) =
        L.foldl'
          (addIdentifierToMaps environment astStateIdSrcSpanMap)
          (HM.empty, astStateIdOccMap)
          (namesFromRenamedSource renamed)          
      flags = envDynFlags environment
      packageId = envPackageId environment
      compId = envComponentId environment
      importedModules =
        map
          ((\(L span modName) ->
              ( modName
              , span
              , moduleLocationInfo
                  flags
                  (envModuleNameMap environment)
                  packageId
                  compId
                  modName)) .
           ideclName . unLoc) .
        filter (not . ideclImplicit . unLoc) $
        importDecls
      exportedModules =
        case mbExported of
          Just lieNames ->
            mapMaybe
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)            
              (\(L span ie,_) ->
#else
              (\(L span ie) ->
#endif
                 case ie of
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
                   IEModuleContents _ (L _ modName) ->
#else
                   IEModuleContents (L _ modName) ->
#endif
                     Just
                       ( modName
                       , span
                       , moduleLocationInfo
                           flags
                           (envModuleNameMap environment)
                           packageId
                           compId
                           modName)
                   _ -> Nothing)
              lieNames
          Nothing -> []
      addImportedAndExportedModulesToIdOccMap ::
           HCE.IdentifierOccurrenceMap -> HCE.IdentifierOccurrenceMap
      addImportedAndExportedModulesToIdOccMap =
        IM.map (L.sortOn fst) .
        addModules
          (envTransformation environment)
          (importedModules ++ exportedModules)
   in SourceInfo
        { sourceInfoExprMap = astStateExprInfoMap
        , sourceInfoIdMap = idInfoMap
        , sourceInfoIdOccMap = addImportedAndExportedModulesToIdOccMap idOccMap
        , sourceInfoTypeErrors = astStateTypeErrors
        }

-- | Updates 'IdentifierOccurrenceMap' and 'IdentifierInfoMap' using information
-- from typechecked source and renamed source
addIdentifierToMaps ::
     Environment
  -> M.Map SrcSpan (Id, Maybe (Type, [Type]))
  -> (HCE.IdentifierInfoMap, HCE.IdentifierOccurrenceMap)
  -> NameOccurrence
  -> (HCE.IdentifierInfoMap, HCE.IdentifierOccurrenceMap)
addIdentifierToMaps environment idSrcSpanMap idMaps@(idInfoMap, idOccMap) nameOcc
  | isGoodSrcSpan (getLoc $ locatedName nameOcc) &&
      isOneLineSpan (getLoc $ locatedName nameOcc)
  , Just (_, (lineNumber, startCol), (_, endCol)) <-
     srcSpanToLineAndColNumbers (envTransformation environment) .
     getLoc . locatedName $
     nameOcc =
    case nameOcc of
      TyLitOccurrence {kind = kind} ->
        addNameToMaps
          environment
          idMaps
          (Just kind)
          Nothing
          (description nameOcc)
          lineNumber
          startCol
          endCol
      NameOccurrence {isBinder = isBinder} ->
        case lookupIdByNameOccurrence environment idSrcSpanMap nameOcc of
          Just (identifier, mbTypes) ->
            let name =
                  fromMaybe
                    (Var.varName identifier)
                    (unLoc $ locatedName nameOcc)
                identifierType = varType identifier
                identifierTypeExpanded = expandTypeSynonyms identifierType
                tyConsAndTyVars =
                  map
                    (, Nothing)
                    (tyConsOfType identifierType ++
                     tyVarsOfType identifierType ++
                     tyConsOfType identifierTypeExpanded ++
                     tyVarsOfType identifierTypeExpanded ++
                     maybe [] (tyConsOfType . fst) mbTypes ++
                     maybe [] (tyVarsOfType . fst) mbTypes)
                idInfoMap' =
                  updateIdMap
                    environment
                    ((identifier, unLoc $ locatedName nameOcc) : tyConsAndTyVars)
                    idInfoMap
                idOcc =
                  mkIdentifierOccurrence
                    environment
                    identifier
                    name
                    mbTypes
                    isBinder
                    (description nameOcc)
                idOccMap' =
                  IM.insertWith
                    removeOverlappingInterval
                    lineNumber
                    [((startCol, endCol), idOcc)]
                    idOccMap
             in (idInfoMap', idOccMap')
          Nothing -- type variable or an internal identifier in a pattern synonym
           ->
            case unLoc $ locatedName nameOcc of
              Just name ->
                addNameToMaps
                  environment
                  idMaps
                  Nothing
                  (Just name)
                  (description nameOcc)
                  lineNumber
                  startCol
                  endCol
              Nothing -> idMaps             
addIdentifierToMaps _ _ idMaps _ = idMaps

addNameToMaps ::
     Environment
  -> (HCE.IdentifierInfoMap, HCE.IdentifierOccurrenceMap)
  -> Maybe Type
  -> Maybe Name
  -> T.Text
  -> Int
  -> Int
  -> Int
  -> (HCE.IdentifierInfoMap, HCE.IdentifierOccurrenceMap)
addNameToMaps environment (idInfoMap, idOccMap) mbKind mbName descr lineNumber colStart colEnd =
  let flags = envDynFlags environment
      idInfoMap' =
        maybe
          idInfoMap
          (\kind ->
             updateIdMap
               environment
               (map (, Nothing) $ tyConsOfType kind ++ tyVarsOfType kind)
               idInfoMap)
          mbKind
      idOcc =
        HCE.IdentifierOccurrence
          { internalId = fmap (HCE.InternalId . nameKey) mbName
          , internalIdFromRenamedSource =
              HCE.InternalId . T.pack . show . getKey . nameUnique <$> mbName
          , isBinder = False
          , instanceResolution = Nothing
          , idOccType = mkType flags <$> mbKind
          , typeArguments = Nothing
          , description = descr
          , sort =
              maybe
                HCE.TypeId
                (\name ->
                   case occNameNameSpace . nameOccName $ name of
                     HCE.VarName -> HCE.ValueId
                     HCE.DataName -> HCE.ValueId
                     _ -> HCE.TypeId)
                mbName
          }
      idOccMap' =
        IM.insertWith
          removeOverlappingInterval
          lineNumber
          [((colStart, colEnd), idOcc)]
          idOccMap
   in (idInfoMap', idOccMap')

lookupIdByNameOccurrence ::
     Environment
  -> M.Map SrcSpan (Id, Maybe (Type, [Type]))
  -> NameOccurrence
  -> Maybe (Id, Maybe (Type, [Type]))
lookupIdByNameOccurrence environment idSrcSpanMap (NameOccurrence (L span mbName) _ _) =
  case M.lookup span idSrcSpanMap of    
    Just (identifier, mbTypes) -> Just (identifier, mbTypes)
    Nothing ->
      case mbName of
        Just name ->
          case M.lookup (nameSrcSpan name) idSrcSpanMap of
            -- LHS of a Match
            Just (identifier, mbTypes) -> Just (identifier, mbTypes)
            Nothing ->
              -- Things that are not in the typechecked source
              case lookupIdInTypeEnv (envTypeEnv environment) name of
                Just t -> Just (t, Nothing)
                Nothing -> Nothing
        Nothing -> Nothing
lookupIdByNameOccurrence _ _ TyLitOccurrence {..} = Nothing
      
updateIdMap ::
     Environment
  -> [(Id, Maybe Name)]
  -> HCE.IdentifierInfoMap
  -> HCE.IdentifierInfoMap
updateIdMap environment ids identifiersMap =
  let flags = envDynFlags environment
      update ::
           HCE.IdentifierInfoMap -> (Id, Maybe Name) -> HCE.IdentifierInfoMap
      update idMap (identifier, mbName) =
        let info = mkIdentifierInfo environment identifier mbName
         in HM.insertWith
              (flip const)
              (HCE.InternalId $ identifierKey flags identifier)
              info
              idMap
   in L.foldl' update identifiersMap ids

addModules ::
     HCE.SourceCodeTransformation
  -> [(ModuleName, SrcSpan, HCE.LocationInfo)]
  -> HCE.IdentifierOccurrenceMap
  -> HCE.IdentifierOccurrenceMap
addModules transformation modules idMap =
  let update ::
           IM.IntMap [((Int, Int), HCE.IdentifierOccurrence)]
        -> (a, SrcSpan, HCE.LocationInfo)
        -> IM.IntMap [((Int, Int), HCE.IdentifierOccurrence)]
      update idOccMap (_modInfo, span, locInfo)
        | Just (_file,(lineNumber, colStart), (_, colEnd)) <-
           srcSpanToLineAndColNumbers transformation span =
          let idOcc =
                HCE.IdentifierOccurrence
                  { internalId = Nothing
                  , internalIdFromRenamedSource = Nothing
                  , isBinder = False
                  , instanceResolution = Nothing
                  , idOccType = Nothing
                  , typeArguments = Nothing
                  , description = "ImportDecl"
                  , sort = HCE.ModuleId locInfo
                  }
           in IM.insertWith
                removeOverlappingInterval
                lineNumber
                [((colStart, colEnd), idOcc)]
                idOccMap
      update idOccMap _ = idOccMap
   in L.foldl' update idMap modules
