{-# LANGUAGE CPP #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecordWildCards #-}

module HaskellCodeExplorer.GhcUtils
  ( -- * Pretty-printing
    toText
  , instanceToText
  , instanceDeclToText
  , nameToText
  , tyClDeclPrefix
  , demangleOccName
  , stringBufferToByteString
  , nameSort
  , occNameNameSpace
  , identifierKey
  , nameKey
  , mbIdDetails
    -- * Syntax manipulation
  , hsGroupVals
  , hsPatSynDetails
  , ieLocNames
    -- * Lookups
  , lookupIdInTypeEnv
  , lookupNameModuleAndPackage
    -- * Location info
  , isHsBoot
  , moduleLocationInfo
  , nameLocationInfo
  , occNameLocationInfo
  , nameDocumentation
  , srcSpanToLineAndColNumbers
    -- * Type-related functions
  , tyThingToId
  , tidyIdentifierType
  , patSynId
  , applyWrapper
  , wrapperTypes
  , tyVarsOfType
  , tyConsOfType
  , updateOccNames
  , mkType
    -- * Documentation processing
  , collectDocs
  , ungroup
  , mkDecls
  , getMainDeclBinder
  , classDeclDocs
  , sigNameNoLoc
  , clsInstDeclSrcSpan
  , hsDocsToDocH
  , subordinateNamesWithDocs
  ) where
import Bag (bagToList)
import ConLike (ConLike(..))
import qualified Data.ByteString as BS
import Data.Hashable (Hashable,hash)
import qualified Data.ByteString.Internal as BSI
import Data.Char (isAlpha, isAlphaNum, isAscii, ord)
import Data.Either (either)
import Data.Generics (Data)
import Data.Generics.SYB (everything, everywhere, mkQ, mkT)
import qualified Data.Generics.Uniplate.Data()
import qualified Data.HashMap.Strict as HM
import qualified Data.List as L
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import qualified Data.Text as T
import DataCon (dataConWorkId, flSelector)
import Documentation.Haddock.Parser (overIdentifier, parseParas)
import Documentation.Haddock.Types (DocH(..),
                                    Header(..),
                                    _doc
 )
import DynFlags ()
import FastString (mkFastString, unpackFS)
import GHC
  ( DynFlags
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  , HsDocString
#else
  , HsDocString (..)
#endif
  , InstDecl(..)
  , ModuleName
  , Name
  , SrcSpan(..)
  , RealSrcSpan(..)
  , ClsInstDecl(..)
  , TyClDecl(..)
  , HsDataDefn(..)
  , NewOrData(..)
  , Id
  , HsGroup(..)
  , HsBindLR(..)
  , HsValBindsLR(..)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,1,0)
  , HsPatSynDetails
#else
  , HsPatSynDetails(..)
#endif
  , Located
  , IE(..)
  , TyThing(..)
  , LHsDecl
  , HsDecl(..)
  , DocDecl(..)
  , ConDecl(..)
  , HsConDetails(..)
  , ConDeclField(..)
  , DataFamInstDecl(..)
  , LSig
  , Sig(..)
  , ForeignDecl(..)
  , FixitySig(..)
  , tcdName
  , collectHsBindBinders
  , getLoc
  , hsSigType
  , getConNames
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  , NHsValBindsLR(..)
  , getConArgs
  , unpackHDS
  , NoExt(..)
  , extFieldOcc
#else
  , getConDetails
  , selectorFieldOcc
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  , tyClGroupTyClDecls
  , LIEWrappedName
  , hsGroupInstDecls
  , ieLWrappedName
#else
  , tyClGroupConcat
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
  , FamEqn(..)
#endif
  , tyConKind
  , nameSrcSpan
  , srcSpanFile
  , srcSpanStartLine
  , srcSpanEndLine
  , srcSpanStartCol
  , srcSpanEndCol
  , isExternalName
  , moduleNameString
  , recordPatSynSelectorId
  , recordPatSynPatVar
  , isGoodSrcSpan
  , isLocalId
  , isDataFamilyDecl
  , tyFamInstDeclName
  , idType
  , hsib_body
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
#else
  , tfe_pats
#endif
  , tfid_eqn
  )

import qualified HaskellCodeExplorer.Types as HCE
import HscTypes (TypeEnv, lookupTypeEnv)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
import HsExtension (GhcRn,IdP)
#endif
import IdInfo (IdDetails(..))
import InstEnv (ClsInst(..))
import Lexer (ParseResult(POk), mkPState, unP)
import Module (Module(..))
import Name
  ( isDataConNameSpace
  , isDerivedOccName
  , isInternalName
  , isSystemName
  , isTvNameSpace
  , isTyConName
  , isValNameSpace
  , isWiredInName
  , mkInternalName
  , mkOccName
  , nameModule_maybe
  , nameOccName
  , nameUnique
  , occNameFS
  , occNameSpace
  , occNameString
  , wiredInNameTyThing_maybe
  )
import OccName (OccName)
import Outputable (Outputable, ppr, showPpr, showSDoc)
import PackageConfig (packageVersion)
import Packages
  ( LookupResult(..)
  , lookupModuleWithSuggestions
  , lookupPackage
  , packageNameString
  )
import Pair (pSnd)
import Parser (parseIdentifier)
import PatSyn (PatSyn, patSynMatcher, patSynSig)
import Prelude hiding (id, span)
import RdrName (GlobalRdrEnv, RdrName(..), gre_name, lookupGRE_RdrName)
import RnEnv (dataTcOccs)
import SrcLoc (GenLocated(..), mkRealSrcLoc, unLoc)
import StringBuffer (StringBuffer(..), stringToStringBuffer)
import System.FilePath (normalise)
import TcEvidence (HsWrapper(..), tcCoercionKind)
import TcType (evVarPred)
import TyCoRep (Type(..),
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  ArgFlag(..)
#else
  VisibilityFlag(..)
#endif
 )
import TyCon (tyConName)
import Type
  ( coreView
  , expandTypeSynonyms
  , mkForAllTy
  , mkFunTy
  , mkFunTys
  , mkInvForAllTys
#if !MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  , mkNamedBinder
#endif
  , piResultTy
  , pprSigmaType
  , splitFunTy_maybe
  , tidyOpenType
  )
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
import ToIface
import IfaceType
#endif
import TysWiredIn (unitTy)
import UniqSet (emptyUniqSet, unionUniqSets,
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
   nonDetEltsUniqSet
#else
   uniqSetToList
#endif
 )
