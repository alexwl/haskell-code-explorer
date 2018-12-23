{-# LANGUAGE CPP #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module HaskellCodeExplorer.AST.TypecheckedSource
  ( ASTState(..)
  , Environment(..)
  , TypeError(..)
  , foldTypecheckedSource
  , mkIdentifierInfo
  , mkIdentifierOccurrence
  , mkType
  , removeOverlappingInterval
  ) where

import Bag (bagToList)
import BasicTypes (Origin(..))
import Class (Class, classTyVars)
import ConLike (ConLike(..),conLikeWrapId_maybe)
import Control.Monad (return, unless, void)
import Control.Monad.State.Strict (State, get, modify')
import qualified Data.HashMap.Strict as HM
import qualified Data.IntMap.Strict as IM
import qualified Data.IntervalMap.Strict as IVM
import qualified Data.Map.Strict as M
import Data.Maybe (Maybe, fromMaybe, mapMaybe)
import qualified Data.Set as S
import qualified Data.Text as T
import DataCon (dataConWorkId)
import DynFlags (DynFlags)
import FastString (mkFastString)
import HaskellCodeExplorer.GhcUtils
import qualified HaskellCodeExplorer.Types as HCE
import HsBinds (HsPatSynDetails(..), RecordPatSynField(..))
import HsSyn
  ( ABExport(..)
  , ApplicativeArg(..)
  , ArithSeqInfo(..)
  , FieldOcc(..)
  , GRHS(..)
  , GRHSs(..)
  , HsBindLR(..)
  , HsCmd(..)
  , HsCmdTop(..)
  , HsConDetails(..)
  , HsConPatDetails
  , HsExpr(..)
  , HsLocalBindsLR(..)
  , HsOverLit(..)
  , HsRecField'(..)
  , HsRecFields(..)
  , HsTupArg(..)
  , HsValBindsLR(..)
  , HsValBindsLR(..)
  , LGRHS
  , LHsBindLR
  , LHsBinds
  , LHsCmd
  , LHsCmd
  , LHsCmdTop
  , LHsExpr
  , LHsRecField
  , LHsRecUpdField
  , LHsTupArg
  , LMatch
  , LPat
  , LStmtLR
  , Match(..)
  , Match(..)
  , MatchGroup(..)
  , ParStmtBlock(..)
  , Pat(..)
  , PatSynBind(..)
  , StmtLR(..)
  , selectorAmbiguousFieldOcc
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
  , RecordConTc (..)
  , RecordUpdTc (..)
  , ListPatTc (..)
  , OverLitTc (..)
  , MatchGroupTc (..)
  , NHsValBindsLR (..)  
#endif
  )
import HscTypes (TypeEnv, lookupTypeEnv)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
import HsExtension (GhcTc)
#endif
import Id (idType)
import IdInfo (IdDetails(..))
import InstEnv
  ( ClsInst(..)
  , InstEnvs
  , instanceSig
  , is_dfun
  , lookupUniqueInstEnv
  )
import Name (Name, nameOccName, nameUnique)
import Prelude hiding (span)
import SrcLoc (GenLocated(..), SrcSpan(..), isGoodSrcSpan, isOneLineSpan, unLoc)
import TcEvidence (HsWrapper(..))
import TcHsSyn (conLikeResTy, hsLitType)
import Type
  ( TyThing(..)
  , Type
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  , nonDetCmpTypes
#else
  , cmpTypes  
#endif
  , eqTypes
  , eqType
  , getClassPredTys_maybe
  , mkFunTy
  , mkFunTys
  , splitForAllTys
  , splitFunTy_maybe
  , splitFunTys
  , substTys
  , tidyOpenType
  , zipTvSubst
  )
import TysWiredIn (mkListTy, mkTupleTy)
import Unique (getKey)
import Var (Id, Var, idDetails, isId, setVarName, setVarType, varName, varType)
import VarEnv (TidyEnv)

data ASTState = ASTState
  { astStateExprInfoMap :: !HCE.ExpressionInfoMap
  -- ^ Type of each expression
  , astStateIdOccMap :: !HCE.IdentifierOccurrenceMap
  -- ^ Each occurrence of an identifier in a source code
  , astStateIdSrcSpanMap :: !(M.Map SrcSpan (Var, Maybe (Type, [Type])))
  -- ^ Intermediate data structure that is used to populate 'IdentifierOccurrenceMap'
  -- and 'IdentifierInfoMap'.
  -- 'SrcSpan' - location of an identifier in a source code
  -- 'Type' - 'expected' type of an identifier
  -- '[Type]' - types at which type variables are instantiated
  , astStateTidyEnv :: !TidyEnv
  -- ^ 'TidyEnv' is used to prevent name clashes of free type variables.
  -- ('TidyEnv' contains all free type variables in scope)
  , astStateHsWrapper :: !(Maybe HsWrapper)
  -- ^ HsWrapper comes from 'HsWrap' constructor of 'HsExpr' datatype.
  , astStateEnv :: !Environment
  -- ^ 'Environment' doesn't change
  , astStateTypeErrors :: [TypeError]
  -- ^ Non-empty list of TypeError's indicates that most likely there is a bug in
  -- a fold_something function in this module.
  }

-- | A 'TypeError' means that an assumption about a type of an AST node is incorrect.
data TypeError = TypeError
  { typeErrorSrcSpan :: SrcSpan
  , typeErrorMessage :: T.Text
  , typeErrorASTNodeName :: T.Text
  } deriving (Show, Eq)

data Environment = Environment
  { envDynFlags :: DynFlags
  , envTypeEnv :: TypeEnv
  , envInstEnv :: InstEnvs
  , envTransformation :: HCE.SourceCodeTransformation
  , envPackageId :: HCE.PackageId
  , envCurrentModuleDefSites :: HCE.DefinitionSiteMap
  , envFileMap :: HM.HashMap HCE.HaskellFilePath HCE.HaskellModulePath
  , envDefSiteMap :: HM.HashMap HCE.HaskellModulePath HCE.DefinitionSiteMap
  , envModuleNameMap :: HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath)
  , envExportedNames :: S.Set Name
  , envComponentId :: HCE.ComponentId
  }

-- | Indicates whether an expression consists of more than one token.
-- Simple expression : wildcard, literal
-- Composite expressin : applcation, lambda abstraction,...
data ExprSort
  = Simple
  | Composite
  deriving (Show, Eq)

exprSort :: HsExpr a -> ExprSort
exprSort HsVar {} = Simple
exprSort HsIPVar {} = Simple
exprSort HsOverLit {} = Simple
exprSort HsLit {} = Simple

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
exprSort (ExplicitTuple _ args _)
#else
exprSort (ExplicitTuple args _)
#endif
  | null args = Simple
  | otherwise = Composite   
exprSort (ExplicitList _ _ args) 
  | null args = Simple
  | otherwise = Composite     
exprSort _ = Composite


patSort :: Pat a -> ExprSort
patSort WildPat {} = Simple
patSort LitPat {} = Simple
patSort NPat {} = Simple
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
patSort (ListPat _ pats)
#else
patSort (ListPat pats _ _)
#endif
  | null pats = Simple
  | otherwise = Composite
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
patSort (TuplePat  _ pats _)
#else
patSort (TuplePat pats _ _)
#endif
  | null pats = Simple
  | otherwise = Composite
patSort _ = Composite

-- | Splits a type of a function, adds 'TypeError' to 'ASTState'
-- in case of failure.
splitFunTySafe ::
     SrcSpan -> T.Text -> Type -> State ASTState (Maybe (Type, Type))
splitFunTySafe srcSpan astNode typ =
  case splitFunTy_maybe typ of
    Just (ty1, ty2) -> return $ Just (ty1, ty2)
    Nothing -> do
      flags <- envDynFlags . astStateEnv <$> get
      let typeError =
            TypeError
              { typeErrorSrcSpan = srcSpan
              , typeErrorMessage = T.append "splitFunTy : " $ toText flags typ
              , typeErrorASTNodeName = astNode
              }
      modify'
        (\st -> st {astStateTypeErrors = typeError : astStateTypeErrors st})
      return Nothing
      
-- | Splits a type of a function of two arguments, adds
-- 'TypeError' to 'ASTState' in case of a failure.
splitFunTy2Safe ::
     SrcSpan -> T.Text -> Type -> State ASTState (Maybe (Type, Type, Type))
splitFunTy2Safe srcSpan astNode typ = do
  tys <- splitFunTySafe srcSpan astNode typ
  case tys of
    Just (arg1, ty1) -> do
      res <- splitFunTySafe srcSpan astNode ty1
      case res of
        Just (arg2, ty2) -> return $ Just (arg1, arg2, ty2)
        Nothing -> return Nothing
    Nothing -> return Nothing
 
-- | Returns result type of a function, adds 'TypeError' to
-- 'ASTState' in case of a failure.
funResultTySafe :: SrcSpan -> T.Text -> Type -> State ASTState (Maybe Type)
funResultTySafe srcSpan astNode typ =
  fmap snd <$> splitFunTySafe srcSpan astNode typ

-- | Returns result type of a function of two arguments,
-- adds 'TypeError' to 'ASTState' in case of a failure.
funResultTy2Safe :: SrcSpan -> T.Text -> Type -> State ASTState (Maybe Type)
funResultTy2Safe srcSpan astNode typ = do
  mbResTy1 <- funResultTySafe srcSpan astNode typ
  case mbResTy1 of
    Just resTy1 -> funResultTySafe srcSpan astNode resTy1
    Nothing -> return Nothing

addIdentifierToIdSrcSpanMap ::
     SrcSpan -> Id -> Maybe (Type, [Type]) -> State ASTState ()
addIdentifierToIdSrcSpanMap span identifier mbTypes
  | isGoodSrcSpan span =
    modify' $ \astState@ASTState {astStateIdSrcSpanMap = ids} ->
      let ids' = M.insert span (identifier, mbTypes) ids
       in astState {astStateIdSrcSpanMap = ids'}
addIdentifierToIdSrcSpanMap _ _ _ = return ()

-- | Updates 'ExpressionInfoMap' or 'IdentifierOccurrenceMap' depending
-- on 'ExprSort'.
addExprInfo :: SrcSpan -> Maybe Type -> T.Text -> ExprSort -> State ASTState ()
addExprInfo span mbType descr sort = do
  transformation <- envTransformation . astStateEnv <$> get
  case srcSpanToLineAndColNumbers transformation span of
    Just (_file,(startLine, startCol), (endLine, endCol)) -> do
      flags <- envDynFlags . astStateEnv <$> get
      mbHsWrapper <- astStateHsWrapper <$> get
      modify' $ \astState@ASTState {astStateExprInfoMap = exprInfoMap} ->
        case sort of
          Composite ->
            let exprInfo =
                  HCE.ExpressionInfo
                    {exprType = mkType flags <$> mbType, description = descr}
                interval =
                  IVM.OpenInterval (startLine, startCol) (endLine, endCol)
                exprInfoMap' = IVM.insert interval exprInfo exprInfoMap
             in astState {astStateExprInfoMap = exprInfoMap'}
          Simple ->
            let idOcc =
                  HCE.IdentifierOccurrence
                    { internalId = Nothing
                    , internalIdFromRenamedSource = Nothing
                    , isBinder = False
                    , instanceResolution = Nothing
                    , idOccType =
                        case mbHsWrapper of                          
                          Just w -> mkType flags <$> (applyWrapper w <$> mbType)
                          Nothing -> mkType flags <$> mbType
                    , typeArguments = Nothing
                    , description = descr
                    , sort = HCE.ValueId
                    }
                idOccMap =
                  IM.insertWith
                    removeOverlappingInterval
                    startLine
                    [((startCol, endCol), idOcc)]
                    (astStateIdOccMap astState)
             in astState {astStateIdOccMap = idOccMap}
    Nothing -> return ()

-- | Finds the first interval that overlaps with a new interval
-- and adds the smaller one of the two to the list. If there are no overlapping
-- intervals then this function adds a new interval to the list.
removeOverlappingInterval ::
     forall a. [((Int, Int), a)] -> [((Int, Int), a)] -> [((Int, Int), a)]
removeOverlappingInterval [newInterval@((newStart, newEnd), _newVal)] intervals =
  go intervals False
  where
    go ::
         [((Int, Int), a)]
      -> Bool -- If an overlapping interval is found
      -> [((Int, Int), a)]
    go (i:is) True = i : go is True
    -- Current interval is inside new interval
    go (interval@((s, e), _val):is) False
      | newStart <= s && newEnd >= e = interval : go is True
    -- New interval is inside current interval
    go (((s, e), _val):is) False
      | newStart >= s && newEnd <= e = newInterval : go is True
    -- Intervals partially overlap
    go (interval@((s, e), _val):is) False
      | newStart >= s && newEnd >= e && newStart < e =
        (if e - s >= newEnd - newStart
           then newInterval
           else interval) :
        go is True
    -- Intervals partially overlap
    go (interval@((s, e), _val):is) False
      | newStart <= s && newEnd <= e && newEnd > s =
        (if e - s >= newEnd - newStart
           then newInterval
           else interval) :
        go is True
    -- Intervals don't overlap
    go (interval:is) False = interval : go is False
    go [] True = []
    go [] False = [newInterval]
removeOverlappingInterval _ intervals = intervals

newtype InstTypes = InstTypes [Type]

instance Eq InstTypes where
  (==) (InstTypes ts1) (InstTypes ts2) = eqTypes ts1 ts2

instance Ord InstTypes where
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  compare (InstTypes ts1) (InstTypes ts2) = nonDetCmpTypes ts1 ts2
#else
  compare (InstTypes ts1) (InstTypes ts2) = cmpTypes ts1 ts2
#endif

-- | Creates an instance resolution tree 
traceInstanceResolution ::
     Environment
  -> Class
  -> [Type] -- ^ Types at which type variables of a class are instantated
  -> HCE.InstanceResolution
traceInstanceResolution environment c ts = go c ts S.empty
  where
    flags = envDynFlags environment
    go :: Class -> [Type] -> S.Set (Name, InstTypes) -> HCE.InstanceResolution
    go cls types seenInstances =
      let clsTyVarCount = length $ classTyVars cls
       in case lookupUniqueInstEnv
                 (envInstEnv environment)
                 cls
                 (take clsTyVarCount types) of
            Right (inst, instTypes) ->
              -- A successful match is a ClsInst, together with the types at which
              -- the dfun_id in the ClsInst should be instantiated              
              let instWithTypes = (is_dfun_name inst, InstTypes instTypes)
               in if not $ S.member instWithTypes seenInstances
                    then let (typeVars, predTypes, _class, _types) =
                               instanceSig inst
                             subst = zipTvSubst typeVars instTypes
                             constraints =
                               mapMaybe getClassPredTys_maybe . substTys subst $
                               predTypes
                          in HCE.Instance
                               (instanceToText flags inst)
                               (mkType flags . idType $ is_dfun inst)
                               (map (mkType flags) instTypes)
                               (nameLocationInfo
                                  flags
                                  (envPackageId environment)
                                  (envComponentId environment)
                                  (envTransformation environment)
                                  (envFileMap environment)
                                  (envDefSiteMap environment)
                                  (Just . instanceToText flags $ inst)
                                  Nothing
                                  (varName . is_dfun $ inst))
                               (map
                                  (\(cl, tys) ->
                                     go
                                       cl
                                       tys
                                       (S.insert instWithTypes seenInstances))
                                  constraints)
                    else HCE.Stop
            Left _ -> HCE.Stop

mkIdentifierInfo :: Environment -> Id -> Maybe Name -> HCE.IdentifierInfo
mkIdentifierInfo environment identifier mbNameFromRenamedSource =
  let name = fromMaybe (varName identifier) mbNameFromRenamedSource
      sort = nameSort name
      nameSpace = occNameNameSpace . nameOccName $ name
      flags = envDynFlags environment
      currentPackageId = envPackageId environment
      compId = envComponentId environment
      transformation = envTransformation environment
      fileMap = envFileMap environment
      defSiteMap = envDefSiteMap environment
      locationInfo =
        nameLocationInfo
          flags
          currentPackageId
          compId
          transformation
          fileMap
          defSiteMap
          Nothing
          Nothing
          name
   in HCE.IdentifierInfo
        { sort = sort
        , occName = HCE.OccName $ nameToText name
        , demangledOccName = demangleOccName name
        , nameSpace = nameSpace
        , idType = mkType flags $ varType identifier
        , locationInfo = locationInfo
        , details = mbIdDetails identifier
        , doc =
            nameDocumentation
              transformation
              fileMap
              defSiteMap
              (envCurrentModuleDefSites environment)
              name
        , internalId = HCE.InternalId $ identifierKey flags identifier
        , externalId =
            case sort of
              HCE.External ->
                case locationInfo of
                  HCE.ExactLocation {..} ->
                    Just $
                    HCE.ExternalId $
                    T.intercalate
                      "|"
                      [ HCE.packageIdToText currentPackageId
                      , HCE.getHaskellModuleName moduleName
                      , case nameSpace of
                          HCE.VarName -> T.pack $ show HCE.Val  
                          HCE.DataName -> T.pack $ show HCE.Val  
                          _ -> T.pack $ show HCE.Typ
                      , nameToText name
                      ]
                  HCE.ApproximateLocation {name = n, ..} ->
                    Just $
                    HCE.ExternalId $
                    T.intercalate
                      "|"
                      [ HCE.packageIdToText packageId
                      , HCE.getHaskellModuleName moduleName
                      , T.pack $ show entity  
                      , n
                      ]
                  _ -> Nothing
              _ -> Nothing
        , isExported = S.member name $ envExportedNames environment
        }

mkIdentifierOccurrence ::
     Environment
  -> Id
  -> Name
  -> Maybe (Type, [Type])
  -> Bool
  -> T.Text
  -> HCE.IdentifierOccurrence
mkIdentifierOccurrence environment identifier nameFromRenamedSource mbInstTypes isBinder descr =
  let flags = envDynFlags environment
      mbClass
        | isId identifier =
          case idDetails identifier of
            ClassOpId cls -> Just cls
            _ -> Nothing
        | otherwise = Nothing
      mbInstanceResolution =
        case (mbClass, mbInstTypes) of
          (Just cls, Just (_, ts)) ->
            Just $ traceInstanceResolution environment cls ts
          _ -> Nothing
   in HCE.IdentifierOccurrence
        (Just . HCE.InternalId . identifierKey flags $ identifier)
        (Just . HCE.InternalId . T.pack . show . getKey . nameUnique $ nameFromRenamedSource)
        isBinder
        mbInstanceResolution
        (mkType flags . fst <$> mbInstTypes)
        (map (mkType flags) . snd <$> mbInstTypes)
        descr
        (if isId identifier
           then HCE.ValueId
           else HCE.TypeId)

restoreTidyEnv :: (State ASTState) a -> (State ASTState) a
restoreTidyEnv action = do
  tidyEnv <- astStateTidyEnv <$> get
  res <- action
  modify' $ \s -> s {astStateTidyEnv = tidyEnv}
  return res

restoreHsWrapper :: (State ASTState) a -> (State ASTState) a
restoreHsWrapper action = do
  wrapper <- astStateHsWrapper <$> get
  res <- action
  modify' $ \s -> s {astStateHsWrapper = wrapper}
  return res  

tidyIdentifier :: Id -> State ASTState (Id, Maybe (Type, [Type]))
tidyIdentifier identifier = do
  tidyEnv <- astStateTidyEnv <$> get
  mbHsWrapper <- astStateHsWrapper <$> get
  let (tidyEnv', identifier') = tidyIdentifierType tidyEnv identifier
      identifierType = varType identifier'
      (mbTypes, updatedEnv) =
        case mbHsWrapper of
          Just wrapper ->
            let expectedType = applyWrapper wrapper identifierType
                (tidyEnv'', expectedType') = tidyOpenType tidyEnv' expectedType
                wrapperTys =
                  map (snd . tidyOpenType tidyEnv'') (wrapperTypes wrapper)
             in if not $ eqType expectedType identifierType
                  then (Just (expectedType', wrapperTys), tidyEnv'')
                  else (Nothing, tidyEnv')
          Nothing -> (Nothing, tidyEnv')
  modify' (\s -> s {astStateTidyEnv = updatedEnv})
  return (identifier', mbTypes)

tidyType :: Type -> State ASTState Type
tidyType typ = do
  tidyEnv <- astStateTidyEnv <$> get
  let (tidyEnv', typ') = tidyOpenType tidyEnv typ
  modify' (\s -> s {astStateTidyEnv = tidyEnv'})
  return typ'

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldTypecheckedSource :: LHsBinds GhcTc -> State ASTState ()
#else
foldTypecheckedSource :: LHsBinds Id -> State ASTState ()
#endif
foldTypecheckedSource = foldLHsBindsLR

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLHsExpr :: LHsExpr GhcTc -> State ASTState (Maybe Type)
#else
foldLHsExpr :: LHsExpr Id -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L _span (XExpr _)) = return Nothing
foldLHsExpr (L _ (HsOverLit _ (XOverLit _))) = return Nothing
foldLHsExpr (L _ (HsLam _ (XMatchGroup _))) = return Nothing
foldLHsExpr (L _ (HsLamCase _ (XMatchGroup _))) = return Nothing
foldLHsExpr (L _ (HsCase _ _ (XMatchGroup _))) = return Nothing
foldLHsExpr (L span (HsVar _ (L _ identifier))) =
#else
foldLHsExpr (L span (HsVar (L _ identifier))) =
#endif
  restoreTidyEnv $ do
    (identifier', mbTypes) <- tidyIdentifier identifier
    addIdentifierToIdSrcSpanMap span identifier' mbTypes
    return . Just . varType $ identifier'
foldLHsExpr (L _ HsUnboundVar {}) = return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L _ (HsConLikeOut _ conLike)) =
#else
foldLHsExpr (L _ (HsConLikeOut conLike)) =
#endif
  restoreTidyEnv $ do
    let mbType = varType <$> conLikeWrapId_maybe conLike
    mbType' <- maybe (return Nothing) (fmap Just . tidyType) mbType
    return mbType'
#endif
foldLHsExpr (L _ HsRecFld {}) = return Nothing
foldLHsExpr (L _ HsOverLabel {}) = return Nothing
foldLHsExpr (L span expr@HsIPVar {}) = do
  addExprInfo span Nothing "HsIPVar" (exprSort expr)
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span (HsOverLit _ (OverLit (OverLitTc _ ol_type) _ _))) =
#else
foldLHsExpr (L span (HsOverLit OverLit {ol_type})) =
#endif
  restoreTidyEnv $ do
    typ <- tidyType ol_type
    addExprInfo
      span
      (Just typ)
      "HsOverLit"
      (if isOneLineSpan span
         then Simple
         else Composite)
    return $ Just typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLHsExpr (L span (HsLit _ lit)) =
#else
foldLHsExpr (L span (HsLit lit)) =
#endif
  restoreTidyEnv $ do
    typ <- tidyType $ hsLitType lit
    addExprInfo
      span
      (Just typ)
      "HsLit"
      (if isOneLineSpan span
         then Simple
         else Composite)
    return $ Just typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span expr@(HsLam _ (MG (MatchGroupTc {..}) mg_alts _))) =
#else
foldLHsExpr (L span expr@(HsLam MG {..})) =
#endif
  restoreTidyEnv $ do
    typ <- tidyType $ mkFunTys mg_arg_tys mg_res_ty
    addExprInfo span (Just typ) "HsLam" (exprSort expr)
    mapM_ foldLMatch $ unLoc mg_alts
    return $ Just typ
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span expr@(HsLamCase _ (MG (MatchGroupTc {..}) mg_alts _))) =
#else
foldLHsExpr (L span expr@(HsLamCase MG {..})) =
#endif
#else
foldLHsExpr (L span expr@(HsLamCase _typ MG {..})) =
#endif
  restoreTidyEnv $ do
    typ <- tidyType $ mkFunTys mg_arg_tys mg_res_ty
    addExprInfo span (Just typ) "HsLamCase" (exprSort expr)
    mapM_ foldLMatch $ unLoc mg_alts
    return $ Just typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLHsExpr (L span expr@(HsApp _ fun arg)) = do
#else
foldLHsExpr (L span expr@(HsApp fun arg)) = do
#endif
  funTy <- foldLHsExpr fun
  _argTy <- foldLHsExpr arg
  typ <- maybe (return Nothing) (funResultTySafe span "HsApp") funTy    
  addExprInfo span typ "HsApp" (exprSort expr)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span ex@(HsAppType _ expr)) = do
#else
foldLHsExpr (L _ (HsAppType _ _)) = return Nothing
foldLHsExpr (L span ex@(HsAppTypeOut expr _)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsAppType" (exprSort ex)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLHsExpr (L span expr@(OpApp _ left op right)) = do
#else
foldLHsExpr (L span expr@(OpApp left op _fixity right)) = do
#endif
  opTyp <- foldLHsExpr op
  typ <- maybe (return Nothing) (funResultTy2Safe span "HsApp") opTyp  
  _ <- foldLHsExpr left
  _ <- foldLHsExpr right
  addExprInfo span typ "OpApp" (exprSort expr)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)      
foldLHsExpr (L span e@(NegApp _ expr _syntaxExp)) = do
#else
foldLHsExpr (L span e@(NegApp expr _syntaxExp)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "NegApp" (exprSort e)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)        
foldLHsExpr (L _span (HsPar _ expr)) = foldLHsExpr expr
#else
foldLHsExpr (L _span (HsPar expr)) = foldLHsExpr expr
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span expr@(SectionL _ operand operator)) = do
#else
foldLHsExpr (L span expr@(SectionL operand operator)) = do
#endif
  opType <- foldLHsExpr operator
  _ <- foldLHsExpr operand
  mbTypes <- maybe (return Nothing) (splitFunTy2Safe span "SectionL") opType    
  let typ =
        case mbTypes of
          Just (_arg1, arg2, res) -> Just $ mkFunTy arg2 res
          Nothing -> Nothing
  addExprInfo span typ "SectionL" (exprSort expr)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(SectionR _ operator operand)) = do
