{-# LANGUAGE CPP #-}
{-# LANGUAGE TupleSections #-}
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
  )
import HscTypes (TypeEnv, lookupTypeEnv)
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
exprSort (HsVar _) = Simple
exprSort (HsIPVar _) = Simple
exprSort (HsOverLit _) = Simple
exprSort (HsLit _) = Simple
exprSort (ExplicitTuple args _)
  | null args = Simple
  | otherwise = Composite   
exprSort (ExplicitList _ _ args) 
  | null args = Simple
  | otherwise = Composite     
exprSort _ = Composite

patSort :: Pat a -> ExprSort
patSort (WildPat _typ) = Simple
patSort (LitPat _lit) = Simple
patSort NPat {} = Simple
patSort (ListPat pats _ _) 
  | null pats = Simple
  | otherwise = Composite       
patSort (TuplePat pats _ _)
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
  
foldTypecheckedSource :: LHsBinds Id -> State ASTState ()
foldTypecheckedSource = foldLHsBindsLR

foldLHsExpr :: LHsExpr Var -> State ASTState (Maybe Type)
foldLHsExpr (L span (HsVar (L _ identifier))) =
  restoreTidyEnv $ do
    (identifier', mbTypes) <- tidyIdentifier identifier
    addIdentifierToIdSrcSpanMap span identifier' mbTypes
    return . Just . varType $ identifier'
foldLHsExpr (L _ (HsUnboundVar _)) = return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
foldLHsExpr (L _ (HsConLikeOut conLike)) =
  restoreTidyEnv $ do    
    let mbType = varType <$> conLikeWrapId_maybe conLike    
    mbType' <- maybe (return Nothing) (fmap Just . tidyType) mbType    
    return mbType'
#endif
foldLHsExpr (L _ (HsRecFld _)) = return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
foldLHsExpr (L _ (HsOverLabel _ _)) = return Nothing
#else
foldLHsExpr (L _ (HsOverLabel _)) = return Nothing
#endif
foldLHsExpr (L span expr@(HsIPVar _)) = do
  addExprInfo span Nothing "HsIPVar" (exprSort expr)
  return Nothing
foldLHsExpr (L span (HsOverLit OverLit {ol_type})) =
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
foldLHsExpr (L span (HsLit lit)) =
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
foldLHsExpr (L span expr@(HsLam MG {..})) =
  restoreTidyEnv $ do
    typ <- tidyType $ mkFunTys mg_arg_tys mg_res_ty
    addExprInfo span (Just typ) "HsLam" (exprSort expr)
    mapM_ foldLMatch $ unLoc mg_alts
    return $ Just typ
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)    
foldLHsExpr (L span expr@(HsLamCase MG {..})) =
#else
foldLHsExpr (L span expr@(HsLamCase _typ MG {..})) =
#endif
  restoreTidyEnv $ do
    typ <- tidyType $ mkFunTys mg_arg_tys mg_res_ty
    addExprInfo span (Just typ) "HsLamCase" (exprSort expr)
    mapM_ foldLMatch $ unLoc mg_alts
    return $ Just typ
foldLHsExpr (L span expr@(HsApp fun arg)) = do
  funTy <- foldLHsExpr fun
  _argTy <- foldLHsExpr arg
  typ <- fromMaybe (return Nothing) (funResultTySafe span "HsApp" <$> funTy)
  addExprInfo span typ "HsApp" (exprSort expr)
  return typ
foldLHsExpr (L _ (HsAppType _ _)) = return Nothing
foldLHsExpr (L span ex@(HsAppTypeOut expr _)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsAppTypeOut" (exprSort ex)
  return typ  
foldLHsExpr (L span expr@(OpApp left op _fixity right)) = do
  opTyp <- foldLHsExpr op
  typ <- fromMaybe (return Nothing) (funResultTy2Safe span "HsApp" <$> opTyp)
  _ <- foldLHsExpr left
  _ <- foldLHsExpr right
  addExprInfo span typ "OpApp" (exprSort expr)
  return typ
foldLHsExpr (L span e@(NegApp expr _syntaxExp)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "NegApp" (exprSort e)
  return typ
foldLHsExpr (L _span (HsPar expr)) = foldLHsExpr expr
foldLHsExpr (L span expr@(SectionL operand operator)) = do
  opType <- foldLHsExpr operator
  _ <- foldLHsExpr operand
  mbTypes <-
    fromMaybe (return Nothing) (splitFunTy2Safe span "SectionL" <$> opType)
  let typ =
        case mbTypes of
          Just (_arg1, arg2, res) -> Just $ mkFunTy arg2 res
          Nothing -> Nothing
  addExprInfo span typ "SectionL" (exprSort expr)
  return typ
foldLHsExpr (L span e@(SectionR operator operand)) = do
  opType <- foldLHsExpr operator
  _ <- foldLHsExpr operand
  mbTypes <-
    fromMaybe (return Nothing) (splitFunTy2Safe span "SectionR" <$> opType)
  let typ =
        case mbTypes of
          Just (arg1, _arg2, res) -> Just $ mkFunTy arg1 res
          Nothing -> Nothing
  addExprInfo span typ "SectionR" (exprSort e)
  return typ
foldLHsExpr (L span e@(ExplicitTuple tupArgs boxity)) = do
  tupleArgs <- mapM foldLHsTupArg tupArgs
  let tupleSectionArgTys =
        mapM fst . filter ((== TupArgMissing) . snd) $ tupleArgs
      tupleArgTys = mapM fst tupleArgs
      resultType =
        mkFunTys <$> tupleSectionArgTys <*> (mkTupleTy boxity <$> tupleArgTys)
  tidyEnv <- astStateTidyEnv <$> get
  addExprInfo
    span
    ((snd . tidyOpenType tidyEnv) <$> resultType)
    "ExplicitTuple"
    (exprSort e)
  return resultType
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
foldLHsExpr (L _span (ExplicitSum _ _ expr _types)) = do
  -- TODO
  _ <- foldLHsExpr expr
  return Nothing    
#endif    
foldLHsExpr (L span e@(HsCase expr MG {..})) =
  restoreTidyEnv $ do
    typ <- tidyType mg_res_ty
    _ <- foldLHsExpr expr
    mapM_ foldLMatch (unLoc mg_alts)
    addExprInfo span (Just typ) "HsCase" (exprSort e)
    return $ Just typ
foldLHsExpr (L span e@(HsIf _mbSynExpr condExpr thenExpr elseExpr)) = do
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
foldLHsExpr (L span e@(HsLet (L _ binds) expr)) = do
  _ <- foldHsLocalBindsLR binds
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsLet" (exprSort e)
  return typ
foldLHsExpr (L span expr@(HsDo _context (L _ stmts) typ)) =
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
foldLHsExpr (L span e@(ExplicitPArr typ exprs)) =
  restoreTidyEnv $ do
    typ' <- tidyType typ
    addExprInfo span (Just typ') "ExplicitPArr" (exprSort e)
    mapM_ foldLHsExpr exprs
    return $ Just typ'
foldLHsExpr (L span e@(RecordCon (L _ _) _conLike conExpr binds)) = do
    mbConType <-
      fmap (snd . splitFunTys) <$>
      foldLHsExpr (L (UnhelpfulSpan $ mkFastString "RecordCon") conExpr)
    addExprInfo span mbConType "RecordCon" (exprSort e)
    _ <- foldHsRecFields binds
    return mbConType
foldLHsExpr (L span e@(RecordUpd expr binds cons _inputTys outTys _wrapper)) =
  restoreTidyEnv $ do   
    -- cons is a non-empty list of DataCons that have  all the upd'd fields
    let typ = conLikeResTy (head cons) outTys
    typ' <- tidyType typ
    addExprInfo span (Just typ') "RecordUpd" (exprSort e)
    _ <- foldLHsExpr expr
    mapM_ foldLHsRecUpdField binds
    return $ Just typ'
foldLHsExpr (L _span (ExprWithTySig _expr _type)) = return Nothing
foldLHsExpr (L span e@(ExprWithTySigOut expr _type)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "ExprWithTySigOut" (exprSort e)
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
foldLHsExpr (L span e@(PArrSeq postTcExpr _seqInfo)) = do
  typ <- foldLHsExpr (L (UnhelpfulSpan $ mkFastString "PArrSeq") postTcExpr)
  addExprInfo span typ "ArithSeq" (exprSort e)
  return typ
foldLHsExpr (L span e@(HsSCC _sourceText _fastString expr)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsSCC" (exprSort e)
  return typ
foldLHsExpr (L span e@(HsCoreAnn _sourceText _fastString expr)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsCoreAnn" (exprSort e)
  return typ
foldLHsExpr (L _span (HsBracket _bracket)) = return Nothing
foldLHsExpr (L _span (HsRnBracketOut _ _)) = return Nothing
foldLHsExpr (L _span (HsTcBracketOut _bracket _splice)) = return Nothing
foldLHsExpr (L _span (HsSpliceE _)) = return Nothing
foldLHsExpr (L span expr@(HsProc pat cmd)) = do
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
foldLHsExpr (L span e@(HsTick _ expr)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsTick" (exprSort e)
  return typ
foldLHsExpr (L span e@(HsBinTick _ _ expr)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsBinTick" (exprSort e)
  return typ
foldLHsExpr (L span e@(HsTickPragma _ _ _ expr)) = do
  typ <- foldLHsExpr expr
  addExprInfo span typ "HsTickPragma" (exprSort e)
  return typ
foldLHsExpr (L _span EWildPat) = return Nothing
foldLHsExpr (L _span (EAsPat _ _)) = return Nothing
foldLHsExpr (L _span (EViewPat _ _)) = return Nothing
foldLHsExpr (L _span (ELazyPat _)) = return Nothing
foldLHsExpr (L span (HsWrap wrapper expr)) =
  restoreHsWrapper $ do
    case exprSort expr of
      Simple -> modify' (\s -> s {astStateHsWrapper = Just wrapper})
      Composite -> return () -- Not sure if it is possible
    typ <- foldLHsExpr (L span expr)
    return $ applyWrapper wrapper <$> typ
  
foldHsRecFields :: HsRecFields Id (LHsExpr Id) -> State ASTState (Maybe Type)
foldHsRecFields HsRecFields {..} = do
  let userWritten =
        case rec_dotdot of
          Just i -> take i
          Nothing -> id
  mapM_ foldLHsRecField $ userWritten rec_flds
  return Nothing
  
foldLHsRecField :: LHsRecField Id (LHsExpr Id) -> State ASTState (Maybe Type)
foldLHsRecField (L span (HsRecField (L idSpan (FieldOcc _ identifier)) arg pun)) =
  restoreTidyEnv $ do
    (identifier', mbTypes) <- tidyIdentifier identifier
    addIdentifierToIdSrcSpanMap idSpan identifier' mbTypes
    addExprInfo span (Just . varType $ identifier') "HsRecField" Composite
    unless pun $ void (foldLHsExpr arg)
    return . Just . varType $ identifier'

foldLHsRecUpdField :: LHsRecUpdField Id -> State ASTState (Maybe Type)
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

foldLHsTupArg :: LHsTupArg Id -> State ASTState (Maybe Type, TupArg)
foldLHsTupArg (L _span (Present expr)) =
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

foldLMatch :: LMatch Id (LHsExpr Var) -> State ASTState (Maybe Type)
foldLMatch (L _span Match {..}) = do
  mapM_ foldLPat m_pats
  _ <- foldGRHSs m_grhss
  return Nothing    
       
foldLMatchCmd :: LMatch Id (LHsCmd Var) -> State ASTState (Maybe Type)
foldLMatchCmd (L _span Match {..}) = do
  mapM_ foldLPat m_pats
  _ <- foldGRHSsCmd m_grhss
  return Nothing

foldGRHSsCmd :: GRHSs Id (LHsCmd Id) -> State ASTState (Maybe Type)
foldGRHSsCmd GRHSs {..} = do
  mapM_ foldLGRHSCmd grhssGRHSs
  _ <- foldHsLocalBindsLR (unLoc grhssLocalBinds)
  return Nothing

foldGRHSs :: GRHSs Id (LHsExpr Var) -> State ASTState (Maybe Type)
foldGRHSs GRHSs {..} = do
  mapM_ foldLGRHS grhssGRHSs
  _ <- foldHsLocalBindsLR (unLoc grhssLocalBinds)
  return Nothing

foldLStmtLR :: LStmtLR Id Id (LHsExpr Var) -> State ASTState (Maybe Type)
foldLStmtLR (L span (LastStmt body _ _)) =  
  do typ <- foldLHsExpr body
     addExprInfo span typ "LastStmt" Composite
     return typ
foldLStmtLR (L _span (BindStmt pat body _ _ _)) = do
  _ <- foldLPat pat
  _ <- foldLHsExpr body
  return Nothing
foldLStmtLR (L span (BodyStmt body _ _ _)) = do
  mbTyp <- foldLHsExpr body
  addExprInfo span mbTyp "BodyStmt" Composite
  return mbTyp
foldLStmtLR (L _ (LetStmt (L _ binds))) = do
  _ <- foldHsLocalBindsLR binds
  return Nothing
foldLStmtLR (L _ (ParStmt blocks _ _ _)) = do
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
foldLStmtLR (L span (ApplicativeStmt args _ typ)) =
  restoreTidyEnv $ do
    typ' <- tidyType typ
    mapM_ (foldApplicativeArg . snd) args
    addExprInfo span (Just typ') "ApplicativeStmt" Composite
    return Nothing

foldApplicativeArg :: ApplicativeArg Id Id -> State ASTState (Maybe Type)
foldApplicativeArg appArg =
  case appArg of
    ApplicativeArgOne pat expr -> do
      _ <- foldLPat pat
      _ <- foldLHsExpr expr
      return Nothing
    ApplicativeArgMany exprStmts _ pat -> do
      _ <- mapM_ foldLStmtLR exprStmts
      _ <- foldLPat pat
      return Nothing  

foldLStmtLRCmd :: LStmtLR Id Id (LHsCmd Var) 
               -> State ASTState (Maybe Type)
foldLStmtLRCmd (L span (LastStmt body _syntaxExpr _)) = do
  typ <- foldLHsCmd body
  addExprInfo span typ "LastStmt Cmd" Composite
  return typ
foldLStmtLRCmd (L _ (BindStmt pat body _ _ _)) = do
  _ <- foldLPat pat
  _ <- foldLHsCmd body
  return Nothing
foldLStmtLRCmd (L span (BodyStmt body _ _ _)) = do
  typ <- foldLHsCmd body
  addExprInfo span typ "BodyStmt Cmd" Composite
  return typ
foldLStmtLRCmd (L _ (LetStmt (L _ binds))) = do
  _ <- foldHsLocalBindsLR binds
  return Nothing
foldLStmtLRCmd (L _ (ParStmt blocks _ _ _)) = do
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
foldLStmtLRCmd (L span (ApplicativeStmt args _ typ)) =
  restoreTidyEnv $ do
    typ' <- tidyType typ
    mapM_ (foldApplicativeArg . snd) args
    addExprInfo span (Just typ') "ApplicativeStmt Cmd" Composite
    return Nothing  
  
foldLGRHS :: LGRHS Id (LHsExpr Id) -> State ASTState (Maybe Type)
foldLGRHS (L _span (GRHS guards body)) = do
  typ <- foldLHsExpr body
  mapM_ foldLStmtLR guards
  return typ
  
foldLGRHSCmd :: LGRHS Id (LHsCmd Var) -> State ASTState (Maybe Type)
foldLGRHSCmd (L _span (GRHS guards body)) = do
  typ <- foldLHsCmd body
  mapM_ foldLStmtLR guards
  return typ   

foldParStmtBlock :: ParStmtBlock Id Id -> State ASTState (Maybe Type)
foldParStmtBlock (ParStmtBlock exprStmts _ids _syntaxExpr) = do
  mapM_ foldLStmtLR exprStmts
  return Nothing

foldHsLocalBindsLR :: HsLocalBindsLR Id Id -> State ASTState (Maybe Type)
foldHsLocalBindsLR (HsValBinds binds) = do
  _ <- foldHsValBindsLR binds
  return Nothing
foldHsLocalBindsLR (HsIPBinds _binds) = return Nothing
foldHsLocalBindsLR EmptyLocalBinds = return Nothing

foldHsValBindsLR :: HsValBindsLR Id Var -> State ASTState (Maybe Type)
foldHsValBindsLR (ValBindsIn _ _) = return Nothing
foldHsValBindsLR (ValBindsOut binds _) = do
  _ <- mapM_ (foldLHsBindsLR . snd) binds
  return Nothing

foldLHsBindsLR :: LHsBinds Id -> State ASTState ()
foldLHsBindsLR = mapM_ (`foldLHsBindLR` Nothing) . bagToList

foldLHsBindLR :: LHsBindLR Id Var
              -> Maybe Id -- ^ Polymorphic id
              -> State ASTState (Maybe Type)
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
  _ <-
    mapM_ (\(bind, typ) -> foldLHsBindLR bind (Just typ)) $
    zip (bagToList abs_binds) (map abe_poly abs_exports)
  return Nothing
foldLHsBindLR (L _ AbsBindsSig {..}) _ = do
  _ <- foldLHsBindLR abs_sig_bind (Just abs_sig_export)
  return Nothing
foldLHsBindLR (L _ (PatSynBind PSB {..})) _ =
  restoreTidyEnv $ do
    _ <- foldLPat psb_def
    _ <-
      let addId :: GenLocated SrcSpan Id -> State ASTState ()
          addId (L span i) = do
            (i', _) <- tidyIdentifier i
            addIdentifierToIdSrcSpanMap span i' Nothing
       in case psb_args of
            InfixPatSyn id1 id2 -> addId id1 >> addId id2
            PrefixPatSyn ids -> mapM_ addId ids
            RecordPatSyn recs ->
              mapM_
                (\(RecordPatSynField selId patVar) ->
                   addId selId >> addId patVar)
                recs
    return Nothing

foldLPat :: LPat Id -> State ASTState (Maybe Type)
foldLPat (L span (VarPat (L _ identifier))) = do
  (identifier', _) <- tidyIdentifier identifier
  addIdentifierToIdSrcSpanMap span identifier' Nothing
  return . Just . varType $ identifier'
foldLPat (L span pat@(WildPat typ)) = do
  typ' <- tidyType typ
  addExprInfo span (Just typ') "WildPat" (patSort pat)
  return $ Just typ'
foldLPat (L span p@(LazyPat pat)) = do
  mbType <- foldLPat pat
  addExprInfo span mbType "LazyPat" (patSort p)
  return mbType
foldLPat (L span p@(AsPat (L idSpan identifier) pat)) = do
  (identifier', _) <- tidyIdentifier identifier
  addIdentifierToIdSrcSpanMap idSpan identifier' Nothing
  addExprInfo span (Just . varType $ identifier') "AsPat" (patSort p)
  _ <- foldLPat pat
  return . Just . varType $ identifier'
foldLPat (L _span (ParPat pat)) = foldLPat pat  
foldLPat (L span p@(BangPat pat)) = do
  typ <- foldLPat pat
  addExprInfo span typ "BangPat" (patSort p)
  return typ
foldLPat (L span p@(ListPat pats typ _)) = do
  typ' <- tidyType typ
  let listType = mkListTy typ'
  addExprInfo span (Just listType) "ListPat" (patSort p)
  _ <- mapM_ foldLPat pats
  return $ Just listType
foldLPat (L span pat@(TuplePat pats boxity types)) = do
  typ' <- tidyType $ mkTupleTy boxity types
  addExprInfo span (Just typ') "TuplePat" (patSort pat)
  _ <- mapM_ foldLPat pats
  return $ Just typ'
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
foldLPat (L _span (SumPat pat _ _ _types)) = do
  -- TODO
  _ <- foldLPat pat
  return Nothing  
#endif
foldLPat (L span pat@(PArrPat pats typ)) = do
  typ' <- tidyType typ
  addExprInfo span (Just typ') "PArrPat" (patSort pat)
  _ <- mapM_ foldLPat pats
  return $ Just typ'
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
foldLPat (L span p@(ViewPat expr pat typ)) = do
  typ' <- tidyType typ
  addExprInfo span (Just typ') "ViewPat" (patSort p)
  _ <- foldLPat pat
  _ <- foldLHsExpr expr
  return $ Just typ'
foldLPat (L _ (SplicePat _)) = return Nothing
foldLPat (L span (LitPat hsLit)) = do
  typ' <- tidyType $ hsLitType hsLit
  addExprInfo
    span
    (Just typ')
    "LitPat"
    (if isOneLineSpan span
       then Simple
       else Composite)
  return $ Just typ'
foldLPat (L span pat@(NPat (L _spanLit OverLit {ol_type}) _ _ _)) = do
  typ' <- tidyType ol_type
  addExprInfo span (Just typ') "NPat" (patSort pat)
  return $ Just ol_type
foldLPat (L span pat@(NPlusKPat (L idSpan identifier) (L litSpan OverLit {ol_type}) _ _ _ typ)) = do
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
foldLPat (L _span (SigPatIn _ _)) = return Nothing  
foldLPat (L _span (SigPatOut pat typ)) = do
  typ' <- tidyType typ
  _ <- foldLPat pat
  return $ Just typ'
foldLPat (L span p@(CoPat _ pat typ)) = do
  typ' <- tidyType typ
  addExprInfo span (Just typ') "CoPat" (patSort p)
  _ <- foldLPat (L span pat)
  return Nothing 

foldHsConPatDetails
  :: HsConPatDetails Id
  -> State ASTState (Maybe Type)
foldHsConPatDetails (PrefixCon args) = do
  _ <- mapM_ foldLPat args
  return Nothing
foldHsConPatDetails (RecCon rec) = do
  _ <- foldHsRecFieldsPat rec
  return Nothing
foldHsConPatDetails (InfixCon arg1 arg2) = do
  _ <- foldLPat arg1
  _ <- foldLPat arg2
  return Nothing

foldHsRecFieldsPat :: HsRecFields Id (LPat Id) -> State ASTState (Maybe Type)
foldHsRecFieldsPat HsRecFields {..} = do
  let onlyUserWritten =
        case rec_dotdot of
          Just i -> take i
          Nothing -> id
  _ <- mapM_ foldLHsRecFieldPat $ onlyUserWritten rec_flds
  return Nothing

foldLHsRecFieldPat :: LHsRecField Id (LPat Id) -> State ASTState (Maybe Type)
foldLHsRecFieldPat (L _ (HsRecField (L idSpan (FieldOcc _ identifier)) arg pun)) = do
  (identifier', mbTypes) <- tidyIdentifier identifier
  addIdentifierToIdSrcSpanMap idSpan identifier' mbTypes
  unless pun $ void $ foldLPat arg
  return . Just . varType $ identifier'

foldLHsCmdTop :: LHsCmdTop Id -> State ASTState (Maybe Type)
foldLHsCmdTop (L span (HsCmdTop cmd _ _ _)) = do
  mbTyp <- foldLHsCmd cmd
  addExprInfo span mbTyp "HsCmdTop" Composite
  return mbTyp

foldLHsCmd :: LHsCmd Id -> State ASTState (Maybe Type)
foldLHsCmd (L _ (HsCmdArrApp expr1 expr2 _ _ _)) = do
  _ <- foldLHsExpr expr1
  _ <- foldLHsExpr expr2
  return Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)  
foldLHsCmd (L _ (HsCmdArrForm expr _  _ topCmds)) = do
#else
foldLHsCmd (L _ (HsCmdArrForm expr _ topCmds)) = do
#endif
  _ <- foldLHsExpr expr
  _ <- mapM_ foldLHsCmdTop topCmds
  return Nothing  
foldLHsCmd (L _ (HsCmdApp cmd expr)) = do
  _ <- foldLHsCmd cmd
  _ <- foldLHsExpr expr
  return Nothing
foldLHsCmd (L _ (HsCmdLam MG {..})) = do
  mapM_ foldLMatchCmd $ unLoc mg_alts
  return Nothing
foldLHsCmd (L _ (HsCmdCase expr MG {..})) = do
  _ <- foldLHsExpr expr
  mapM_ foldLMatchCmd $ unLoc mg_alts
  return Nothing   
foldLHsCmd (L _ (HsCmdPar cmd)) = do
  _ <- foldLHsCmd cmd
  return Nothing
foldLHsCmd (L _ (HsCmdIf _ expr cmd1 cmd2)) = do
  _ <- foldLHsCmd cmd1
  _ <- foldLHsCmd cmd2
  _ <- foldLHsExpr expr
  return Nothing
foldLHsCmd (L _ (HsCmdLet (L _ binds) cmd)) = do
  _ <- foldLHsCmd cmd
  _ <- foldHsLocalBindsLR binds
  return Nothing
foldLHsCmd (L _ (HsCmdDo stmts _)) = do
  mapM_ foldLStmtLRCmd $ unLoc stmts
  return Nothing
foldLHsCmd (L span (HsCmdWrap _ cmd)) = do
  _ <- foldLHsCmd (L span cmd)
  return Nothing