import Unique (getKey)
import Var
  ( idDetails
  , isId
  , mkTyVar
  , setVarType
  , varName
  , varType
  , varUnique
  )
import VarEnv (TidyEnv)
import VarSet (VarSet, emptyVarSet, unionVarSet, unitVarSet
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
#else
 ,varSetElems
#endif
 )

--------------------------------------------------------------------------------
-- Pretty-printing
--------------------------------------------------------------------------------

toText :: (Outputable a) => DynFlags -> a -> T.Text
toText flags = T.pack . showSDoc flags . ppr

instanceToText :: DynFlags -> ClsInst -> T.Text
instanceToText flags ClsInst {..} =
  T.append "instance " $ T.pack . showSDoc flags $ pprSigmaType (idType is_dfun)

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
instanceDeclToText :: DynFlags -> InstDecl GhcRn -> T.Text
#else
instanceDeclToText :: DynFlags -> InstDecl Name -> T.Text
#endif
instanceDeclToText flags decl =
  case decl of
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    XInstDecl _ -> ""
    ClsInstD _ (XClsInstDecl _) -> ""
    ClsInstD _ ClsInstDecl {..} ->
#else
    ClsInstD ClsInstDecl {..} ->
#endif
      T.append "instance " (toText flags cid_poly_ty)

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    DataFamInstD _ di ->
      let args =
            T.intercalate " " . map (toText flags) .  feqn_pats  . hsib_body . dfid_eqn $ di
       in T.concat
            ["data instance ", toText flags (unLoc $ feqn_tycon . hsib_body . dfid_eqn $ di), " ", args]
    TyFamInstD _ ti ->
      let args =
            T.intercalate " " .
            map (toText flags) . feqn_pats . hsib_body . tfid_eqn $
            ti
       in T.concat
            ["type instance ", toText flags $ tyFamInstDeclName ti, " ", args]
#elif MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
    DataFamInstD di ->
      let args =
            T.intercalate " " . map (toText flags) .  feqn_pats  . hsib_body . dfid_eqn $ di
       in T.concat
            ["data instance ", toText flags (unLoc $ feqn_tycon . hsib_body . dfid_eqn $ di), " ", args]
    TyFamInstD ti ->
      let args =
            T.intercalate " " .
            map (toText flags) . feqn_pats . hsib_body . tfid_eqn $
            ti
       in T.concat
            ["type instance ", toText flags $ tyFamInstDeclName ti, " ", args]
#else
    DataFamInstD di ->
      let args =
            T.intercalate " " . map (toText flags) . hsib_body $ dfid_pats di
       in T.concat
            ["data instance ", toText flags (unLoc $ dfid_tycon di), " ", args]
    TyFamInstD ti ->
      let args =
            T.intercalate " " .
            map (toText flags) . hsib_body . tfe_pats . unLoc . tfid_eqn $
            ti
       in T.concat
            ["type instance ", toText flags $ tyFamInstDeclName ti, " ", args]
#endif

nameToText :: Name -> T.Text
nameToText = T.pack . unpackFS . occNameFS . nameOccName

tyClDeclPrefix :: TyClDecl a -> T.Text
tyClDeclPrefix tyClDecl =
  let isNewTy :: TyClDecl a -> Bool
      isNewTy DataDecl {tcdDataDefn = HsDataDefn {dd_ND = NewType}} = True
      isNewTy _ = False
   in case tyClDecl of
        FamDecl {}
          | isDataFamilyDecl tyClDecl -> "data family "
          | otherwise -> "type family "
        SynDecl {} -> "type "
        DataDecl {}
          | isNewTy tyClDecl -> "newtype "
          | otherwise -> "data "
        ClassDecl {} -> "class "
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
        XTyClDecl _ -> ""
#endif

demangleOccName :: Name -> T.Text
demangleOccName name
  | isDerivedOccName (nameOccName name) =
    let removePrefix :: T.Text -> T.Text
        removePrefix occName
          | T.isPrefixOf "$sel:" occName =
            fst $ T.breakOn ":" (T.drop 5 occName)
          | T.isPrefixOf "$W" occName = T.drop 2 occName
          | T.isPrefixOf "$w" occName = T.drop 2 occName
          | T.isPrefixOf "$m" occName = T.drop 2 occName
          | T.isPrefixOf "$b" occName = T.drop 2 occName
          | T.isPrefixOf "$dm" occName = T.drop 3 occName
          | T.isPrefixOf "$c" occName = T.drop 2 occName
          | T.isPrefixOf "$d" occName = T.drop 2 occName
          | T.isPrefixOf "$i" occName = T.drop 2 occName
          | T.isPrefixOf "$s" occName = T.drop 2 occName
          | T.isPrefixOf "$f" occName = T.drop 2 occName
          | T.isPrefixOf "$r" occName = T.drop 2 occName
          | T.isPrefixOf "C:" occName = T.drop 2 occName
          | T.isPrefixOf "N:" occName = T.drop 2 occName
          | T.isPrefixOf "D:" occName = T.drop 2 occName
          | T.isPrefixOf "$co" occName = T.drop 3 occName
          | otherwise = occName
     in removePrefix $ nameToText name
  | otherwise = nameToText name

stringBufferToByteString :: StringBuffer -> BS.ByteString
stringBufferToByteString (StringBuffer buf len cur) =
  BSI.fromForeignPtr buf cur len

nameSort :: Name -> HCE.NameSort
nameSort n =
  if isExternalName n
    then HCE.External
    else HCE.Internal

occNameNameSpace :: OccName -> HCE.NameSpace
occNameNameSpace n
  | isDataConNameSpace (occNameSpace n) = HCE.DataName
  | isTvNameSpace (occNameSpace n) = HCE.TvName
  | isValNameSpace (occNameSpace n) = HCE.VarName
  | otherwise = HCE.TcClsName

-- Two 'Id''s may have different types even though they have the same 'Unique'.
identifierKey :: DynFlags -> Id -> T.Text
identifierKey flags id
  | isLocalId id =
    T.concat
      [ T.pack . show . getKey . varUnique $ id
      , "_"
      , T.pack . show . hash . showSDoc flags . ppr . varType $ id
      ]
identifierKey _ id = T.pack . show . getKey . varUnique $ id

nameKey :: Name -> T.Text
nameKey = T.pack . show . getKey . nameUnique

