{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE StrictData #-}

module HaskellCodeExplorer.AST.RenamedSource
  ( NameOccurrence(..)
  , namesFromRenamedSource
  ) where

import BasicTypes (TupleSort(..))
import BooleanFormula (BooleanFormula(..))
import Data.Generics (Data, everything, extQ, mkQ)
import Data.Maybe (Maybe(..), mapMaybe)
import qualified Data.Text as T (Text)
import GHC
  ( AmbiguousFieldOcc(..)
  , ConDecl(..)
  , ConDeclField(..)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
#else
  , DataFamInstDecl(..)
#endif
  , FamilyDecl(..)
  , FieldOcc(..)
  , FixitySig(..)
  , ForeignDecl(..)
  , GenLocated(..)
  , HsBindLR(..)
  , HsExpr(..)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,1,0)
  , HsPatSynDetails
#else
  , HsPatSynDetails(..)
#endif
  , HsRecField'(..)
  , HsTupleSort(..)
  , HsTyLit(..)
  , HsTyPats
  , HsTyVarBndr(..)
  , HsType(..)
  , IE(..)
  , LHsBindLR
  , LHsExpr
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
#else
  , LHsQTyVars(..)
#endif
  , LHsType
  , LPat
  , LSig
  , LTyClDecl
  , Located
  , HsBracket(..)
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  , HsMatchContext(..)
  , Match(..)
#else
  , m_fixity
  , MatchFixity(..)
#endif
  , MatchGroup(..)
  , Name
  , Pat(..)
  , PatSynBind(..)
  , Sig(..)
  , TyClDecl(..)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
  , FamEqn(..)
  , HsDataDefn(..)
#else
  , TyFamEqn(..)
#endif
  , Type
  , RoleAnnotDecl(..)
  , InjectivityAnn (..)
  , unLoc
  )
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
import HsExtension (GhcRn)
#endif
import HaskellCodeExplorer.GhcUtils (hsPatSynDetails, ieLocNames, ghcDL)
import Prelude hiding (span)
import TysWiredIn
  ( nilDataConName
  , tupleTyConName
  , typeNatKind
  , typeSymbolKind
  )
import SrcLoc
  ( mkRealSrcSpan
  , mkRealSrcLoc
  , realSrcSpanEnd
  , realSrcSpanStart
  , srcLocCol
  , srcLocFile
  , srcLocLine
  , SrcSpan(..)
  )
data NameOccurrence
  = NameOccurrence { locatedName :: Located (Maybe Name)
                   , description :: T.Text
                   , isBinder :: Bool }
  | TyLitOccurrence { locatedName :: Located (Maybe Name)
                    , description :: T.Text
                    , kind :: Type }

-- | Here we are only interested in a small subset of all AST nodes, so it is
-- convenient to use generic functions
namesFromRenamedSource :: (Data a) => a -> [NameOccurrence]
namesFromRenamedSource =
  everything
    (++)
    ([] `mkQ` hsExprNames `extQ` matchGroupNames `extQ` bindNames `extQ`
     patNames `extQ`
     sigNames `extQ`
     hsTypeNames `extQ`
     tyClDeclNames `extQ`
     familyDeclNames `extQ`
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
     familyEqNames `extQ`
     dataEqNames `extQ`
#else
     tyFamilyEqNames `extQ`
     tyFamilyDefEqNames `extQ`
     dataFamInstDeclNames `extQ`
#endif
     conDeclNames `extQ`
     importNames `extQ`
     hsTyVarBndrNames `extQ`
     hsPatSynDetailsNames `extQ`
     conDeclFieldNames `extQ`
     hsRecFieldExprNames `extQ`
     hsRecAmbFieldExprNames `extQ`
     hsRecFieldPatNames `extQ`
     foreignDeclNames `extQ`
     roleAnnotationNames `extQ`
     injectivityAnnotationNames)

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
fieldOccName :: Bool -> FieldOcc GhcRn -> NameOccurrence
#else
fieldOccName :: Bool -> FieldOcc Name -> NameOccurrence
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
fieldOccName _ (XFieldOcc _) = undefined
fieldOccName isBinder (FieldOcc name (L span _)) =
#else
fieldOccName isBinder (FieldOcc (L span _) name) =
#endif
  NameOccurrence
    { locatedName = L span (Just name)
    , description = "FieldOcc"
    , isBinder = isBinder
    }

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
conDeclFieldNames :: ConDeclField GhcRn -> [NameOccurrence]
#else
conDeclFieldNames :: ConDeclField Name -> [NameOccurrence]
#endif
conDeclFieldNames ConDeclField {..} =
  map (fieldOccName True . unLoc) cd_fld_names
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
conDeclFieldNames _ = []
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
hsRecFieldExprNames :: HsRecField' (FieldOcc GhcRn) (LHsExpr GhcRn) -> [NameOccurrence]
#else
hsRecFieldExprNames :: HsRecField' (FieldOcc Name) (LHsExpr Name) -> [NameOccurrence]
#endif
hsRecFieldExprNames HsRecField {..} = [fieldOccName False $ unLoc hsRecFieldLbl]

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
hsRecAmbFieldExprNames :: HsRecField' (AmbiguousFieldOcc GhcRn) (LHsExpr GhcRn) -> [NameOccurrence]
#else
hsRecAmbFieldExprNames :: HsRecField' (AmbiguousFieldOcc Name) (LHsExpr Name) -> [NameOccurrence]
#endif
hsRecAmbFieldExprNames HsRecField {..} =
  let (L span recField) = hsRecFieldLbl
      mbName =
        case recField of
          Ambiguous _ _ -> Nothing
