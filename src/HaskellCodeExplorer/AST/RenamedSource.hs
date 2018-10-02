{-# LANGUAGE CPP #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
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
  , DataFamInstDecl(..)
  , FamilyDecl(..)
  , FieldOcc(..)
  , FixitySig(..)
  , ForeignDecl(..)
  , GenLocated(..)
  , HsBindLR(..)
  , HsExpr(..)
  , HsPatSynDetails(..)
  , HsRecField'(..)
  , HsTupleSort(..)
  , HsTyLit(..)
  , HsTyPats
  , HsTyVarBndr(..)
  , HsType(..)
  , IE(..)
  , LHsBindLR
  , LHsExpr
  , LHsQTyVars(..)
  , LHsType
  , LPat
  , LSig
  , LTyClDecl
  , Located
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
  , TyFamEqn(..)
  , Type
  , unLoc
  )
import HaskellCodeExplorer.GhcUtils (hsPatSynDetails, ieLocNames)
import Prelude hiding (span)
import TysWiredIn
  ( nilDataConName  
  , tupleTyConName
  , typeNatKind
  , typeSymbolKind
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
     tyFamilyEqNames `extQ`
     tyFamilyDefEqNames `extQ`
     dataFamInstDeclNames `extQ`
     conDeclNames `extQ`
     importNames `extQ`
     hsTyVarBndrNames `extQ`
     hsPatSynDetailsNames `extQ`
     conDeclFieldNames `extQ`
     hsRecFieldExprNames `extQ`
     hsRecAmbFieldExprNames `extQ`
     hsRecFieldPatNames `extQ`
     foreignDeclNames)

fieldOccName :: Bool -> FieldOcc Name -> NameOccurrence
fieldOccName isBinder (FieldOcc (L span _) name) =
  NameOccurrence
    { locatedName = L span (Just name)
    , description = "FieldOcc"
    , isBinder = isBinder
    }

conDeclFieldNames :: ConDeclField Name -> [NameOccurrence]
conDeclFieldNames ConDeclField {..} =
  map (fieldOccName True . unLoc) cd_fld_names

hsRecFieldExprNames ::
     HsRecField' (FieldOcc Name) (LHsExpr Name) -> [NameOccurrence]
hsRecFieldExprNames HsRecField {..} = [fieldOccName False $ unLoc hsRecFieldLbl]

hsRecAmbFieldExprNames ::
     HsRecField' (AmbiguousFieldOcc Name) (LHsExpr Name) -> [NameOccurrence]
hsRecAmbFieldExprNames HsRecField {..} =
  let (L span recField) = hsRecFieldLbl
      mbName =
        case recField of
          Ambiguous _ _ -> Nothing
          Unambiguous _ name -> Just name
   in [ NameOccurrence
          { locatedName = L span mbName
          , description = "AmbiguousFieldOcc"
          , isBinder = False
          }
      ]

hsRecFieldPatNames ::
     HsRecField' (FieldOcc Name) (LPat Name) -> [NameOccurrence]
hsRecFieldPatNames HsRecField {..} = [fieldOccName False $ unLoc hsRecFieldLbl]

hsExprNames :: LHsExpr Name -> [NameOccurrence]
hsExprNames (L _span (HsVar name)) =
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
hsExprNames (L _span (RecordCon name _conLike _instFun _binds)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "RecordCon"
    , isBinder = False
    }
  ]
hsExprNames (L _span (HsRecFld (Unambiguous (L span _) name))) =
  [ NameOccurrence
    { locatedName = L span (Just name)
    , description = "HsRecFld"
    , isBinder = False
    }
  ]
hsExprNames (L _span (HsRecFld (Ambiguous (L span _) _name))) =
  [ NameOccurrence
    { locatedName = L span Nothing
    , description = "HsRecFld"
    , isBinder = False
    }
  ]
hsExprNames _ = []

matchGroupNames :: MatchGroup Name (LHsExpr Name) -> [NameOccurrence]
matchGroupNames =
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)      
  mapMaybe (fmap toNameOcc . matchContextName . m_ctxt . unLoc) .
#else
  mapMaybe (fmap toNameOcc . matchFixityName . m_fixity . unLoc) .