mbIdDetails :: Id -> Maybe HCE.IdDetails
mbIdDetails v
  | isId v =
    case idDetails v of
      VanillaId -> Just HCE.VanillaId
      RecSelId {sel_naughty = False} -> Just HCE.RecSelId
      RecSelId {sel_naughty = True} -> Just HCE.RecSelIdNaughty
      DataConWorkId _ -> Just HCE.DataConWorkId
      DataConWrapId _ -> Just HCE.DataConWrapId
      ClassOpId _ -> Just HCE.ClassOpId
      PrimOpId _ -> Just HCE.PrimOpId
      FCallId _ -> Just HCE.FCallId
      TickBoxOpId _ -> Just HCE.TickBoxOpId
      DFunId _ -> Just HCE.DFunId
      CoVarId -> Just HCE.CoVarId
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
      JoinId _ -> Just HCE.JoinId
#endif
mbIdDetails _ = Nothing

--------------------------------------------------------------------------------
--  Syntax transformation
--------------------------------------------------------------------------------

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
hsGroupVals :: HsGroup GhcRn -> [GenLocated SrcSpan (HsBindLR GhcRn GhcRn)]
#else
hsGroupVals :: HsGroup Name -> [GenLocated SrcSpan (HsBindLR Name Name)]
#endif
hsGroupVals hsGroup =
  filter (isGoodSrcSpan . getLoc) $
  case hs_valds hsGroup of
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    XValBindsLR (NValBinds binds _) -> concatMap (bagToList . snd) binds
#else
    ValBindsOut binds _ -> concatMap (bagToList . snd) binds
#endif
    _ -> []

hsPatSynDetails :: HsPatSynDetails a -> [a]
hsPatSynDetails patDetails =
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
  case patDetails of
    InfixCon name1 name2 -> [name1, name2]
    PrefixCon fields -> fields
    RecCon fields -> concatMap
        (\field -> [recordPatSynSelectorId field, recordPatSynPatVar field])
        fields
#else
  case patDetails of
    InfixPatSyn name1 name2 -> [name1, name2]
    PrefixPatSyn name -> name
    RecordPatSyn fields ->
      concatMap
        (\field -> [recordPatSynSelectorId field, recordPatSynPatVar field])
        fields
#endif


#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
unwrapName :: LIEWrappedName a -> Located a
unwrapName = ieLWrappedName
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
unwrapName :: LIEWrappedName Name -> Located Name
unwrapName = ieLWrappedName
#else
unwrapName :: Located Name -> Located Name
unwrapName n = n
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
ieLocNames :: IE pass -> [Located (IdP pass)]
#else
ieLocNames :: IE Name -> [Located Name]
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
ieLocNames (XIE _) = []
ieLocNames (IEVar _ n) =
#else
ieLocNames (IEVar n) =
#endif
  [unwrapName n]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
ieLocNames (IEThingAbs _ n) =
#else
ieLocNames (IEThingAbs n) =
#endif
  [unwrapName n]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
ieLocNames (IEThingAll _ n) =
#else
ieLocNames (IEThingAll n) =
#endif
  [unwrapName n]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
ieLocNames (IEThingWith _ n _ ns labels) =
#else
ieLocNames (IEThingWith n _ ns labels) =
#endif
  unwrapName n : (map unwrapName ns ++ map (fmap flSelector) labels)
ieLocNames IEModuleContents {} = []
ieLocNames IEGroup {} = []
ieLocNames IEDoc {} = []
ieLocNames IEDocNamed {} = []

--------------------------------------------------------------------------------
-- Lookups
--------------------------------------------------------------------------------

lookupIdInTypeEnv :: TypeEnv -> Name -> Maybe Id
lookupIdInTypeEnv typeEnv name = do
  let mbTyThing
        | isInternalName name = Nothing
        | isSystemName name = Nothing
        | isWiredInName name = wiredInNameTyThing_maybe name
        | isExternalName name = lookupTypeEnv typeEnv name
        | otherwise = Nothing
  case mbTyThing of
    Just tyThing -> tyThingToId tyThing
    _ -> Nothing

lookupNameModuleAndPackage ::
     DynFlags
  -> HCE.PackageId
  -> Name
  -> Either T.Text (HCE.HaskellModuleName, HCE.PackageId)
lookupNameModuleAndPackage flags currentPackageId name =
  case nameModule_maybe name of
    Just Module {..} ->
      case lookupPackage flags moduleUnitId of
        Just packageConfig ->
          let packageId =
                if (T.pack . packageNameString $ packageConfig) ==
                   HCE.name (currentPackageId :: HCE.PackageId)
                  then currentPackageId
                  else HCE.PackageId
                         (T.pack $ packageNameString packageConfig)
                         (PackageConfig.packageVersion packageConfig)
           in Right
                ( HCE.HaskellModuleName . T.pack . moduleNameString $ moduleName
                , packageId)
        Nothing ->
          Right
            ( HCE.HaskellModuleName . T.pack . moduleNameString $ moduleName
            , currentPackageId)
    Nothing ->
      Left $ T.concat ["nameModule_maybe ", nameToText name, " is Nothing"]

--------------------------------------------------------------------------------
-- Location info
--------------------------------------------------------------------------------

isHsBoot :: HCE.HaskellModulePath -> Bool
isHsBoot = T.isSuffixOf "-boot" . HCE.getHaskellModulePath

moduleLocationInfo ::
     DynFlags
  -> HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath)
  -> HCE.PackageId
  -> HCE.ComponentId
  -> ModuleName
  -> HCE.LocationInfo
moduleLocationInfo flags moduleNameMap currentPackageId compId moduleName =
  let moduleNameText = T.pack . moduleNameString $ moduleName
      currentPackageLocation =
        HCE.ApproximateLocation
          currentPackageId
          (HCE.HaskellModuleName . T.pack . moduleNameString $ moduleName)
          HCE.Mod
          moduleNameText
          Nothing
          compId
   in case HM.lookup (HCE.HaskellModuleName moduleNameText) moduleNameMap of
        Just modulePathMap
          | Just modulePath <- HM.lookup compId modulePathMap ->
            HCE.ExactLocation
              currentPackageId
              modulePath
              (HCE.HaskellModuleName moduleNameText)
              1
              1
              1
              1
        _ ->
          case lookupModuleWithSuggestions flags moduleName Nothing of
            LookupFound Module {moduleUnitId = unitId} _ ->
              case lookupPackage flags unitId of
                Just packInfo ->
                  let packageId =
                        HCE.PackageId
                          (T.pack $ packageNameString packInfo)
                          (PackageConfig.packageVersion packInfo)
                   in HCE.ApproximateLocation
                        packageId
                        (HCE.HaskellModuleName . T.pack . moduleNameString $
                         moduleName)
                        HCE.Mod
                        moduleNameText
                        Nothing
                        (if packageId == currentPackageId
                           then compId
                           else HCE.ComponentId "lib")
                Nothing -> currentPackageLocation
            _ -> currentPackageLocation