#if MIN_VERSION_GLASGOW_HASKELL(8,6,3,0)
          Unambiguous name _ -> Just name
          _ -> Nothing
#else
          Unambiguous _ name -> Just name
#endif
   in [ NameOccurrence
          { locatedName = L span mbName
          , description = "AmbiguousFieldOcc"
          , isBinder = False
          }
      ]

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
hsRecFieldPatNames :: HsRecField' (FieldOcc GhcRn) (LPat GhcRn) -> [NameOccurrence]
#else
hsRecFieldPatNames :: HsRecField' (FieldOcc Name) (LPat Name) -> [NameOccurrence]
#endif
hsRecFieldPatNames HsRecField {..} = [fieldOccName False $ unLoc hsRecFieldLbl]

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
hsExprNames :: LHsExpr GhcRn -> [NameOccurrence]
#else
hsExprNames :: LHsExpr Name -> [NameOccurrence]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsExprNames (L _span (HsVar _ name)) =
#else
hsExprNames (L _span (HsVar name)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "HsVar"
    , isBinder = False
    }
  ]
hsExprNames (L span (ExplicitList _ _ exprs))
  | null exprs =
    [ NameOccurrence
      { locatedName = L span $ Just nilDataConName
      , description = "ExplicitList"
      , isBinder = False
      }
    ]
  | otherwise = []
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsExprNames (L _span (RecordCon _ name _)) =
#else
hsExprNames (L _span (RecordCon name _conLike _instFun _binds)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "RecordCon"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsExprNames (L _span (HsRecFld _ (Unambiguous name (L span _)))) =
#else
hsExprNames (L _span (HsRecFld (Unambiguous (L span _) name))) =
#endif
  [ NameOccurrence
    { locatedName = L span (Just name)
    , description = "HsRecFld"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsExprNames (L _span (HsRecFld _ (Ambiguous _name (L span _)))) =
#else
hsExprNames (L _span (HsRecFld (Ambiguous (L span _) _name))) =
#endif
  [ NameOccurrence
    { locatedName = L span Nothing
    , description = "HsRecFld"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsExprNames (L span (HsRnBracketOut _ (VarBr _ quote name) _)) =
#else
hsExprNames (L span (HsRnBracketOut (VarBr quote name) _)) =
#endif
  case span of
    RealSrcSpan realSpan ->
      let start = realSrcSpanStart realSpan
          end = realSrcSpanEnd realSpan
          offset =
            if quote
              then 1 -- 'x
              else 2 -- ''T
          start' =
            mkRealSrcLoc
              (srcLocFile start)
              (srcLocLine start)
              (srcLocCol start + offset)
          span' = RealSrcSpan $ mkRealSrcSpan start' end
       in [ NameOccurrence
              { locatedName = L span' (Just name)
              , description = "VarBr"
              , isBinder = False
              }
          ]
    _ -> []
hsExprNames _ = []

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
matchGroupNames :: MatchGroup GhcRn (LHsExpr GhcRn) -> [NameOccurrence]
#else
matchGroupNames :: MatchGroup Name (LHsExpr Name) -> [NameOccurrence]
#endif
matchGroupNames =
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
  mapMaybe (fmap toNameOcc . matchContextName . m_ctxt . unLoc) .
#else
  mapMaybe (fmap toNameOcc . matchFixityName . m_fixity . unLoc) .
#endif
  unLoc . mg_alts
  where
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
    --matchContextName :: HsMatchContext Name -> Maybe (Located Name)
    matchContextName (FunRhs name _ _bool) = Just name
    matchContextName _ = Nothing
#else
    --matchFixityName :: MatchFixity Name -> Maybe (Located Name)
    matchFixityName NonFunBindMatch = Nothing
    matchFixityName (FunBindMatch name _bool) = Just name
#endif
    --toNameOcc :: Located Name -> NameOccurrence
    toNameOcc n =
      NameOccurrence
        {locatedName = Just <$> n, description = "Match", isBinder = True}

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
bindNames :: LHsBindLR GhcRn GhcRn -> [NameOccurrence]
#else
bindNames :: LHsBindLR Name Name -> [NameOccurrence]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
bindNames (L _span (PatSynBind _ PSB {..})) =
#else
bindNames (L _span (PatSynBind PSB {..})) =
#endif
  [ NameOccurrence
      { locatedName = Just <$> psb_id
      , description = "PatSynBind"
      , isBinder = True
      }
  ]
bindNames _ = []

hsPatSynDetailsNames :: HsPatSynDetails (Located Name) -> [NameOccurrence]
hsPatSynDetailsNames =
  map
    (\name ->
       NameOccurrence
         { locatedName = Just <$> name
         , description = "HsPatSynDetails"
         , isBinder = True
         }) .
  hsPatSynDetails

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
importNames :: IE GhcRn -> [NameOccurrence]
#else
importNames :: IE Name -> [NameOccurrence]
#endif
importNames =
  map
    (\name ->
        NameOccurrence
        { locatedName = Just <$> name
        , description = "IE"
        , isBinder = False
        }) .
  ieLocNames


#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
patNames :: LPat GhcRn -> [NameOccurrence]
#else
patNames :: LPat Name -> [NameOccurrence]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
patNames (ghcDL -> (L _span (VarPat _ name))) =
#else
patNames (L _span (VarPat name)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "VarPat"
    , isBinder = True
    }
  ]
patNames (ghcDL -> (L _span (ConPatIn name _))) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "ConPatIn"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
patNames (ghcDL -> (L _span (AsPat _ name _))) =
#else
patNames (L _span (AsPat name _)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "AsPat"
    , isBinder = True
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
patNames (ghcDL -> (L _span (NPlusKPat _ name _ _ _ _))) =
#else
patNames (L _span (NPlusKPat name _ _ _ _ _)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "NPlusKPat"
    , isBinder = True
    }
  ]
patNames _ = []


#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
sigNames :: LSig GhcRn -> [NameOccurrence]
#else
sigNames :: LSig Name -> [NameOccurrence]
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNames (L _span (TypeSig _ names _)) =
#else
sigNames (L _span (TypeSig names _)) =
#endif
  map
    (\n ->
        NameOccurrence
        { locatedName = Just <$> n
        , description = "TypeSig"
        , isBinder = False
        })
    names

#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNames (L _span (PatSynSig _ names _)) = map (\name -> NameOccurrence (Just <$> name) "PatSynSig" False) names
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
sigNames (L _span (PatSynSig names _)) = map (\name -> NameOccurrence (Just <$> name) "PatSynSig" False) names
#else
sigNames (L _span (PatSynSig name _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "PatSynSig"
    , isBinder = False
    }
  ]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNames (L _span (ClassOpSig _ _ names _)) =
#else
sigNames (L _span (ClassOpSig _ names _)) =
#endif
  map
    (\n ->
        NameOccurrence
        { locatedName = Just <$> n
        , description = "ClassOpSig"
        , isBinder = True
        })
    names
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNames (L _span (FixSig _ (FixitySig _ names _))) =
#else
sigNames (L _span (FixSig (FixitySig names _))) =
#endif
  map
    (\n ->
        NameOccurrence
        { locatedName = Just <$> n
        , description = "FixitySig"
        , isBinder = False
        })
    names
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNames (L _span (InlineSig _ name _)) =
#else
sigNames (L _span (InlineSig name _)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "InlineSig"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNames (L _span (SpecSig _ name _ _)) =
#else
sigNames (L _span (SpecSig name _ _)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "SpecSig"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
sigNames (L _span (MinimalSig _ _ (L _ boolFormula))) =
#else
sigNames (L _span (MinimalSig _ (L _ boolFormula))) =
#endif
  map
    (\n ->
        NameOccurrence
        { locatedName = Just <$> n
        , description = "MinimalSig"
        , isBinder = False
        }) .
  boolFormulaNames $
  boolFormula
  where
    boolFormulaNames :: BooleanFormula name -> [name]
    boolFormulaNames (Var a) = [a]
    boolFormulaNames (And fs) = concatMap (boolFormulaNames . unLoc) fs
    boolFormulaNames (Or fs) = concatMap (boolFormulaNames . unLoc) fs
    boolFormulaNames (Parens (L _ f)) = boolFormulaNames f
sigNames (L _ _) = []

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
hsTypeNames :: LHsType GhcRn -> [NameOccurrence]
#else
hsTypeNames :: LHsType Name -> [NameOccurrence]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsTypeNames (L _span (HsTyVar _ _promoted name)) =
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
hsTypeNames (L _span (HsTyVar _promoted name)) =
#else
hsTypeNames (L _span (HsTyVar name)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "HsTyVar"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsTypeNames (L span (HsTyLit _ lit)) =
#else
hsTypeNames (L span (HsTyLit lit)) =
#endif
  let kind =
        case lit of
          HsNumTy _ _ -> typeNatKind
          HsStrTy _ _ -> typeSymbolKind
  in [ TyLitOccurrence
       { locatedName = L span Nothing
       , description = "HsTyLit"
       , kind = kind
       }
     ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsTypeNames (L _span (HsOpTy _ _ name _)) =
#else
hsTypeNames (L _span (HsOpTy _ name _)) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "HsOpTy"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsTypeNames (L span (HsTupleTy _ tupleSort types))
#else
hsTypeNames (L span (HsTupleTy tupleSort types))
#endif
  | null types =
    let sort =
          case tupleSort of
            HsUnboxedTuple -> UnboxedTuple
            HsBoxedTuple -> BoxedTuple
            HsConstraintTuple -> ConstraintTuple
            HsBoxedOrConstraintTuple -> BoxedTuple
    in [ NameOccurrence
         { locatedName = L span (Just $ tupleTyConName sort 0)
         , description = "HsTupleTy"
         , isBinder = False
         }
       ]
  | otherwise = []
--https://ghc.haskell.org/trac/ghc/ticket/13737
--hsTypeNames (L span (HsExplicitListTy _kind types)) = ...
--hsTypeNames (L span (HsExplicitTupleTy _kind types)) = ...
hsTypeNames _ = []


#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
hsTyVarBndrNames :: HsTyVarBndr GhcRn -> [NameOccurrence]
#else
hsTyVarBndrNames :: HsTyVarBndr Name -> [NameOccurrence]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsTyVarBndrNames (UserTyVar _ n) =
#else
hsTyVarBndrNames (UserTyVar n) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> n
    , description = "UserTyVar"
    , isBinder = True
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsTyVarBndrNames (KindedTyVar _ n _) =
#else
hsTyVarBndrNames (KindedTyVar n _) =
#endif
  [ NameOccurrence
    { locatedName = Just <$> n
    , description = "KindedTyVar"
    , isBinder = True
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
hsTyVarBndrNames _ = []
#endif


#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
tyClDeclNames :: LTyClDecl GhcRn -> [NameOccurrence]
#else
tyClDeclNames :: LTyClDecl Name -> [NameOccurrence]
#endif
tyClDeclNames (L _span DataDecl {..}) =
  [ NameOccurrence
    { locatedName = Just <$> tcdLName
    , description = "DataDecl"
    , isBinder = True
    }
  ]
tyClDeclNames (L _span SynDecl {..}) =
  [ NameOccurrence
    { locatedName = Just <$> tcdLName
    , description = "SynDecl"
    , isBinder = True
    }
  ]
tyClDeclNames (L _span ClassDecl {..}) =
  NameOccurrence
  { locatedName = Just <$> tcdLName
  , description = "ClassDecl"
  , isBinder = True
  } :
  concatMap
    ((\(names1, names2) -> map toNameOcc names1 ++ map toNameOcc names2) . unLoc)
    tcdFDs
  where
    toNameOcc :: Located Name -> NameOccurrence
    toNameOcc n =
      NameOccurrence
      { locatedName = Just <$> n
      , description = "FunDep"
      , isBinder = False
      }
tyClDeclNames _ = []

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
familyDeclNames :: FamilyDecl GhcRn -> [NameOccurrence]
#else
familyDeclNames :: FamilyDecl Name -> [NameOccurrence]
#endif
familyDeclNames FamilyDecl {..} =
  [ NameOccurrence
    { locatedName = Just <$> fdLName
    , description = "FamilyDecl"
    , isBinder = True
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
familyDeclNames _ = []
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
familyEqNames :: FamEqn GhcRn (HsTyPats GhcRn) (LHsType GhcRn) -> [NameOccurrence]
familyEqNames FamEqn {feqn_tycon = tyCon} =
  [ NameOccurrence
    { locatedName = Just <$> tyCon
    , description = "FamEqn"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
familyEqNames _ = []
#endif

dataEqNames :: FamEqn GhcRn (HsTyPats GhcRn) (HsDataDefn GhcRn) -> [NameOccurrence]
dataEqNames FamEqn {feqn_tycon = tyCon} =
  [ NameOccurrence
    { locatedName = Just <$> tyCon
    , description = "FamEqn"
    , isBinder = False
    }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
dataEqNames _ = []
#endif

#else
tyFamilyEqNames :: TyFamEqn Name (HsTyPats Name) -> [NameOccurrence]
tyFamilyEqNames TyFamEqn {tfe_tycon = tyCon} =
  [ NameOccurrence
    { locatedName = Just <$> tyCon
    , description = "TyFamEqn"
    , isBinder = False
    }
  ]

tyFamilyDefEqNames :: TyFamEqn Name (LHsQTyVars Name) -> [NameOccurrence]
tyFamilyDefEqNames TyFamEqn {tfe_tycon = tyCon} =
  [ NameOccurrence
    { locatedName = Just <$> tyCon
    , description = "TyFamEqn"
    , isBinder = False
    }
  ]

dataFamInstDeclNames :: DataFamInstDecl Name -> [NameOccurrence]
dataFamInstDeclNames DataFamInstDecl {dfid_tycon = tyCon} =
  [ NameOccurrence
    { locatedName = Just <$> tyCon
    , description = "DataFamInstDecl"
    , isBinder = False
    }
  ]
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
conDeclNames :: ConDecl GhcRn -> [NameOccurrence]
#else
conDeclNames :: ConDecl Name -> [NameOccurrence]
#endif
conDeclNames con =
  case con of
    ConDeclGADT {con_names = names} ->
      map
        (\n ->
            NameOccurrence
            { locatedName = Just <$> n
            , description = "ConDeclGADT"
            , isBinder = True
            })
        names
    ConDeclH98 {con_name = name} ->
      [ NameOccurrence
        { locatedName = Just <$> name
        , description = "ConDeclH98"
        , isBinder = True
        }
      ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
    _ -> []
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
foreignDeclNames :: ForeignDecl GhcRn -> [NameOccurrence]
#else
foreignDeclNames :: ForeignDecl Name -> [NameOccurrence]
#endif
foreignDeclNames decl =
  [ NameOccurrence
    { locatedName = Just <$> fd_name decl
    , description = "ForeignDecl"
    , isBinder = True
    }
  ]

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
roleAnnotationNames :: RoleAnnotDecl GhcRn -> [NameOccurrence]
#else
roleAnnotationNames :: RoleAnnotDecl Name -> [NameOccurrence]
#endif
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
roleAnnotationNames (RoleAnnotDecl _ n _) =
#else
roleAnnotationNames (RoleAnnotDecl n _) =
#endif
  [ NameOccurrence
      { locatedName = Just <$> n
      , description = "RoleAnnotDecl"
      , isBinder = False
      }
  ]
#if MIN_VERSION_GLASGOW_HASKELL(8,6,1,0)
roleAnnotationNames _ = []
#endif

#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
injectivityAnnotationNames :: InjectivityAnn GhcRn -> [NameOccurrence]
#else
injectivityAnnotationNames :: InjectivityAnn Name -> [NameOccurrence]
#endif
injectivityAnnotationNames (InjectivityAnn lhsName rhsNames) =
  injAnnNameOcc lhsName : map injAnnNameOcc rhsNames
  where
    injAnnNameOcc :: GenLocated SrcSpan Name -> NameOccurrence
    injAnnNameOcc n =
      NameOccurrence
        { locatedName = Just <$> n
        , description = "InjectivityAnn"
        , isBinder = False
        }