#else
foldLHsExpr (L span e@(SectionR operator operand)) = do
#endif
  opType <- foldLHsExpr operator
  _ <- foldLHsExpr operand
  mbTypes <- maybe (return Nothing) (splitFunTy2Safe span "SectionR") opType    
  let typ =
        case mbTypes of
          Just (arg1, _arg2, res) -> Just $ mkFunTy arg1 res
          Nothing -> Nothing
  addExprInfo span typ "SectionR" (exprSort e)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(ExplicitTuple _ tupArgs boxity)) = do
#else
foldLHsExpr (L span e@(ExplicitTuple tupArgs boxity)) = do
#endif
  tupleArgs <- mapM foldLHsTupArg tupArgs
  let tupleSectionArgTys =
        mapM fst . filter ((== TupArgMissing) . snd) $ tupleArgs
      tupleArgTys = mapM fst tupleArgs
      resultType =
        mkFunTys <$> tupleSectionArgTys <*> (mkTupleTy boxity <$> tupleArgTys)
  tidyEnv <- astStateTidyEnv <$> get
  addExprInfo
    span
    (snd . tidyOpenType tidyEnv <$> resultType)
    "ExplicitTuple"
    (exprSort e)
  return resultType
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L _span (ExplicitSum _ _ _ expr)) = do
#else
foldLHsExpr (L _span (ExplicitSum _ _ expr _types)) = do
#endif
  -- TODO
  _ <- foldLHsExpr expr
  return Nothing    
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(HsCase _ expr (MG (MatchGroupTc {..}) mg_alts _))) =
#else
foldLHsExpr (L span e@(HsCase expr MG {..})) =
#endif
  restoreTidyEnv $ do
    typ <- tidyType mg_res_ty
    _ <- foldLHsExpr expr
    mapM_ foldLMatch (unLoc mg_alts)
    addExprInfo span (Just typ) "HsCase" (exprSort e)
    return $ Just typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(HsIf _ _mbSynExpr condExpr thenExpr elseExpr)) = do