isDefinedInCurrentModule ::
     HCE.SourceCodeTransformation -> HCE.HaskellFilePath -> Bool
isDefinedInCurrentModule transformation file =
  let includedFiles = HM.keys $ HCE.fileIndex transformation
      modPath =
        HCE.getHaskellModulePath $
        HCE.filePath (transformation :: HCE.SourceCodeTransformation)
   in HCE.getHaskellFilePath file == modPath || (file `elem` includedFiles)

nameLocationInfo ::
     DynFlags
  -> HCE.PackageId
  -> HCE.ComponentId
  -> HCE.SourceCodeTransformation
  -> HM.HashMap HCE.HaskellFilePath HCE.HaskellModulePath
  -> HM.HashMap HCE.HaskellModulePath HCE.DefinitionSiteMap
  -> Maybe T.Text -- ^ Instance head (when name is a dictionary function)
  -> Maybe SrcSpan -- ^ Only for wired-in names
  -> Name
  -> HCE.LocationInfo
nameLocationInfo flags currentPackageId compId transformation fileMap defSiteMap mbInstanceHead mbSrcSpan name
  | Just srcSpan <- realSrcSpan name mbSrcSpan =
    let filePath =
          HCE.HaskellFilePath . T.pack . normalise . unpackFS . srcSpanFile $
          srcSpan
        approximateLocation =
          mkApproximateLocation
            flags
            currentPackageId
            compId
            mbInstanceHead
            name
     in if isDefinedInCurrentModule transformation filePath
          then let eitherStart =
                     HCE.fromOriginalLineNumber
                       transformation
                       (filePath, srcSpanStartLine srcSpan)
                   eitherEnd =
                     HCE.fromOriginalLineNumber
                       transformation
                       (filePath, srcSpanEndLine srcSpan)
                in case (,) eitherStart eitherEnd of
                     (Right startLine,Right endLine) ->
                         let  modulePath = HCE.filePath (transformation :: HCE.SourceCodeTransformation)
                              moduleName =
                                  either
                                    (const $ HCE.HaskellModuleName "")
                                    fst
                                    (lookupNameModuleAndPackage flags currentPackageId name)
                         in HCE.ExactLocation
                              { packageId = currentPackageId
                              , modulePath = modulePath
                              , moduleName = moduleName
                              , startLine = startLine
                              , endLine = endLine
                              , startColumn = srcSpanStartCol srcSpan
                              , endColumn = srcSpanEndCol srcSpan
                              }
                     _ -> approximateLocation
          else case HM.lookup filePath fileMap of
                 Just haskellModulePath ->
                   case HM.lookup haskellModulePath defSiteMap of
                     Just defSites ->
                       let key = fromMaybe (nameToText name) mbInstanceHead
                        in lookupEntityLocation
                             defSites
                             (mkLocatableEntity name mbInstanceHead)
                             key
                     Nothing -> approximateLocation
                 Nothing -> approximateLocation
  where
    realSrcSpan :: Name -> Maybe SrcSpan -> Maybe RealSrcSpan
    realSrcSpan n mbSpan =
      case nameSrcSpan n of
        RealSrcSpan span -> Just span
        _
          | isWiredInName n ->
            case mbSpan of
              Just span ->
                case span of
                  RealSrcSpan s -> Just s
                  _ -> Nothing
              _ -> Nothing
        _ -> Nothing
nameLocationInfo flags currentPackageId compId _transformation _fileMap _defSiteMap mbInstanceHead _mbSrcSpan name =
  mkApproximateLocation flags currentPackageId compId mbInstanceHead name

mkApproximateLocation ::
     DynFlags
  -> HCE.PackageId
  -> HCE.ComponentId
  -> Maybe T.Text
  -> Name
  -> HCE.LocationInfo
mkApproximateLocation flags currentPackageId compId mbInstanceHead name =
  let haddockAnchor =
        Just . T.pack . makeAnchorId . T.unpack . nameToText $ name
   in case lookupNameModuleAndPackage flags currentPackageId name of
        Right (moduleName, packageId) ->
          HCE.ApproximateLocation
            { moduleName = moduleName
            , packageId = packageId
            , componentId =
                if packageId == currentPackageId
                  then compId
                  else HCE.ComponentId "lib"
            , entity = mkLocatableEntity name mbInstanceHead
            , haddockAnchorId = haddockAnchor
            , name = fromMaybe (nameToText name) mbInstanceHead
            }
        Left errorMessage -> HCE.UnknownLocation errorMessage

mkLocatableEntity :: Name -> Maybe a -> HCE.LocatableEntity
mkLocatableEntity name mbInstanceHead
  | isJust mbInstanceHead = HCE.Inst
  | otherwise =
    case occNameNameSpace . nameOccName $ name of
      HCE.VarName -> HCE.Val
      HCE.DataName -> HCE.Val
      _ -> HCE.Typ

occNameLocationInfo ::
     DynFlags
  -> HCE.PackageId
  -> HCE.ComponentId
  -> (ModuleName, OccName)
  -> HCE.LocationInfo
occNameLocationInfo flags packageId componentId (modName, occName) =
  HCE.ApproximateLocation
    { packageId = packageId
    , moduleName = HCE.HaskellModuleName $ toText flags modName
    , entity =
        case occNameNameSpace occName of
          HCE.VarName -> HCE.Val
          HCE.DataName -> HCE.Val
          _ -> HCE.Typ
    , name = toText flags occName
    , haddockAnchorId =
        Just . T.pack . makeAnchorId . T.unpack $ toText flags occName
    , componentId = componentId
    }

lookupEntityLocation ::
     HCE.DefinitionSiteMap -> HCE.LocatableEntity -> T.Text -> HCE.LocationInfo