#endif
  unLoc . mg_alts
  where
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)    
    matchContextName :: HsMatchContext Name -> Maybe (Located Name)
    matchContextName (FunRhs name _ _bool) = Just name
    matchContextName _ = Nothing   
#else
    matchFixityName :: MatchFixity Name -> Maybe (Located Name)
    matchFixityName NonFunBindMatch = Nothing
    matchFixityName (FunBindMatch name _bool) = Just name
#endif
    toNameOcc :: Located Name -> NameOccurrence
    toNameOcc n =
      NameOccurrence
        {locatedName = Just <$> n, description = "Match", isBinder = True}

bindNames :: LHsBindLR Name Name -> [NameOccurrence]
bindNames (L _span (PatSynBind PSB {..})) =
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

importNames :: IE Name -> [NameOccurrence]
importNames =
  map
    (\name ->
        NameOccurrence
        { locatedName = Just <$> name
        , description = "IE"
        , isBinder = False
        }) .
  ieLocNames

patNames :: LPat Name -> [NameOccurrence]
patNames (L _span (VarPat name)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "VarPat"
    , isBinder = True
    }
  ]
patNames (L _span (ConPatIn name _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "ConPatIn"
    , isBinder = False
    }
  ]
patNames (L _span (AsPat name _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "AsPat"
    , isBinder = True
    }
  ]
patNames (L _span (NPlusKPat name _ _ _ _ _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "NPlusKPat"
    , isBinder = True
    }
  ]
patNames _ = []

sigNames :: LSig Name -> [NameOccurrence]
sigNames (L _span (TypeSig names _)) =
  map
    (\n ->
        NameOccurrence
        { locatedName = Just <$> n
        , description = "TypeSig"
        , isBinder = False
        })
    names
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)    
sigNames (L _span (PatSynSig names _)) =
  map (\name -> NameOccurrence (Just <$> name) "PatSynSig" False) names
#else
sigNames (L _span (PatSynSig name _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "PatSynSig"
    , isBinder = False
    }
  ]
#endif
sigNames (L _span (ClassOpSig _ names _)) =
  map
    (\n ->
        NameOccurrence
        { locatedName = Just <$> n
        , description = "ClassOpSig"
        , isBinder = True
        })
    names
sigNames (L _span (FixSig (FixitySig names _))) =
  map
    (\n ->
        NameOccurrence
        { locatedName = Just <$> n
        , description = "FixitySig"
        , isBinder = False
        })
    names
sigNames (L _span (InlineSig name _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "InlineSig"
    , isBinder = False
    }
  ]
sigNames (L _span (SpecSig name _ _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "SpecSig"
    , isBinder = False
    }
  ]
sigNames (L _span (MinimalSig _ (L _ boolFormula))) =
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

hsTypeNames :: LHsType Name -> [NameOccurrence]
#if MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
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
hsTypeNames (L span (HsTyLit lit)) =
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
hsTypeNames (L _span (HsOpTy _ name _)) =
  [ NameOccurrence
    { locatedName = Just <$> name
    , description = "HsOpTy"
    , isBinder = False
    }
  ]
hsTypeNames (L span (HsTupleTy tupleSort types))
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

hsTyVarBndrNames :: HsTyVarBndr Name -> [NameOccurrence]
hsTyVarBndrNames (UserTyVar n) =
  [ NameOccurrence
    { locatedName = Just <$> n
    , description = "UserTyVar"
    , isBinder = True
    }
  ]
hsTyVarBndrNames (KindedTyVar n _) =
  [ NameOccurrence
    { locatedName = Just <$> n
    , description = "KindedTyVar"
    , isBinder = True
    }
  ]

tyClDeclNames :: LTyClDecl Name -> [NameOccurrence]
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

familyDeclNames :: FamilyDecl Name -> [NameOccurrence]
familyDeclNames FamilyDecl {..} =
  [ NameOccurrence
    { locatedName = Just <$> fdLName
    , description = "FamilyDecl"
    , isBinder = True
    }
  ]

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

conDeclNames :: ConDecl Name -> [NameOccurrence]
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

foreignDeclNames :: ForeignDecl Name -> [NameOccurrence]
foreignDeclNames decl =
  [ NameOccurrence
    { locatedName = Just <$> fd_name decl
    , description = "ForeignDecl"
    , isBinder = True
    }
  ]