#else
foldLHsExpr (L span e@(HsIf _mbSynExpr condExpr thenExpr elseExpr)) = do
#endif
  _ <- foldLHsExpr condExpr
  typ <- foldLHsExpr thenExpr
  _ <- foldLHsExpr elseExpr
  addExprInfo span typ "HsIf" (exprSort e)
  return typ
foldLHsExpr (L span e@(HsMultiIf typ grhss)) =
  restoreTidyEnv $ do
    typ' <- tidyType typ
    addExprInfo span (Just typ') "HsMultiIf" (exprSort e)
    mapM_ foldLGRHS grhss
    return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLHsExpr (L span e@(HsLet _ (L _ binds) expr)) = do
#else
foldLHsExpr (L span e@(HsLet (L _ binds) expr)) = do
#endif
  _ <- foldHsLocalBindsLR binds
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsLet" (exprSort e)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)      
foldLHsExpr (L span expr@(HsDo typ _context (L _ stmts))) =
#else
foldLHsExpr (L span expr@(HsDo _context (L _ stmts) typ)) =
#endif
  restoreTidyEnv $ do
    typ' <- tidyType typ
    addExprInfo span (Just typ') "HsDo" (exprSort expr)
    mapM_ foldLStmtLR stmts
    return $ Just typ'
foldLHsExpr (L span (ExplicitList typ _syntaxExpr exprs)) =
  restoreTidyEnv $ do
    typ' <- mkListTy <$> tidyType typ
    unless (null exprs) $ addExprInfo span (Just typ') "ExplicitList" Composite
    mapM_ foldLHsExpr exprs
    return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
#else
foldLHsExpr (L span e@(ExplicitPArr typ exprs)) =
  restoreTidyEnv $ do
    typ' <- tidyType typ
    addExprInfo span (Just typ') "ExplicitPArr" (exprSort e)
    mapM_ foldLHsExpr exprs
    return $ Just typ'
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(RecordCon (RecordConTc _ conExpr) _ binds)) = do
#else
foldLHsExpr (L span e@(RecordCon (L _ _) _conLike conExpr binds)) = do
#endif
    mbConType <-
      fmap (snd . splitFunTys) <$>
      foldLHsExpr (L (UnhelpfulSpan $ mkFastString "RecordCon") conExpr)
    addExprInfo span mbConType "RecordCon" (exprSort e)
    _ <- foldHsRecFields binds
    return mbConType
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLHsExpr (L span e@(RecordUpd (RecordUpdTc cons _inputTys outTys _wrapper) expr binds)) =
#else
foldLHsExpr (L span e@(RecordUpd expr binds cons _inputTys outTys _wrapper)) =
#endif
  restoreTidyEnv $ do   
    -- cons is a non-empty list of DataCons that have  all the upd'd fields
    let typ = conLikeResTy (head cons) outTys
    typ' <- tidyType typ
    addExprInfo span (Just typ') "RecordUpd" (exprSort e)
    _ <- foldLHsExpr expr
    mapM_ foldLHsRecUpdField binds
    return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(ExprWithTySig _ expr)) = do
#else
foldLHsExpr (L _span (ExprWithTySig _expr _type)) = return Nothing
foldLHsExpr (L span e@(ExprWithTySigOut expr _type)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "ExprWithTySig" (exprSort e)
  return typ
foldLHsExpr (L span e@(ArithSeq postTcExpr _mbSyntaxExpr seqInfo)) = do
  typ <-
    fmap (snd . splitFunTys . snd . splitForAllTys) <$>
    foldLHsExpr (L (UnhelpfulSpan $ mkFastString "ArithSeq") postTcExpr)
  _ <-
    case seqInfo of
      From expr -> foldLHsExpr expr
      FromThen expr1 expr2 -> foldLHsExpr expr1 >> foldLHsExpr expr2
      FromTo expr1 expr2 -> foldLHsExpr expr1 >> foldLHsExpr expr2
      FromThenTo expr1 expr2 expr3 ->
        foldLHsExpr expr1 >> foldLHsExpr expr2 >> foldLHsExpr expr3
  addExprInfo span typ "ArithSeq" (exprSort e)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
#else    
foldLHsExpr (L span e@(PArrSeq postTcExpr _seqInfo)) = do
  typ <- foldLHsExpr (L (UnhelpfulSpan $ mkFastString "PArrSeq") postTcExpr)
  addExprInfo span typ "ArithSeq" (exprSort e)
  return typ
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(HsSCC _ _sourceText _fastString expr)) = do
#else
foldLHsExpr (L span e@(HsSCC _sourceText _fastString expr)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsSCC" (exprSort e)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(HsCoreAnn _ _sourceText _fastString expr)) = do
#else
foldLHsExpr (L span e@(HsCoreAnn _sourceText _fastString expr)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsCoreAnn" (exprSort e)
  return typ
foldLHsExpr (L _span HsBracket {}) = return Nothing
foldLHsExpr (L _span HsRnBracketOut {}) = return Nothing
foldLHsExpr (L _span HsTcBracketOut {}) = return Nothing
foldLHsExpr (L _span HsSpliceE {}) = return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span expr@(HsProc _ pat cmd)) = do
#else
foldLHsExpr (L span expr@(HsProc pat cmd)) = do
#endif
  _ <- foldLPat pat
  _ <- foldLHsCmdTop cmd
  addExprInfo span Nothing "HsProc" (exprSort expr)
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)  
foldLHsExpr (L span e@(HsStatic _ expr)) = do
#else
foldLHsExpr (L span e@(HsStatic expr)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsStatic" (exprSort e)
  return typ
foldLHsExpr (L _ HsArrForm {}) = return Nothing
foldLHsExpr (L _ HsArrApp {}) = return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span e@(HsTick _ _ expr)) = do
#else
foldLHsExpr (L span e@(HsTick _ expr)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsTick" (exprSort e)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLHsExpr (L span e@(HsBinTick _ _ _ expr)) = do
#else
foldLHsExpr (L span e@(HsBinTick _ _ expr)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsBinTick" (exprSort e)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLHsExpr (L span e@(HsTickPragma _ _ _ _ expr)) = do
#else
foldLHsExpr (L span e@(HsTickPragma _ _ _ expr)) = do
#endif
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsTickPragma" (exprSort e)
  return typ
foldLHsExpr (L _span EWildPat {}) = return Nothing
foldLHsExpr (L _span EAsPat {}) = return Nothing
foldLHsExpr (L _span EViewPat {}) = return Nothing
foldLHsExpr (L _span ELazyPat {}) = return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsExpr (L span (HsWrap _ wrapper expr)) =
#else
foldLHsExpr (L span (HsWrap wrapper expr)) =
#endif
  restoreHsWrapper $ do
    case exprSort expr of
      Simple -> modify' (\s -> s {astStateHsWrapper = Just wrapper})
      Composite -> return () -- Not sure if it is possible
    typ <- foldLHsExpr (L span expr)
    return $ applyWrapper wrapper <$> typ    

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldHsRecFields :: HsRecFields GhcTc (LHsExpr GhcTc) -> State ASTState (Maybe Type)
#else
foldHsRecFields :: HsRecFields Id (LHsExpr Id) -> State ASTState (Maybe Type)
#endif
foldHsRecFields HsRecFields {..} = do
  let userWritten =
        case rec_dotdot of
          Just i -> take i
          Nothing -> id
  mapM_ foldLHsRecField $ userWritten rec_flds
  return Nothing

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldLHsRecField :: LHsRecField GhcTc (LHsExpr GhcTc) -> State ASTState (Maybe Type)
#else
foldLHsRecField :: LHsRecField Id (LHsExpr Id) -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLHsRecField (L _span (HsRecField (L _idSpan (XFieldOcc _)) _ _)) = return Nothing
foldLHsRecField (L span (HsRecField (L idSpan (FieldOcc identifier _)) arg pun)) =
#else
foldLHsRecField (L span (HsRecField (L idSpan (FieldOcc _ identifier)) arg pun)) =
#endif
  restoreTidyEnv $ do
    (identifier', mbTypes) <- tidyIdentifier identifier
    addIdentifierToIdSrcSpanMap idSpan identifier' mbTypes
    addExprInfo span (Just . varType $ identifier') "HsRecField" Composite
    unless pun $ void (foldLHsExpr arg)
    return . Just . varType $ identifier'

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldLHsRecUpdField :: LHsRecUpdField GhcTc -> State ASTState (Maybe Type)
#else
foldLHsRecUpdField :: LHsRecUpdField Id -> State ASTState (Maybe Type)
#endif
foldLHsRecUpdField (L span (HsRecField (L idSpan recField) arg pun)) =
  restoreTidyEnv $ do
    let selectorId = selectorAmbiguousFieldOcc recField
    (identifier', mbTypes) <- tidyIdentifier selectorId
     -- Name of the selectorId is not 'correct' (Internal instead of External) :
     -- https://github.com/ghc/ghc/blob/321b420f4582d103ca7b304867b916a749712e9f/compiler/typecheck/TcExpr.hs#L2424
    typeEnv <- envTypeEnv . astStateEnv <$> get
    let selName = varName selectorId
        originalName =
          case lookupTypeEnv typeEnv selName of
            Just (AnId originalSelId) -> varName originalSelId
            _ -> selName
    let identifier'' = setVarName identifier' originalName
    addIdentifierToIdSrcSpanMap idSpan identifier'' mbTypes
    addExprInfo span (Just . varType $ identifier'') "HsRecUpdField" Composite
    unless pun $ void (foldLHsExpr arg)
    return . Just . varType $ identifier'

data TupArg
  = TupArgPresent
  | TupArgMissing
  deriving (Show, Eq)

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldLHsTupArg :: LHsTupArg GhcTc -> State ASTState (Maybe Type, TupArg)
#else
foldLHsTupArg :: LHsTupArg Id -> State ASTState (Maybe Type, TupArg)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsTupArg (L _span (XTupArg _)) = return (Nothing, TupArgMissing)
foldLHsTupArg (L _span (Present _ expr)) =
#else
foldLHsTupArg (L _span (Present expr)) =
#endif
  restoreTidyEnv $ do
    typ <- foldLHsExpr expr
    typ' <-
      case typ of
        Just t -> Just <$> tidyType t
        Nothing -> return Nothing
    return (typ', TupArgPresent)
foldLHsTupArg (L _ (Missing typ)) =
  restoreTidyEnv $ do
    typ' <- tidyType typ
    return (Just typ', TupArgMissing)

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLMatch :: LMatch GhcTc (LHsExpr GhcTc) -> State ASTState (Maybe Type)
#else
foldLMatch :: LMatch Id (LHsExpr Id) -> State ASTState (Maybe Type)
#endif
foldLMatch (L _span Match {..}) = do
  mapM_ foldLPat m_pats
  _ <- foldGRHSs m_grhss
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLMatch (L _span _) = return Nothing    
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)      
foldLMatchCmd :: LMatch GhcTc (LHsCmd GhcTc) -> State ASTState (Maybe Type)
#else
foldLMatchCmd :: LMatch Id (LHsCmd Id) -> State ASTState (Maybe Type)
#endif
foldLMatchCmd (L _span Match {..}) = do
  mapM_ foldLPat m_pats
  _ <- foldGRHSsCmd m_grhss
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLMatchCmd (L _span _) = return Nothing    
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)      
foldGRHSsCmd :: GRHSs GhcTc (LHsCmd GhcTc) -> State ASTState (Maybe Type)
#else
foldGRHSsCmd :: GRHSs Id (LHsCmd Id) -> State ASTState (Maybe Type)
#endif
foldGRHSsCmd GRHSs {..} = do
  mapM_ foldLGRHSCmd grhssGRHSs
  _ <- foldHsLocalBindsLR (unLoc grhssLocalBinds)
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldGRHSsCmd (_) = return Nothing    
#endif  

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldGRHSs :: GRHSs GhcTc (LHsExpr GhcTc) -> State ASTState (Maybe Type)
#else
foldGRHSs :: GRHSs Id (LHsExpr Id) -> State ASTState (Maybe Type)
#endif
foldGRHSs GRHSs {..} = do
  mapM_ foldLGRHS grhssGRHSs
  _ <- foldHsLocalBindsLR (unLoc grhssLocalBinds)
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldGRHSs (_) = return Nothing    
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLStmtLR :: LStmtLR GhcTc GhcTc (LHsExpr GhcTc) -> State ASTState (Maybe Type)
#else
foldLStmtLR :: LStmtLR Id Id (LHsExpr Id) -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLStmtLR (L _span (XStmtLR _)) = return Nothing
foldLStmtLR (L span (LastStmt _ body _ _)) =
#else
foldLStmtLR (L span (LastStmt body _ _)) =
#endif
  do typ <- foldLHsExpr body
     addExprInfo span typ "LastStmt" Composite
     return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLStmtLR (L _span (BindStmt _ pat body _ _)) = do
#else
foldLStmtLR (L _span (BindStmt pat body _ _ _)) = do
#endif
  _ <- foldLPat pat
  _ <- foldLHsExpr body
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLStmtLR (L span (BodyStmt _ body _ _)) = do
#else
foldLStmtLR (L span (BodyStmt body _  _ _)) = do
#endif
  mbTyp <- foldLHsExpr body
  addExprInfo span mbTyp "BodyStmt" Composite
  return mbTyp
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLStmtLR (L _ (LetStmt _ (L _ binds))) = do
#else
foldLStmtLR (L _ (LetStmt (L _ binds))) = do
#endif
  _ <- foldHsLocalBindsLR binds
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLStmtLR (L _ (ParStmt _ blocks _ _)) = do
#else
foldLStmtLR (L _ (ParStmt blocks _ _ _)) = do
#endif
  mapM_ foldParStmtBlock blocks
  return Nothing
foldLStmtLR (L _ TransStmt {..}) = do
  mapM_ foldLStmtLR trS_stmts  
  _ <- maybe (return Nothing) foldLHsExpr trS_by
  _ <- foldLHsExpr trS_using
  return Nothing
foldLStmtLR (L _span RecStmt {..}) = do
  mapM_ foldLStmtLR recS_stmts
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLStmtLR (L span (ApplicativeStmt typ args _)) =
#else
foldLStmtLR (L span (ApplicativeStmt args _ typ)) =
#endif
  restoreTidyEnv $ do
    typ' <- tidyType typ
    mapM_ (foldApplicativeArg . snd) args
    addExprInfo span (Just typ') "ApplicativeStmt" Composite
    return Nothing

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldApplicativeArg :: ApplicativeArg GhcTc -> State ASTState (Maybe Type)    
#elif MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldApplicativeArg :: ApplicativeArg GhcTc GhcTc -> State ASTState (Maybe Type)
#else
foldApplicativeArg :: ApplicativeArg Id Id -> State ASTState (Maybe Type)
#endif
foldApplicativeArg appArg =
  case appArg of
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    XApplicativeArg _ -> return Nothing
    ApplicativeArgOne _ pat expr _bool -> do
#else
    ApplicativeArgOne pat expr _bool -> do
#endif
#else
    ApplicativeArgOne pat expr -> do
#endif
      _ <- foldLPat pat
      _ <- foldLHsExpr expr
      return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)            
    ApplicativeArgMany _ exprStmts _ pat -> do
#else
    ApplicativeArgMany exprStmts _ pat -> do
#endif
      mapM_ foldLStmtLR exprStmts
      _ <- foldLPat pat
      return Nothing  
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLStmtLRCmd ::
     LStmtLR GhcTc GhcTc (LHsCmd GhcTc) -> State ASTState (Maybe Type)
#else
foldLStmtLRCmd :: LStmtLR Id Id (LHsCmd Id) -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLStmtLRCmd (L _ (XStmtLR _)) = return Nothing
foldLStmtLRCmd (L span (LastStmt _ body _syntaxExpr _)) = do
#else
foldLStmtLRCmd (L span (LastStmt body _syntaxExpr _)) = do
#endif
  typ <- foldLHsCmd body
  addExprInfo span typ "LastStmt Cmd" Composite
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLStmtLRCmd (L _ (BindStmt _ pat body _ _)) = do
#else
foldLStmtLRCmd (L _ (BindStmt pat body _ _ _)) = do
#endif
  _ <- foldLPat pat
  _ <- foldLHsCmd body
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLStmtLRCmd (L span (BodyStmt _ body _ _)) = do
#else
foldLStmtLRCmd (L span (BodyStmt body _ _ _)) = do
#endif
  typ <- foldLHsCmd body
  addExprInfo span typ "BodyStmt Cmd" Composite
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLStmtLRCmd (L _ (LetStmt _ (L _ binds))) = do
#else
foldLStmtLRCmd (L _ (LetStmt (L _ binds))) = do
#endif
  _ <- foldHsLocalBindsLR binds
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLStmtLRCmd (L _ (ParStmt _ blocks _ _)) = do
#else
foldLStmtLRCmd (L _ (ParStmt blocks _ _ _)) = do
#endif
  mapM_ foldParStmtBlock blocks
  return Nothing
foldLStmtLRCmd (L _ TransStmt {..}) = do
  mapM_ foldLStmtLR trS_stmts
  _ <- foldLHsExpr trS_using
  _ <- maybe (return Nothing) foldLHsExpr trS_by
  return Nothing
foldLStmtLRCmd (L _ RecStmt {..}) = do
  mapM_ foldLStmtLRCmd recS_stmts
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLStmtLRCmd (L span (ApplicativeStmt typ args _)) =
#else
foldLStmtLRCmd (L span (ApplicativeStmt args _ typ)) =
#endif
  restoreTidyEnv $ do
    typ' <- tidyType typ
    mapM_ (foldApplicativeArg . snd) args
    addExprInfo span (Just typ') "ApplicativeStmt Cmd" Composite
    return Nothing  

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)    
foldLGRHS :: LGRHS GhcTc (LHsExpr GhcTc) -> State ASTState (Maybe Type)
#else
foldLGRHS :: LGRHS Id (LHsExpr Id) -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLGRHS (L _span (XGRHS _)) = return Nothing
foldLGRHS (L _span (GRHS _ guards body)) = do
#else
foldLGRHS (L _span (GRHS guards body)) = do
#endif
  typ <- foldLHsExpr body
  mapM_ foldLStmtLR guards
  return typ

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldLGRHSCmd :: LGRHS GhcTc (LHsCmd GhcTc) -> State ASTState (Maybe Type)
#else
foldLGRHSCmd :: LGRHS Id (LHsCmd Id) -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLGRHSCmd (L _span (XGRHS _)) = return Nothing
foldLGRHSCmd (L _span (GRHS _ guards body)) = do
#else
foldLGRHSCmd (L _span (GRHS guards body)) = do
#endif
  typ <- foldLHsCmd body
  mapM_ foldLStmtLR guards
  return typ   

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldParStmtBlock :: ParStmtBlock GhcTc GhcTc -> State ASTState (Maybe Type)
#else
foldParStmtBlock :: ParStmtBlock Id Id -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldParStmtBlock (XParStmtBlock _) = return Nothing
foldParStmtBlock (ParStmtBlock _ exprStmts _ids _syntaxExpr) = do
#else
foldParStmtBlock (ParStmtBlock exprStmts _ids _syntaxExpr) = do
#endif
  mapM_ foldLStmtLR exprStmts
  return Nothing

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldHsLocalBindsLR :: HsLocalBindsLR GhcTc GhcTc -> State ASTState (Maybe Type)
#else
foldHsLocalBindsLR :: HsLocalBindsLR Id Id -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldHsLocalBindsLR (XHsLocalBindsLR _) = return Nothing
foldHsLocalBindsLR (HsValBinds _ binds) = do
#else
foldHsLocalBindsLR (HsValBinds binds) = do
#endif
  _ <- foldHsValBindsLR binds
  return Nothing
foldHsLocalBindsLR HsIPBinds {} = return Nothing
foldHsLocalBindsLR EmptyLocalBinds {} = return Nothing

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldHsValBindsLR :: HsValBindsLR GhcTc GhcTc -> State ASTState (Maybe Type)
#else
foldHsValBindsLR :: HsValBindsLR Id Id -> State ASTState (Maybe Type)
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldHsValBindsLR (ValBinds _ _binds _) = do  
  return Nothing
foldHsValBindsLR (XValBindsLR (NValBinds binds _)) = do
  _ <- mapM_ (foldLHsBindsLR . snd) binds
  return Nothing      
#else    
foldHsValBindsLR (ValBindsIn _ _) = return Nothing
foldHsValBindsLR (ValBindsOut binds _) = do
  mapM_ (foldLHsBindsLR . snd) binds
  return Nothing
#endif  

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldLHsBindsLR :: LHsBinds GhcTc -> State ASTState ()
#else
foldLHsBindsLR :: LHsBinds Id -> State ASTState ()
#endif
foldLHsBindsLR = mapM_ (`foldLHsBindLR` Nothing) . bagToList

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLHsBindLR :: LHsBindLR GhcTc GhcTc
              -> Maybe Id -- ^ Polymorphic id
              -> State ASTState (Maybe Type)
#else
foldLHsBindLR :: LHsBindLR Id Id
              -> Maybe Id -- ^ Polymorphic id
              -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsBindLR (L _span (XHsBindsLR _)) _ = return Nothing
foldLHsBindLR (L _span (PatSynBind _ (XPatSynBind _))) _ = return Nothing
#endif
foldLHsBindLR (L _span FunBind {..}) mbPolyId
  | mg_origin fun_matches == FromSource =
    restoreTidyEnv $ do
      let (L idSpan identifier) = fun_id -- monotype
          typ =
            case mbPolyId of
              Just polyId -> varType polyId
              Nothing -> varType identifier
          name = maybe (varName identifier) varName mbPolyId
          identifier' = setVarType (setVarName identifier name) typ
      (identifier'', _) <- tidyIdentifier identifier'
      addIdentifierToIdSrcSpanMap idSpan identifier'' Nothing
      mapM_ foldLMatch (unLoc (mg_alts fun_matches))
      return Nothing
  | otherwise = return Nothing
foldLHsBindLR (L _ PatBind {..}) _ = do
  _ <- foldLPat pat_lhs
  _ <- foldGRHSs pat_rhs
  return Nothing
foldLHsBindLR (L _ VarBind {..}) _ = return Nothing
foldLHsBindLR (L _ AbsBinds {..}) _ = do
  mapM_ (\(bind, typ) -> foldLHsBindLR bind (Just typ)) $
    zip (bagToList abs_binds) (map abe_poly abs_exports)
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
#else
foldLHsBindLR (L _ AbsBindsSig {..}) _ = do
  _ <- foldLHsBindLR abs_sig_bind (Just abs_sig_export)
  return Nothing
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsBindLR (L _ (PatSynBind _ PSB {..})) _ =
#else
foldLHsBindLR (L _ (PatSynBind PSB {..})) _ =
#endif
  restoreTidyEnv $ do
    _ <- foldLPat psb_def
    _ <-
      let addId :: GenLocated SrcSpan Id -> State ASTState ()
          addId (L span i) = do
            (i', _) <- tidyIdentifier i
            addIdentifierToIdSrcSpanMap span i' Nothing
       in case psb_args of
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
            InfixCon id1 id2 -> addId id1 >> addId id2
            PrefixCon ids -> mapM_ addId ids
            RecCon recs ->
              mapM_
                (\(RecordPatSynField selId patVar) ->
                   addId selId >> addId patVar)
                recs
#else
            InfixPatSyn id1 id2 -> addId id1 >> addId id2
            PrefixPatSyn ids -> mapM_ addId ids
            RecordPatSyn recs ->
              mapM_
                (\(RecordPatSynField selId patVar) ->
                   addId selId >> addId patVar)
                recs 
#endif
    return Nothing

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldLPat :: LPat GhcTc -> State ASTState (Maybe Type)
#else
foldLPat :: LPat Id -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLPat (L _span (XPat _)) = return Nothing
foldLPat (L _ (NPat _ (L _ (XOverLit _)) _ _)) = return Nothing
foldLPat (L _ (NPlusKPat _ (L _ _) (L _ (XOverLit _)) _ _ _)) = return Nothing
foldLPat (L span (VarPat _ (L _ identifier))) = do
#else
foldLPat (L span (VarPat (L _ identifier))) = do
#endif
  (identifier', _) <- tidyIdentifier identifier
  addIdentifierToIdSrcSpanMap span identifier' Nothing
  return . Just . varType $ identifier'
foldLPat (L span pat@(WildPat typ)) = do
  typ' <- tidyType typ
  addExprInfo span (Just typ') "WildPat" (patSort pat)
  return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLPat (L span p@(LazyPat _ pat)) = do
#else
foldLPat (L span p@(LazyPat pat)) = do
#endif
  mbType <- foldLPat pat
  addExprInfo span mbType "LazyPat" (patSort p)
  return mbType
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLPat (L span p@(AsPat _ (L idSpan identifier) pat)) = do
#else
foldLPat (L span p@(AsPat (L idSpan identifier) pat)) = do
#endif
  (identifier', _) <- tidyIdentifier identifier
  addIdentifierToIdSrcSpanMap idSpan identifier' Nothing
  addExprInfo span (Just . varType $ identifier') "AsPat" (patSort p)
  _ <- foldLPat pat
  return . Just . varType $ identifier'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLPat (L _span (ParPat _ pat)) = foldLPat pat
#else
foldLPat (L _span (ParPat pat)) = foldLPat pat
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLPat (L span p@(BangPat _ pat)) = do
#else
foldLPat (L span p@(BangPat pat)) = do
#endif
  typ <- foldLPat pat
  addExprInfo span typ "BangPat" (patSort p)
  return typ
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLPat (L span p@(ListPat (ListPatTc typ _) pats)) = do
#else
foldLPat (L span p@(ListPat pats typ _)) = do
#endif
  typ' <- tidyType typ
  let listType = mkListTy typ'
  addExprInfo span (Just listType) "ListPat" (patSort p)
  mapM_ foldLPat pats
  return $ Just listType
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLPat (L span pat@(TuplePat types pats boxity)) = do
#else
foldLPat (L span pat@(TuplePat pats boxity types)) = do
#endif
  typ' <- tidyType $ mkTupleTy boxity types
  addExprInfo span (Just typ') "TuplePat" (patSort pat)
  mapM_ foldLPat pats
  return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLPat (L _span (SumPat _ pat _ _)) = do
#else
foldLPat (L _span (SumPat pat _ _ _types)) = do
#endif
  -- TODO
  _ <- foldLPat pat
  return Nothing  
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
#else
foldLPat (L span pat@(PArrPat pats typ)) = do
  typ' <- tidyType typ
  addExprInfo span (Just typ') "PArrPat" (patSort pat)
  mapM_ foldLPat pats
  return $ Just typ'
#endif  
foldLPat (L _span (ConPatIn _ _)) = return Nothing
foldLPat (L span pat@ConPatOut {..}) = do
  let (L idSpan conLike) = pat_con 
      conId =
        case conLike of
          RealDataCon dc -> dataConWorkId dc
          PatSynCon ps -> patSynId ps
      typ = conLikeResTy (unLoc pat_con) pat_arg_tys
  (identifier', mbTypes) <- tidyIdentifier conId
  addIdentifierToIdSrcSpanMap idSpan identifier' mbTypes
  typ' <- tidyType typ
  addExprInfo span (Just typ') "ConPatOut" (patSort pat)
  _ <- foldHsConPatDetails pat_args
  return . Just . varType $ identifier'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLPat (L span p@(ViewPat typ expr pat)) = do
#else
foldLPat (L span p@(ViewPat expr pat typ)) = do
#endif
  typ' <- tidyType typ
  addExprInfo span (Just typ') "ViewPat" (patSort p)
  _ <- foldLPat pat
  _ <- foldLHsExpr expr
  return $ Just typ'
foldLPat (L _ SplicePat {}) = return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLPat (L span (LitPat _ hsLit)) = do
#else
foldLPat (L span (LitPat hsLit)) = do
#endif
  typ' <- tidyType $ hsLitType hsLit
  addExprInfo
    span
    (Just typ')
    "LitPat"
    (if isOneLineSpan span
       then Simple
       else Composite)
  return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLPat (L span pat@(NPat _ (L _spanLit (OverLit (OverLitTc {..}) _ _)) _ _)) = do
#else
foldLPat (L span pat@(NPat (L _spanLit OverLit {ol_type}) _ _ _)) = do
#endif
  typ' <- tidyType ol_type
  addExprInfo span (Just typ') "NPat" (patSort pat)
  return $ Just ol_type
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLPat (L span pat@(NPlusKPat typ (L idSpan identifier) (L litSpan (OverLit (OverLitTc {..}) _ _)) _ _ _)) = do
#else
foldLPat (L span pat@(NPlusKPat (L idSpan identifier) (L litSpan OverLit {ol_type}) _ _ _ typ)) = do
#endif
  (identifier', _) <- tidyIdentifier identifier
  addIdentifierToIdSrcSpanMap idSpan identifier' Nothing
  typ' <- tidyType typ
  addExprInfo span (Just typ') "NPlusKPat" (patSort pat)
  olType' <- tidyType ol_type
  addExprInfo
    litSpan
    (Just olType')
    "NPlusKPat"
    (if isOneLineSpan span
       then Simple
       else Composite)
  return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLPat (L _span (SigPat typ pat)) = do
  typ' <- tidyType typ
  _ <- foldLPat pat
  return $ Just typ'    
#else
foldLPat (L _span (SigPatIn _ _)) = return Nothing  
foldLPat (L _span (SigPatOut pat typ)) = do
  typ' <- tidyType typ
  _ <- foldLPat pat
  return $ Just typ'
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLPat (L span p@(CoPat _ _ pat typ)) = do
#else
foldLPat (L span p@(CoPat _ pat typ)) = do
#endif
  typ' <- tidyType typ
  addExprInfo span (Just typ') "CoPat" (patSort p)
  _ <- foldLPat (L span pat)
  return Nothing 

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)  
foldHsConPatDetails
  :: HsConPatDetails GhcTc
  -> State ASTState (Maybe Type)
#else
foldHsConPatDetails
  :: HsConPatDetails Id
  -> State ASTState (Maybe Type)
#endif  
foldHsConPatDetails (PrefixCon args) = do
  mapM_ foldLPat args
  return Nothing
foldHsConPatDetails (RecCon rec) = do
  _ <- foldHsRecFieldsPat rec
  return Nothing
foldHsConPatDetails (InfixCon arg1 arg2) = do
  _ <- foldLPat arg1
  _ <- foldLPat arg2
  return Nothing

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldHsRecFieldsPat :: HsRecFields GhcTc (LPat GhcTc) -> State ASTState (Maybe Type)
#else
foldHsRecFieldsPat :: HsRecFields Id (LPat Id) -> State ASTState (Maybe Type)
#endif
foldHsRecFieldsPat HsRecFields {..} = do
  let onlyUserWritten =
        case rec_dotdot of
          Just i -> take i
          Nothing -> id
  mapM_ foldLHsRecFieldPat $ onlyUserWritten rec_flds
  return Nothing

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLHsRecFieldPat :: LHsRecField GhcTc (LPat GhcTc) -> State ASTState (Maybe Type)
#else
foldLHsRecFieldPat :: LHsRecField Id (LPat Id) -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsRecFieldPat (L _ (HsRecField (L idSpan (FieldOcc identifier _)) arg pun)) = do
#else
foldLHsRecFieldPat (L _ (HsRecField (L idSpan (FieldOcc _ identifier)) arg pun)) = do
#endif
  (identifier', mbTypes) <- tidyIdentifier identifier
  addIdentifierToIdSrcSpanMap idSpan identifier' mbTypes
  unless pun $ void $ foldLPat arg
  return . Just . varType $ identifier'
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsRecFieldPat (L _ (HsRecField (L _idSpan (XFieldOcc _)) _arg _pun)) = return Nothing    
#endif    

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLHsCmdTop :: LHsCmdTop GhcTc -> State ASTState (Maybe Type)
#else
foldLHsCmdTop :: LHsCmdTop Id -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLHsCmdTop (L _span (XCmdTop _)) = return Nothing
foldLHsCmdTop (L span (HsCmdTop _ cmd)) = do
#else
foldLHsCmdTop (L span (HsCmdTop cmd _ _ _)) = do
#endif
  mbTyp <- foldLHsCmd cmd
  addExprInfo span mbTyp "HsCmdTop" Composite
  return mbTyp

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foldLHsCmd :: LHsCmd GhcTc -> State ASTState (Maybe Type)
#else
foldLHsCmd :: LHsCmd Id -> State ASTState (Maybe Type)
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)      
foldLHsCmd (L _ (XCmd _)) = return Nothing
foldLHsCmd (L _ (HsCmdLam _ (XMatchGroup _))) = return Nothing
foldLHsCmd (L _ (HsCmdCase _ _ (XMatchGroup _))) = return Nothing
foldLHsCmd (L _ (HsCmdArrApp _ expr1 expr2 _ _)) = do
#else
foldLHsCmd (L _ (HsCmdArrApp expr1 expr2 _ _ _)) = do
#endif
  _ <- foldLHsExpr expr1
  _ <- foldLHsExpr expr2
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)      
foldLHsCmd (L _ (HsCmdArrForm _ expr _  _ topCmds)) = do
#else
foldLHsCmd (L _ (HsCmdArrForm expr _  _ topCmds)) = do
#endif
#else
foldLHsCmd (L _ (HsCmdArrForm expr _ topCmds)) = do
#endif
  _ <- foldLHsExpr expr
  mapM_ foldLHsCmdTop topCmds
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsCmd (L _ (HsCmdApp _ cmd expr)) = do
#else
foldLHsCmd (L _ (HsCmdApp cmd expr)) = do
#endif
  _ <- foldLHsCmd cmd
  _ <- foldLHsExpr expr
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsCmd (L _ (HsCmdLam _ MG {..})) = do
#else
foldLHsCmd (L _ (HsCmdLam MG {..})) = do
#endif
  mapM_ foldLMatchCmd $ unLoc mg_alts
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLHsCmd (L _ (HsCmdCase _ expr MG {..})) = do
#else
foldLHsCmd (L _ (HsCmdCase expr MG {..})) = do
#endif
  _ <- foldLHsExpr expr
  mapM_ foldLMatchCmd $ unLoc mg_alts
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
foldLHsCmd (L _ (HsCmdPar _ cmd)) = do
#else
foldLHsCmd (L _ (HsCmdPar cmd)) = do
#endif
  _ <- foldLHsCmd cmd
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)  
foldLHsCmd (L _ (HsCmdIf _ _ expr cmd1 cmd2)) = do
#else
foldLHsCmd (L _ (HsCmdIf _ expr cmd1 cmd2)) = do
#endif
  _ <- foldLHsCmd cmd1
  _ <- foldLHsCmd cmd2
  _ <- foldLHsExpr expr
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)    
foldLHsCmd (L _ (HsCmdLet _ (L _ binds) cmd)) = do
#else
foldLHsCmd (L _ (HsCmdLet (L _ binds) cmd)) = do
#endif
  _ <- foldLHsCmd cmd
  _ <- foldHsLocalBindsLR binds
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)      
foldLHsCmd (L _ (HsCmdDo _ stmts)) = do
#else
foldLHsCmd (L _ (HsCmdDo stmts _)) = do
#endif
  mapM_ foldLStmtLRCmd $ unLoc stmts
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)      
foldLHsCmd (L span (HsCmdWrap _ _ cmd)) = do
#else
foldLHsCmd (L span (HsCmdWrap _ cmd)) = do
#endif    
  _ <- foldLHsCmd (L span cmd)
  return Nothing