lookupEntityLocation defSiteMap locatableEntity text =
  let errorMessage =
        T.concat
          [ "Cannot find location of "
          , T.pack . show $ locatableEntity
          , " "
          , text
          ]
      defSiteLocation = HCE.location :: HCE.DefinitionSite -> HCE.LocationInfo
      lookupLocation ::
           (Eq a, Hashable a)
        => (HCE.DefinitionSiteMap -> HM.HashMap a HCE.DefinitionSite)
        -> (T.Text -> a)
        -> HCE.LocationInfo
      lookupLocation selector toKey =
        maybe (HCE.UnknownLocation errorMessage) defSiteLocation $
        HM.lookup (toKey text) (selector defSiteMap)
   in case locatableEntity of
        HCE.Val -> lookupLocation HCE.values HCE.OccName
        HCE.Typ -> lookupLocation HCE.types HCE.OccName
        HCE.Inst -> lookupLocation HCE.instances (\t -> t)
        HCE.Mod -> HCE.UnknownLocation errorMessage

nameDocumentation ::
     HCE.SourceCodeTransformation
  -> HM.HashMap HCE.HaskellFilePath HCE.HaskellModulePath
  -> HM.HashMap HCE.HaskellModulePath HCE.DefinitionSiteMap
  -> HCE.DefinitionSiteMap
  -> Name
  -> Maybe T.Text
nameDocumentation transformation fileMap defSiteMap currentModuleDefSiteMap name
  | isExternalName name || isWiredInName name
  , Just file <- srcSpanToFilePath . nameSrcSpan $ name =
    if isDefinedInCurrentModule transformation file
      then lookupNameDocumentation name currentModuleDefSiteMap
      else case HM.lookup file fileMap of
             Just haskellModulePath ->
               case HM.lookup haskellModulePath defSiteMap of
                 Just defSites -> lookupNameDocumentation name defSites
                 Nothing -> Nothing
             Nothing -> Nothing
nameDocumentation _ _ _ _ _ = Nothing

lookupNameDocumentation :: Name -> HCE.DefinitionSiteMap -> Maybe T.Text
lookupNameDocumentation name defSiteMap =
  let key = HCE.OccName $ nameToText name
      lookupDoc ::
           (HCE.DefinitionSiteMap -> HM.HashMap HCE.OccName HCE.DefinitionSite)
        -> Maybe T.Text
      lookupDoc selector =
        maybe Nothing HCE.documentation $
        HM.lookup key (selector (defSiteMap :: HCE.DefinitionSiteMap))
   in case occNameNameSpace . nameOccName $ name of
        HCE.VarName -> lookupDoc HCE.values
        HCE.DataName -> lookupDoc HCE.values
        _ -> lookupDoc HCE.types

srcSpanToFilePath :: SrcSpan -> Maybe HCE.HaskellFilePath
srcSpanToFilePath (RealSrcSpan s) =
  Just . HCE.HaskellFilePath . T.pack . normalise . unpackFS . srcSpanFile $ s
srcSpanToFilePath (UnhelpfulSpan _) = Nothing

srcSpanToLineAndColNumbers ::
     HCE.SourceCodeTransformation
  -> SrcSpan
  -> Maybe (HCE.HaskellFilePath, (Int, Int), (Int, Int))
srcSpanToLineAndColNumbers transformation (RealSrcSpan s) =
  let filePath =
        HCE.HaskellFilePath . T.pack . normalise . unpackFS . srcSpanFile $ s
      eitherStart =
        HCE.fromOriginalLineNumber transformation (filePath, srcSpanStartLine s)
      eitherEnd =
        HCE.fromOriginalLineNumber transformation (filePath, srcSpanEndLine s)
   in case (,) eitherStart eitherEnd of
        (Right startLine, Right endLine) ->
          Just
            ( filePath
            , (startLine, srcSpanStartCol s)
            , (endLine, srcSpanEndCol s))
        _ -> Nothing
srcSpanToLineAndColNumbers _ _ = Nothing

--------------------------------------------------------------------------------
-- Type-related functions
--------------------------------------------------------------------------------

tyThingToId :: TyThing -> Maybe Id
tyThingToId tyThing =
  case tyThing of
    AnId id -> Just id
    ATyCon tc -> Just $ mkTyVar (tyConName tc) (tyConKind tc)
    AConLike con ->
      case con of
        RealDataCon dataCon -> Just $ dataConWorkId dataCon
        PatSynCon ps -> Just $ patSynId ps
    ACoAxiom _ -> Nothing

tidyIdentifierType :: TidyEnv -> Id -> (TidyEnv, Id)
tidyIdentifierType tidyEnv identifier =
  let (tidyEnv', typ') = tidyOpenType tidyEnv (varType identifier)
   in (tidyEnv', setVarType identifier typ')

patSynId :: PatSyn -> Id
patSynId patSyn =
  let (univTvs, reqTheta, exTvs, provTheta, argTys, resTy) = patSynSig patSyn
      reqTheta'
        | null reqTheta && not (null provTheta && null exTvs) = [unitTy]
        | otherwise = reqTheta
      --  required => provided => arg_1 -> ... -> arg_n -> res
      patSynTy =
        mkInvForAllTys univTvs $
        mkFunTys reqTheta' $
        mkInvForAllTys exTvs $ mkFunTys provTheta $ mkFunTys argTys resTy
   in flip setVarType patSynTy . fst . patSynMatcher $ patSyn

applyWrapper :: HsWrapper -> Type -> Type
applyWrapper wp ty
  | Just ty' <- coreView ty = applyWrapper wp ty'
applyWrapper WpHole t = t
applyWrapper (WpCompose w1 w2) t = applyWrapper w1 . applyWrapper w2 $ t
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
applyWrapper (WpFun w1 w2 t1 _doc) t = mkFunTy t1 (applyWrapper w2 $ piResultTy t (applyWrapper w1 t1))
#else
applyWrapper (WpFun w1 w2 t1) t = mkFunTy t1 (applyWrapper w2 $ piResultTy t (applyWrapper w1 t1))
#endif
applyWrapper (WpCast coercion) _t = pSnd $ tcCoercionKind coercion
applyWrapper (WpEvLam v) t = mkFunTy (evVarPred v) t
applyWrapper (WpEvApp _ev) t = case splitFunTy_maybe t of
  Just (_arg,res) -> res
  Nothing -> t
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
applyWrapper (WpTyLam v) t = mkForAllTy v Required t
#else
applyWrapper (WpTyLam v) t = mkForAllTy (mkNamedBinder Invisible v) t
#endif
applyWrapper (WpTyApp t') t = piResultTy t t'
applyWrapper (WpLet _) t = t

wrapperTypes :: HsWrapper -> [Type]
wrapperTypes WpHole  = []
wrapperTypes (WpCompose w1 w2) = wrapperTypes w2 ++ wrapperTypes w1
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
wrapperTypes (WpFun w1 w2 _ _) = wrapperTypes w2 ++ wrapperTypes w1
#else
wrapperTypes (WpFun w1 w2 _) = wrapperTypes w2 ++ wrapperTypes w1
#endif
wrapperTypes (WpCast _)  = []
wrapperTypes (WpEvLam _) = []
wrapperTypes (WpEvApp _) = []
wrapperTypes (WpTyLam _) = []
wrapperTypes (WpTyApp t) = [t]
wrapperTypes (WpLet _) = []

mkType :: DynFlags -> Type -> HCE.Type
mkType flags typ =
  let typeExpanded = expandTypeSynonyms typ
      typeComponents = toTypeComponents flags typ
      typeComponentsExpanded = toTypeComponents flags typeExpanded
   in HCE.Type
        typeComponents
        (if typeComponents /= typeComponentsExpanded
           then Just typeComponentsExpanded
           else Nothing)

#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
typeToText :: DynFlags -> Type -> T.Text
typeToText flags = T.pack . showSDoc flags . pprIfaceType . toIfaceType
#else
typeToText :: DynFlags -> Type -> T.Text
typeToText = toText
#endif

toTypeComponents :: DynFlags -> Type -> [HCE.TypeComponent]
toTypeComponents flags typ =
  let signature =
        typeToText flags $
        updateOccNames (\_unique occName -> ";" ++ drop 2 occName ++ ";") typ
      -- Signature with OccNames and uniques
      signatureWithUniques =
        typeToText flags $
        updateOccNames
          (\unique occName -> ";," ++ occName ++ "," ++ unique ++ ";")
          typ
      -- Dirty but simple way to extract a list of TypeComponent from a type signature.
      -- Assumptions :
      -- 1. Character ';' cannot appear anywhere in a type signature
      -- 2. Character ',' cannot appear in an 'OccName'
      -- 3. length (T.splitOn ";" signature) == length (T.splitOn ";" signatureWithUniques)
      components =
        L.zip (T.splitOn ";" signature) (T.splitOn ";" signatureWithUniques)
   in mapMaybe
        (\(text1, text2) ->
           if T.isPrefixOf "," text2
             then case T.splitOn "," text2 of
                    ["", name, id] ->
                      Just HCE.TyCon {name = name, internalId = HCE.InternalId id}
                    _ -> Just $ HCE.Text text1
             else if T.null text1
                    then Nothing
                    else Just $ HCE.Text text1)
        components

-- | Replaces 'OccName' of each type variable and type constructor in a type.
updateOccNames :: (String -> String -> String) -> Type -> Type
updateOccNames update = everywhere (mkT updateType)
  where
    updateType :: Type -> Type
    updateType (TyVarTy var) = TyVarTy var {varName = updateName (varName var)}
    updateType (TyConApp con args) =
      TyConApp (con {tyConName = updateName (tyConName con)}) args
    updateType other = other
    updateName :: Name -> Name
    updateName oldName =
      let oldOccName = nameOccName oldName
          unique = T.unpack $ nameKey oldName
          newOccName =
            mkOccName
              (occNameSpace oldOccName)
              (update unique (occNameString oldOccName))
       in mkInternalName (nameUnique oldName) newOccName (nameSrcSpan oldName)

-- | This function doesn't look through type synonyms
tyConsOfType :: Type -> [Id]
tyConsOfType =
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  nonDetEltsUniqSet . everything unionUniqSets (emptyVarSet `mkQ` tyCon)
#else
  uniqSetToList . everything unionUniqSets (emptyVarSet `mkQ` tyCon)
#endif
  where
    tyCon :: Type -> VarSet
    tyCon (TyConApp tc _) = unitVarSet $ mkTyVar (tyConName tc) (tyConKind tc)
    tyCon _ = emptyUniqSet

tyVarsOfType :: (Data a) => a -> [Id]
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
tyVarsOfType = nonDetEltsUniqSet . everything unionVarSet (emptyVarSet `mkQ` tyVar)
#else
tyVarsOfType = varSetElems . everything unionVarSet (emptyVarSet `mkQ` tyVar)
#endif
  where
    tyVar :: Type -> VarSet
    tyVar (TyVarTy ty) = unitVarSet ty
    tyVar _ = emptyVarSet

--------------------------------------------------------------------------------
-- Documentation processing
-- Some functions are copied from haddock-api package
--------------------------------------------------------------------------------

collectDocs :: [LHsDecl a] -> [(LHsDecl a, [HsDocString])]
collectDocs = go Nothing []
  where
    go Nothing _ [] = []
    go (Just prev) docs [] = finished prev docs []
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    go prev docs (L _ (DocD _ (DocCommentNext str)):ds)
#else
    go prev docs (L _ (DocD (DocCommentNext str)):ds)
#endif

      | Nothing <- prev = go Nothing (str : docs) ds
      | Just decl <- prev = finished decl docs (go Nothing [str] ds)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    go prev docs (L _ (DocD _ (DocCommentPrev str)):ds) = go prev (str : docs) ds
#else
    go prev docs (L _ (DocD (DocCommentPrev str)):ds) = go prev (str : docs) ds
#endif
    go Nothing docs (d:ds) = go (Just d) docs ds
    go (Just prev) docs (d:ds) = finished prev docs (go (Just d) [] ds)
    finished decl docs rest = (decl, reverse docs) : rest

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
ungroup :: HsGroup GhcRn -> [LHsDecl GhcRn]
#else
ungroup :: HsGroup Name -> [LHsDecl Name]
#endif
ungroup group_ =
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  mkDecls (tyClGroupTyClDecls . hs_tyclds) (TyClD NoExt) group_ ++
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  mkDecls (tyClGroupTyClDecls . hs_tyclds) TyClD group_ ++
#else
  mkDecls (tyClGroupConcat . hs_tyclds) TyClD group_ ++
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  mkDecls hs_derivds (DerivD NoExt) group_ ++
  mkDecls hs_defds (DefD NoExt) group_ ++
  mkDecls hs_fords (ForD NoExt) group_ ++
  mkDecls hs_docs (DocD NoExt) group_ ++
#else
  mkDecls hs_derivds DerivD group_ ++
  mkDecls hs_defds DefD group_ ++
  mkDecls hs_fords ForD group_ ++
  mkDecls hs_docs DocD group_ ++
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  mkDecls hsGroupInstDecls (InstD NoExt) group_ ++
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  mkDecls hsGroupInstDecls InstD group_ ++
#else
  mkDecls hs_instds InstD group_ ++
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  mkDecls (typesigs . hs_valds) (SigD NoExt) group_ ++
  mkDecls (valbinds . hs_valds) (ValD NoExt) group_
#else
  mkDecls (typesigs . hs_valds) SigD group_ ++
  mkDecls (valbinds . hs_valds) ValD group_
#endif


  where
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    typesigs (XValBindsLR (NValBinds _ sigs)) = filter isUserLSig sigs
#else
    typesigs (ValBindsOut _ sigs) = filter isUserLSig sigs
#endif
    typesigs _ = []
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    valbinds (XValBindsLR (NValBinds binds _)) = concatMap (bagToList . snd) binds
#else
    valbinds (ValBindsOut binds _) = concatMap (bagToList . snd) binds
#endif
    valbinds _ = []

mkDecls :: (a -> [Located b]) -> (b -> c) -> a -> [Located c]
mkDecls field con struct = [L loc (con decl) | L loc decl <- field struct]

sortByLoc :: [Located a] -> [Located a]
sortByLoc = L.sortOn getLoc

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
classDeclDocs :: TyClDecl GhcRn -> [(LHsDecl GhcRn, [HsDocString])]
#else
classDeclDocs :: TyClDecl Name -> [(LHsDecl Name, [HsDocString])]
#endif
classDeclDocs class_ = collectDocs . sortByLoc $ decls
  where
    decls = docs ++ defs ++ sigs ++ ats
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    docs = mkDecls tcdDocs (DocD NoExt) class_
    defs = mkDecls (bagToList . tcdMeths) (ValD NoExt) class_
    sigs = mkDecls tcdSigs (SigD NoExt) class_
    ats = mkDecls tcdATs ((TyClD NoExt) . (FamDecl NoExt)) class_
#else
    docs = mkDecls tcdDocs DocD class_
    defs = mkDecls (bagToList . tcdMeths) ValD class_
    sigs = mkDecls tcdSigs SigD class_
    ats = mkDecls tcdATs (TyClD . FamDecl) class_
#endif


#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
conDeclDocs :: ConDecl GhcRn -> [(Name, [HsDocString], SrcSpan)]
#else
conDeclDocs :: ConDecl Name -> [(Name, [HsDocString], SrcSpan)]
#endif
conDeclDocs conDecl =
  map (\(L span n) -> (n, maybe [] ((: []) . unLoc) $ con_doc conDecl, span)) .
  getConNames $
  conDecl

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
selectorDocs :: ConDecl GhcRn -> [(Name, [HsDocString], SrcSpan)]
#else
selectorDocs :: ConDecl Name -> [(Name, [HsDocString], SrcSpan)]
#endif
selectorDocs con =
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  case getConArgs con of
#else
  case getConDetails con of
#endif
    RecCon (L _ flds) ->
      concatMap
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
        (\(L _ (ConDeclField _ fieldOccs _ mbDoc)) ->
#else
        (\(L _ (ConDeclField fieldOccs _ mbDoc)) ->
#endif
           map
             (\(L span f) ->
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
                (extFieldOcc f, maybe [] ((: []) . unLoc) mbDoc, span))
#else
                (selectorFieldOcc f, maybe [] ((: []) . unLoc) mbDoc, span))
#endif
             fieldOccs)
        flds
    _ -> []

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
subordinateNamesWithDocs :: [GenLocated SrcSpan (HsDecl GhcRn)] -> [(Name, [HsDocString], SrcSpan)]
#else
subordinateNamesWithDocs :: [GenLocated SrcSpan (HsDecl Name)] -> [(Name, [HsDocString], SrcSpan)]
#endif
subordinateNamesWithDocs =
    concatMap
    (\(L span tyClDecl) ->
       case tyClDecl of
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
         TyClD _ classDecl@ClassDecl {..} ->
#else
         TyClD classDecl@ClassDecl {..} ->
#endif
           concatMap
             (\(L _ decl, docs) -> map (, docs, span) $ getMainDeclBinder decl) $
           classDeclDocs classDecl
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
         TyClD _ DataDecl {..} ->
#else
         TyClD DataDecl {..} ->
#endif
           concatMap (\(L _ con) -> conDeclDocs con ++ selectorDocs con) $
           dd_cons tcdDataDefn
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
         InstD _ (DataFamInstD _ DataFamInstDecl {..}) ->
#else
         InstD (DataFamInstD DataFamInstDecl {..}) ->
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
           concatMap (conDeclDocs . unLoc) . dd_cons . feqn_rhs  . hsib_body $ dfid_eqn
#else
           concatMap (conDeclDocs . unLoc) . dd_cons $ dfid_defn
#endif
         _ -> [])


isUserLSig :: LSig name -> Bool
isUserLSig (L _ TypeSig {})    = True
isUserLSig (L _ ClassOpSig {}) = True
isUserLSig _ = False

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
getMainDeclBinder :: HsDecl pass -> [IdP pass]
#else
getMainDeclBinder :: HsDecl name -> [name]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
getMainDeclBinder (TyClD _ d) =
#else
getMainDeclBinder (TyClD d) =
#endif
  [tcdName d]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
getMainDeclBinder (ValD _ d) =
#else
getMainDeclBinder (ValD d) =
#endif
  case collectHsBindBinders d of
    [] -> []
    (name:_) -> [name]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
getMainDeclBinder (SigD _ d) = sigNameNoLoc d
#else
getMainDeclBinder (SigD d) = sigNameNoLoc d
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
getMainDeclBinder (ForD _ (ForeignImport _ name _ _)) = [unLoc name]
#else
getMainDeclBinder (ForD (ForeignImport name _ _ _)) = [unLoc name]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
getMainDeclBinder (ForD _ ForeignExport {}) = []
#else
getMainDeclBinder (ForD ForeignExport {}) = []
#endif
getMainDeclBinder _ = []

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
sigNameNoLoc :: Sig pass -> [IdP pass]
#else
sigNameNoLoc :: Sig name -> [name]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNameNoLoc (TypeSig _ ns _) = map unLoc ns
#else
sigNameNoLoc (TypeSig ns _) = map unLoc ns
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNameNoLoc (ClassOpSig _ _ ns _) = map unLoc ns
#else
sigNameNoLoc (ClassOpSig _ ns _) = map unLoc ns
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNameNoLoc (PatSynSig _ ns _) = map unLoc ns
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
sigNameNoLoc (PatSynSig ns _) = map unLoc ns
#else
sigNameNoLoc (PatSynSig n _) = [unLoc n]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNameNoLoc (SpecSig _ n _ _) = [unLoc n]
#else
sigNameNoLoc (SpecSig n _ _) = [unLoc n]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNameNoLoc (InlineSig _ n _) = [unLoc n]
#else
sigNameNoLoc (InlineSig n _) = [unLoc n]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNameNoLoc (FixSig _ (FixitySig _ ns _)) = map unLoc ns
#else
sigNameNoLoc (FixSig (FixitySig ns _)) = map unLoc ns
#endif
sigNameNoLoc _                         = []

clsInstDeclSrcSpan :: ClsInstDecl a -> SrcSpan
clsInstDeclSrcSpan ClsInstDecl {cid_poly_ty = ty} = getLoc (hsSigType ty)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
clsInstDeclSrcSpan (XClsInstDecl _) = UnhelpfulSpan "XClsinstdecl"
#endif

hsDocsToDocH :: DynFlags -> GlobalRdrEnv -> [HsDocString] -> Doc Name
hsDocsToDocH flags rdrEnv =
  rename flags rdrEnv .
  overIdentifier (parseIdent flags) .
  _doc
#if MIN_VERSION_haddock_library(1,6,0)
    . parseParas Nothing
#else
    . parseParas
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    . concatMap unpackHDS
#else
    . concatMap (unpackFS . (\(HsDocString s) -> s))
#endif

parseIdent :: DynFlags -> String -> Maybe RdrName
parseIdent dflags str0 =
  let buffer = stringToStringBuffer str0
      realSrcLc = mkRealSrcLoc (mkFastString "<unknown file>") 0 0
      pstate = mkPState dflags buffer realSrcLc
  in case unP parseIdentifier pstate of
    POk _ name -> Just (unLoc name)
    _ -> Nothing

type Doc id = DocH (ModuleName, OccName) id

rename :: DynFlags -> GlobalRdrEnv -> Doc RdrName -> Doc Name
rename dflags gre = rn
  where
    rn d = case d of
      DocAppend a b -> DocAppend (rn a) (rn b)
      DocParagraph doc -> DocParagraph (rn doc)
      DocIdentifier x -> do
        -- Generate the choices for the possible kind of thing this
        -- is.
        let choices = dataTcOccs x
        -- Try to look up all the names in the GlobalRdrEnv that match
        -- the names.
        let names = concatMap (\c -> map gre_name (lookupGRE_RdrName c gre)) choices

        case names of
          -- We found no names in the env so we start guessing.
          [] ->
            case choices of
              [] -> DocMonospaced (DocString (showPpr dflags x))
              -- There was nothing in the environment so we need to
              -- pick some default from what's available to us. We
              -- diverge here from the old way where we would default
              -- to type constructors as we're much more likely to
              -- actually want anchors to regular definitions than
              -- type constructor names (such as in #253). So now we
              -- only get type constructor links if they are actually
              -- in scope.
              a:_ -> outOfScope dflags a

          -- There is only one name in the environment that matches so
          -- use it.
          [a] -> DocIdentifier a
          -- But when there are multiple names available, default to
          -- type constructors: somewhat awfully GHC returns the
          -- values in the list positionally.
          a:b:_ | isTyConName a -> DocIdentifier a
                | otherwise -> DocIdentifier b

      DocWarning doc -> DocWarning (rn doc)
      DocEmphasis doc -> DocEmphasis (rn doc)
      DocBold doc -> DocBold (rn doc)
      DocMonospaced doc -> DocMonospaced (rn doc)
      DocUnorderedList docs -> DocUnorderedList (map rn docs)
      DocOrderedList docs -> DocOrderedList (map rn docs)
      DocDefList list -> DocDefList [ (rn a, rn b) | (a, b) <- list ]
      DocCodeBlock doc -> DocCodeBlock (rn doc)
      DocIdentifierUnchecked x -> DocIdentifierUnchecked x
      DocModule str -> DocModule str
      DocHyperlink l -> DocHyperlink l
      DocPic str -> DocPic str
      DocMathInline str -> DocMathInline str
      DocMathDisplay str -> DocMathDisplay str
      DocAName str -> DocAName str
      DocProperty p -> DocProperty p
      DocExamples e -> DocExamples e
      DocEmpty -> DocEmpty
      DocString str -> DocString str
      DocHeader (Header l t) -> DocHeader $ Header l (rn t)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
      DocTable t -> DocTable (rn <$> t)
#endif

-- | Wrap an identifier that's out of scope (i.e. wasn't found in
-- 'GlobalReaderEnv' during 'rename') in an appropriate doc. Currently
-- we simply monospace the identifier in most cases except when the
-- identifier is qualified: if the identifier is qualified then we can
-- still try to guess and generate anchors accross modules but the
-- users shouldn't rely on this doing the right thing. See tickets
-- #253 and #375 on the confusion this causes depending on which
-- default we pick in 'rename'.
outOfScope :: DynFlags -> RdrName -> Doc a
outOfScope dflags x =
  case x of
    Unqual occ -> monospaced occ
    Qual mdl occ -> DocIdentifierUnchecked (mdl, occ)
    Orig _ occ -> monospaced occ
    Exact name -> monospaced name -- Shouldn't happen since x is out of scope
  where
    monospaced :: (Outputable a) => a -> Doc b
    monospaced a = DocMonospaced (DocString (showPpr dflags a))

makeAnchorId :: String -> String
makeAnchorId [] = []
makeAnchorId (f:r) = escape isAlpha f ++ concatMap (escape isLegal) r
  where
    escape p c | p c = [c]
               | otherwise = '-' : show (ord c) ++ "-"
    isLegal ':' = True
    isLegal '_' = True
    isLegal '.' = True
    isLegal c = isAscii c && isAlphaNum c
