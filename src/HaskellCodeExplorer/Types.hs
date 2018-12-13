{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module HaskellCodeExplorer.Types where

import Control.DeepSeq (NFData)
import qualified Data.Aeson as A
import Data.Aeson.Types (Options, defaultOptions, omitNothingFields)
import Data.Generics
  ( Constr
  , Data(..)
  , DataType
  , Fixity(..)
  , constrIndex
  , gcast2
  , mkConstr
  , mkDataType
  )
import qualified Data.HashMap.Strict as HM
import Data.Hashable (Hashable)
import qualified Data.IntMap.Strict as IM
import qualified Data.IntervalMap.Strict as IVM
import qualified Data.List as L
import Data.Maybe (fromMaybe, isJust)
import Data.Serialize (Get, Serialize(..))
import qualified Data.Set as S      
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Text.Lazy (toStrict)
import qualified Data.Vector as V
import Data.Version (Version(..),showVersion)
import Documentation.Haddock.Types
  ( DocH(..)
  , Example(..)
  , Header(..)
  , Hyperlink(..)
  , Picture(..)
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
  , Table(..)
  , TableCell(..)
  , TableRow(..)  
#endif    
  )
import GHC.Generics (Generic)
import Prelude hiding (id)
import Text.Blaze.Html.Renderer.Text (renderHtml)
import qualified Text.Blaze.Html5 as Html
import qualified Text.Blaze.Html5.Attributes as Attr

--------------------------------------------------------------------------------
-- Package info
--------------------------------------------------------------------------------

data PackageInfo modInfo = PackageInfo
  { id :: PackageId
  , moduleMap :: HM.HashMap HaskellModulePath modInfo
  , moduleNameMap :: HM.HashMap HaskellModuleName (HM.HashMap ComponentId HaskellModulePath)
  , directoryTree :: DirTree
  , externalIdInfoMap :: Trie Char ExternalIdentifierInfo
  -- ^ All external identifiers defined in the package
  , externalIdOccMap :: HM.HashMap ExternalId (S.Set IdentifierSrcSpan)
  -- ^ All occurrences of each external identifier in the package
  } deriving (Show, Eq, Generic, Data)

data PackageId = PackageId
  { name :: T.Text
  , version :: Data.Version.Version
  } deriving (Show, Eq, Ord, Generic, Data)

packageIdToText :: PackageId -> T.Text
packageIdToText (PackageId name version) =
  T.concat [name, "-", T.pack $ showVersion version]

packageName :: PackageInfo a -> T.Text
packageName =
  (name :: (PackageId -> T.Text)) . (id :: PackageInfo a -> PackageId)

data IdentifierSrcSpan = IdentifierSrcSpan
  { modulePath :: HaskellModulePath
  , line :: Int
  , startColumn :: Int
  , endColumn :: Int
  } deriving (Show, Eq, Ord, Generic, Data)

data DirTree
  = Dir { name :: FilePath
        , contents :: [DirTree] }
  | File { name :: FilePath
         , path :: FilePath
         , isHaskellModule :: Bool }
  deriving (Show, Eq, Generic, Data)

newtype ComponentId = ComponentId
  { getComponentId :: T.Text
  } deriving (Show, Eq, Ord, Generic, A.ToJSONKey, Data, Hashable)

data ComponentType
  = Setup
  | Lib
  | SubLib T.Text
  | FLib T.Text
  | Exe T.Text
  | Test T.Text
  | Bench T.Text
  deriving (Show, Eq, Generic, Data)

isLibrary :: ComponentType -> Bool
isLibrary Lib = True
isLibrary (SubLib _) = True
isLibrary (FLib _) = True
isLibrary _ = False

packageInfoBinaryFileName :: FilePath
packageInfoBinaryFileName = "packageInfo"

packageInfoJsonFileName :: FilePath
packageInfoJsonFileName = "packageInfo.json"

defaultOutputDirectoryName :: FilePath
defaultOutputDirectoryName = ".haskell-code-explorer"

--------------------------------------------------------------------------------
-- A simple Trie implementation
--------------------------------------------------------------------------------

data Trie k v = Trie
  { values :: S.Set v
  , children :: HM.HashMap k (Trie k v)
  } deriving (Show, Eq, Generic, Data)

emptyTrie :: Trie k v
emptyTrie = Trie S.empty HM.empty

insertToTrie ::
     (Hashable k, Eq k, Ord v)
  => (v -> S.Set v -> S.Set v)
  -> [k]
  -> v
  -> Trie k v
  -> Trie k v
insertToTrie f [] v (Trie vals children) = Trie (f v vals) children
insertToTrie f word@(first:rest) val (Trie vals children) =
  case HM.lookup first children of
    Just trie ->
      Trie vals (HM.insert first (insertToTrie f rest val trie) children)
    Nothing ->
      insertToTrie f word val (Trie vals (HM.insert first emptyTrie children))

match :: (Hashable k, Eq k, Ord v) => [k] -> Trie k v -> S.Set v
match (first:rest) (Trie _ children) =
  maybe S.empty (match rest) (HM.lookup first children)
match [] (Trie val children) =
  S.union val $
  S.unions
    [S.union v $ match [] trie | (_, trie@(Trie v _)) <- HM.toList children]

--------------------------------------------------------------------------------
-- Module info
--------------------------------------------------------------------------------

data ModuleInfo = ModuleInfo
  { id :: HaskellModulePath
  , name :: HaskellModuleName
  , source :: V.Vector T.Text
    -- ^ Source code of the module
  , transformation :: SourceCodeTransformation
  , exprInfoMap :: ExpressionInfoMap
    -- ^ Type of each expression in the module
  , idOccMap :: IdentifierOccurrenceMap
    -- ^ All occurrences of each identifier in the module
  , idInfoMap :: IdentifierInfoMap
    -- ^ Information about each identifier in the module
  , declarations :: [Declaration]
  , definitionSiteMap :: DefinitionSiteMap
    -- ^ Definition site of each top-level value, type, and type class instance    
  , externalIds :: [ExternalIdentifierInfo]
  } deriving (Show, Eq, Generic, Data)

type ExpressionInfoMap = IVM.IntervalMap (Int, Int) ExpressionInfo
type IdentifierOccurrenceMap = IM.IntMap [((Int, Int), IdentifierOccurrence)]
type IdentifierInfoMap = HM.HashMap InternalId IdentifierInfo

data DefinitionSiteMap = DefinitionSiteMap
  { values :: HM.HashMap OccName DefinitionSite
  , types :: HM.HashMap OccName DefinitionSite
  , instances :: HM.HashMap T.Text DefinitionSite
  } deriving (Show, Eq, Generic, Data)

data DefinitionSite = DefinitionSite
  { location :: LocationInfo
  , documentation :: Maybe HTML
  } deriving (Show, Eq, Generic, Data)

type HTML = T.Text

newtype OccName = OccName
  { getOccName :: T.Text
  } deriving (Show, Eq, Ord, Generic, A.ToJSONKey, Data, Hashable)

-- | 'CompactModuleInfo' contains a subset of fields of 'ModuleInfo'.
data CompactModuleInfo = CompactModuleInfo
  { id :: HaskellModulePath
  , name :: HaskellModuleName
  , exprInfoMap :: ExpressionInfoMap
  , definitionSiteMap :: DefinitionSiteMap
  , source :: V.Vector T.Text
  } deriving (Show, Eq, Generic, Data)

haskellPreprocessorExtensions :: [FilePath]
haskellPreprocessorExtensions =
  [".hsc", ".chs", ".cpphs", ".gc", ".x", ".y", ".ly"]

toCompactPackageInfo :: PackageInfo ModuleInfo -> PackageInfo CompactModuleInfo
toCompactPackageInfo PackageInfo {..} =
  PackageInfo
    { id = id    
    , moduleMap = HM.map toCompactModuleInfo moduleMap
    , moduleNameMap = moduleNameMap
    , directoryTree = directoryTree
    , externalIdOccMap = externalIdOccMap
    , externalIdInfoMap = externalIdInfoMap
    }

toCompactModuleInfo :: ModuleInfo -> CompactModuleInfo
toCompactModuleInfo ModuleInfo {..} =
  CompactModuleInfo
    { id = id
    , name = name
    , exprInfoMap = exprInfoMap
    , definitionSiteMap = definitionSiteMap
    , source = source
    }

newtype HaskellModuleName = HaskellModuleName
  { getHaskellModuleName :: T.Text
  } deriving (Show, Eq, Ord, Generic, A.ToJSONKey, Data)

newtype HaskellModulePath = HaskellModulePath
  { getHaskellModulePath :: T.Text
  } deriving (Show, Eq, Ord, Generic, A.ToJSONKey, Data)

newtype HaskellFilePath = HaskellFilePath
  { getHaskellFilePath :: T.Text
  } deriving (Show, Eq, Ord, Generic, A.ToJSONKey, Data)

-- | Haskell identifier (value or type)
data IdentifierInfo = IdentifierInfo
  { sort :: NameSort
  , occName :: OccName
  , demangledOccName :: T.Text
  , nameSpace :: NameSpace
  , locationInfo :: LocationInfo
  , idType :: Type
  , details :: Maybe IdDetails
  , doc :: Maybe HTML
  , internalId :: InternalId
  , externalId :: Maybe ExternalId
  , isExported :: Bool
  } deriving (Show, Eq, Ord, Generic, Data)

data NameSort
  = External
  | Internal
  deriving (Show, Eq, Ord, Generic, Data)

data NameSpace
  = VarName
  | DataName
  | TvName
  | TcClsName
  deriving (Show, Eq, Ord, Generic, Data)

data IdDetails
  = VanillaId
  | RecSelId
  | RecSelIdNaughty
  | DataConWorkId
  | DataConWrapId
  | ClassOpId
  | PrimOpId
  | FCallId
  | TickBoxOpId
  | DFunId
  | CoVarId
  | JoinId
  deriving (Show, Eq, Ord, Generic, Data)

-- | Each Haskell identifier has an 'InternalId' that is unique within a single module
newtype InternalId = InternalId
  { getInternalId :: T.Text
  } deriving (Show, Eq, Ord, Generic, Data, Hashable, A.ToJSONKey)

newtype ExternalId = ExternalId
  { getExternalId :: T.Text
  } deriving (Show, Eq, Ord, Generic, Data, Hashable, A.ToJSONKey)

newtype ExternalIdentifierInfo = ExternalIdentifierInfo
  { getIdentifierInfo :: IdentifierInfo
  } deriving (Eq, Show, Generic, Data)

instance Ord ExternalIdentifierInfo where
  compare (ExternalIdentifierInfo i1) (ExternalIdentifierInfo i2) =
    case compare
           (T.length . demangledOccName $ i1)
           (T.length . demangledOccName $ i2) of
      GT -> GT
      LT -> LT
      EQ ->
        case compare (demangledOccName i1) (demangledOccName i2) of
          GT -> GT
          LT -> LT
          EQ ->            
            compare
              (internalId (i1 :: IdentifierInfo))
              (internalId (i2 :: IdentifierInfo))
        
data ExpressionInfo = ExpressionInfo
  { description :: T.Text
  , exprType :: Maybe Type
  } deriving (Show, Eq, Generic, Data)

-- | Occurrence of an identifier in a source code
data IdentifierOccurrence = IdentifierOccurrence
  { internalId :: Maybe InternalId
  , internalIdFromRenamedSource :: Maybe InternalId
  , isBinder :: Bool
  , instanceResolution :: Maybe InstanceResolution
  , idOccType :: Maybe Type
  -- ^ Instantiated type of an identifier
  , typeArguments :: Maybe [Type]
  , description :: T.Text
  , sort :: IdentifierOccurrenceSort
  } deriving (Show, Eq, Ord, Generic, Data)

data IdentifierOccurrenceSort
  = ValueId
  | TypeId
  | ModuleId LocationInfo
  deriving (Show, Eq, Ord, Generic, Data)

data Type = Type
  { components :: [TypeComponent]
  , componentsExpanded :: Maybe [TypeComponent]
  -- ^ Components of a type with all type synonyms expanded
  } deriving (Show, Eq, Ord, Generic, Data)

data TypeComponent
  = Text T.Text
  | TyCon { internalId :: InternalId
          , name :: T.Text }
  deriving (Show, Eq, Ord, Generic, Data)

-- | Tree of instances
data InstanceResolution =
  Instance
  { name :: T.Text
  -- ^ Type of an instance, e.g., "instance Show a => ClassName a"
  , instanceType :: Type
  , types :: [Type]
  -- ^ Types at which type variables of a class are instantiated
  , location :: LocationInfo
  , instances :: [InstanceResolution]  
  }
  | Stop
  deriving (Show,Eq,Ord,Generic,Data)

data SourceCodeTransformation = SourceCodeTransformation
  { totalLines :: Int
  , filePath :: HaskellModulePath
  , linePragmas :: S.Set LinePragma
  , fileIndex :: HM.HashMap HaskellFilePath (S.Set FileLocation)
  -- ^ Map from an original filename to its locations in a preprocessed source code
  } deriving (Show, Eq, Generic, Data)

-- | Location of a file included by a preprocessor
data FileLocation = FileLocation
  { lineStart :: Int
  , lineEnd :: Int
  , offset :: Int
  -- ^ (line number in a preprocessed file) - (line number in an original file) + 1
  } deriving (Show, Eq, Generic, Data)

-- | Line pragma inserted by a preprocessor
data LinePragma = LinePragma
  { filePath :: HaskellFilePath
  , lineNumberPreprocessed :: Int
  , lineNumberOriginal :: Int
  } deriving (Show, Eq, Generic, Data)

fromOriginalLineNumber ::
     SourceCodeTransformation -> (HaskellFilePath, Int) -> Either T.Text Int
fromOriginalLineNumber SourceCodeTransformation {linePragmas = pragmas} (_originalFileName, originalLineNumber)
  | S.null pragmas = Right originalLineNumber
fromOriginalLineNumber SourceCodeTransformation {fileIndex = index} (originalFileName, originalLineNumber) =
  case HM.lookup originalFileName index of
    Just set ->
      -- lookupGE finds smallest element greater or equal to the given one
      case S.lookupGE (FileLocation 1 originalLineNumber 1) set of
        Just FileLocation {..} -> Right $ originalLineNumber + offset
        Nothing ->
          Left $
          T.concat
            [ "Cannot find "
            , T.pack . show $ (originalFileName, originalLineNumber)
            , " in "
            , T.pack $ show index
            ]
    Nothing ->
      Left $
      T.concat
        [ "Cannot find file "
        , T.pack . show $ originalFileName
        , " in "
        , T.pack $ show index
        ]
        
data Declaration = Declaration
  { sort :: DeclarationSort
  , name :: T.Text
  , declType :: Maybe Type
  , isExported :: Bool
  , lineNumber :: Int
  } deriving (Show, Eq, Ord, Generic, Data)

data DeclarationSort
  = TyClD
  | InstD
  | ValD
  | ForD
  deriving (Show, Eq, Ord, Generic, Data)

data LocationInfo
  = ExactLocation { packageId :: PackageId
                  , modulePath :: HaskellModulePath
                  , moduleName :: HaskellModuleName
                  , startLine :: Int
                  , endLine :: Int
                  , startColumn :: Int
                  , endColumn :: Int }
  | ApproximateLocation { packageId :: PackageId
                        , moduleName :: HaskellModuleName
                        , entity :: LocatableEntity
                        , name :: T.Text
                        , haddockAnchorId :: Maybe T.Text
                        , componentId :: ComponentId }
  | UnknownLocation T.Text
  deriving (Show, Eq, Ord, Generic, Data)

data LocatableEntity
  = Typ
  | Val
  | Inst
  | Mod
  deriving (Show, Eq, Ord, Generic, Data)

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------

deriving instance (Data k) => Data (IVM.Interval k)

instance (Data k, Data v, Eq k, Ord k, Data (IVM.Interval k)) =>
         Data (IVM.IntervalMap k v) where
  gfoldl f z m = z IVM.fromList `f` IVM.toList m
  toConstr _ = fromListConstr
  gunfold k z c =
    case constrIndex c of
      1 -> k (z IVM.fromList)
      _ -> error "gunfold"
  dataTypeOf _ = intervalMapDataType
  dataCast2 = gcast2

fromListConstr :: Constr
fromListConstr = mkConstr intervalMapDataType "fromList" [] Prefix

intervalMapDataType :: DataType
intervalMapDataType = mkDataType "Data.IntervalMap" [fromListConstr]

deriving instance Generic (IVM.Interval k)

instance Hashable HaskellModuleName
instance Serialize HaskellModuleName
instance Hashable HaskellModulePath
instance Serialize HaskellModulePath
instance Hashable HaskellFilePath
instance Serialize HaskellFilePath
instance (Serialize k, Serialize v, Ord k) =>
         Serialize (IVM.IntervalMap k v) where
  put = put . IVM.toAscList
  get = IVM.fromAscList <$> Data.Serialize.get
instance Ord LinePragma where
  compare p1 p2 =
    compare
      (lineNumberPreprocessed (p1 :: LinePragma))
      (lineNumberPreprocessed (p2 :: LinePragma))
instance Ord FileLocation where
  compare l1 l2 = compare (lineEnd l1) (lineEnd l2)
instance Serialize LinePragma
instance Serialize FileLocation
instance Serialize SourceCodeTransformation
instance Serialize IdentifierInfo
instance Serialize InternalId
instance Serialize ExternalId
instance Serialize ExternalIdentifierInfo where
  put (ExternalIdentifierInfo info) = put info
  get = ExternalIdentifierInfo <$>(get :: Get IdentifierInfo)
instance Serialize InstanceResolution
instance Serialize OccName
instance Serialize IdDetails
instance Serialize NameSpace
instance Serialize DefinitionSiteMap
instance Serialize DefinitionSite
instance Serialize Declaration
instance Serialize NameSort
instance Serialize DeclarationSort
instance Serialize PackageId
instance Serialize Data.Version.Version
instance Serialize (PackageInfo ModuleInfo)
instance Serialize (PackageInfo CompactModuleInfo)
instance Serialize IdentifierSrcSpan
instance Serialize DirTree
instance Serialize ComponentId
instance Serialize ComponentType
instance Serialize T.Text where
  put = put . encodeUtf8
  get = decodeUtf8 <$> Data.Serialize.get
instance (Serialize k, Serialize v, Eq k,Hashable k) => Serialize (HM.HashMap k v) where
  put = put . HM.toList
  get = HM.fromList <$> get
instance Serialize ModuleInfo
instance Serialize CompactModuleInfo
instance (Serialize k) => Serialize (IVM.Interval k)
instance Serialize LocationInfo
instance Serialize IdentifierOccurrence
instance Serialize IdentifierOccurrenceSort
instance Serialize TypeComponent
instance (Serialize a) => Serialize (V.Vector a) where
  put = put . V.toList
  get = (\l -> V.fromListN (L.length l) l) <$> get
instance Serialize Type
instance Serialize ExpressionInfo
instance Serialize LocatableEntity
instance (Serialize k,Ord k,Serialize v,Ord v,Hashable k) => Serialize (Trie k v)
instance NFData HaskellModuleName
instance NFData HaskellModulePath
instance NFData HaskellFilePath
instance NFData LinePragma
instance NFData FileLocation
instance NFData SourceCodeTransformation
instance NFData IdentifierInfo
instance NFData InternalId
instance NFData ExternalId
instance NFData ExternalIdentifierInfo 
instance NFData InstanceResolution
instance NFData IdDetails
instance NFData NameSpace
instance NFData OccName
instance NFData DefinitionSiteMap
instance NFData DefinitionSite
instance NFData Declaration
instance NFData NameSort
instance NFData DeclarationSort
instance NFData PackageId
instance NFData (PackageInfo ModuleInfo)
instance NFData (PackageInfo CompactModuleInfo)
instance NFData IdentifierSrcSpan
instance NFData DirTree
instance NFData ComponentId
instance NFData ComponentType
instance NFData ModuleInfo
instance NFData CompactModuleInfo
instance NFData LocationInfo
instance NFData IdentifierOccurrence
instance NFData IdentifierOccurrenceSort
instance NFData TypeComponent
instance NFData Type
instance NFData ExpressionInfo
instance NFData LocatableEntity
instance (NFData k, Ord k, NFData v, Ord v, Hashable k) =>
         NFData (Trie k v)

omitNothingOptions :: Options
omitNothingOptions = defaultOptions {omitNothingFields = True}

instance A.ToJSON (PackageInfo a) where
  toJSON PackageInfo {..} =
    A.object
      [ ("id", A.toJSON $ packageIdToText id)
      , ("directoryTree", A.toJSON directoryTree)
      , ("modules", A.toJSON . HM.map (const ()) $ moduleMap)
      ]

instance A.ToJSON ModuleInfo where
  toJSON ModuleInfo {..} =
    let sourceCodeLines = zip [1 ..] $ V.toList source
        tokenizedLines =
          L.map
            (\(lineNumber, lineText) ->
               case IM.lookup lineNumber idOccMap of
                 Just identifiers -> (lineNumber, tokenize lineText identifiers)
                 Nothing ->
                   ( lineNumber
                   , [(lineText, (1, T.length lineText + 1), Nothing)]))
            sourceCodeLines
        html =
          Html.table Html.! Attr.class_ "source-code" $
          Html.tbody $ mapM_ (uncurry lineToHtml) tokenizedLines
     in A.object
          [ ("id", A.toJSON id)
          , ("name", A.toJSON name)
          , ("sourceCodeHtml", A.toJSON . renderHtml $ html)
          , ("identifiers", A.toJSON idInfoMap)
          , ("occurrences", A.toJSON $ idOccurrencesHashMap idOccMap)
          , ("declarations", A.toJSON declarations)
          ]
          
idOccurrencesHashMap ::
     IM.IntMap [((Int, Int), IdentifierOccurrence)]
  -> HM.HashMap T.Text IdentifierOccurrence
idOccurrencesHashMap =
  HM.fromList .
  concatMap
    (\(lineNum, occs) ->
       L.map
         (\((startCol, endCol), occ) ->
            (occurrenceLocationToText lineNum startCol endCol, occ))
         occs) .
  IM.toList 

idOccurrenceList ::
     IM.IntMap [((Int, Int), IdentifierOccurrence)]
  -> HM.HashMap T.Text IdentifierOccurrence
idOccurrenceList =
  HM.fromList .
  concatMap
    (\(lineNum, occs) ->
       L.map
         (\((startCol, endCol), occ) ->
            (occurrenceLocationToText lineNum startCol endCol, occ))
         occs) .
  IM.toList 

occurrenceLocationToText :: Int -> Int -> Int -> T.Text
occurrenceLocationToText lineNum startCol endCol =
  T.concat
    [ T.pack . show $ lineNum
    , "-"
    , T.pack . show $ startCol
    , "-"
    , T.pack . show $ endCol
    ]

lineToHtml :: Int
           -> [(T.Text, (Int, Int), Maybe IdentifierOccurrence)]
           -> Html.Html
lineToHtml lineNumber tokens =
  Html.tr $ do
    Html.td Html.! Attr.class_ "line-number" Html.!
      Attr.id (Html.textValue . T.append "LN" . T.pack $ show lineNumber) $
      Html.toHtml (T.pack $ show lineNumber)
    Html.td Html.! Attr.class_ "line-content" Html.!
      Html.dataAttribute "line" (Html.textValue $ T.pack . show $ lineNumber) Html.!
      Attr.id (Html.textValue . T.append "LC" . T.pack $ show lineNumber) $
      mapM_
        (\(content, (start, end), mbIdOcc) ->
           let addPositionAttrs :: Html.Html -> Html.Html
               addPositionAttrs htmlElement =
                 htmlElement Html.!
                 Html.dataAttribute
                   "start"
                   (Html.textValue $ T.pack . show $ start) Html.!
                 Html.dataAttribute "end" (Html.textValue $ T.pack . show $ end)
            in case mbIdOcc of
                 Just idOcc ->
                   addPositionAttrs $
                   Html.span Html.! Attr.class_ "identifier" Html.!
                   Attr.id
                     (Html.textValue .
                      maybe "" getInternalId . internalIdFromRenamedSource $
                      idOcc) Html.!
                   Html.dataAttribute
                     "occurrence"
                     (Html.textValue $
                      occurrenceLocationToText lineNumber start end) Html.!
                   Html.dataAttribute
                     "identifier"
                     (Html.textValue $
                      maybe "" getInternalId $
                      internalId (idOcc :: IdentifierOccurrence)) $
                   Html.toHtml content
                 Nothing -> addPositionAttrs . Html.span . Html.toHtml $ content)
        tokens

tokenize
  :: forall a.
     T.Text -- ^ Source code
  -> [((Int, Int), a)] -- ^ Identifier locations
                       -- The end position is defined to be the column /after/ the end of the
                       -- span. That is, a span of (1,1)-(1,2) is one character long, and a
                       -- span of (1,1)-(1,1) is zero characters long.                       
  -> [(T.Text, (Int, Int), Maybe a)]
tokenize line =
  L.reverse .
  (\(remainingLine, currentIndex, c) ->
     if T.null remainingLine
       then c
       else (remainingLine, (currentIndex, T.length line + 1), Nothing) : c) .
  L.foldl' split (line, 1, [])
  where
    split ::
         (T.Text, Int, [(T.Text, (Int, Int), Maybe a)])
      -> ((Int, Int), a)
      -> (T.Text, Int, [(T.Text, (Int, Int), Maybe a)])
    split (remainingLine, currentIndex, chunks) ((start, end), a)
      | start == currentIndex =
        let (chunk, remainingLine') = T.splitAt (end - start) remainingLine
            chunks' = (chunk, (start, end), Just a) : chunks
         in (remainingLine', end, chunks')
      | otherwise =
        let (chunkNoId, remainingLine') =
              T.splitAt (start - currentIndex) remainingLine
            (chunk, remainingLine'') = T.splitAt (end - start) remainingLine'
         in ( remainingLine''
            , end
            , (chunk, (start, end), Just a) :
              (chunkNoId, (currentIndex, start), Nothing) : chunks)

docToHtml ::
     forall mod id.
     (mod -> Html.Html)
  -> (id -> Html.Html)
  -> DocH mod id
  -> HTML
docToHtml modToHtml idToHtml = toStrict . renderHtml . toH
  where
    toH :: DocH mod id -> Html.Html
    toH (DocAppend doc1 doc2) = toH doc1 >> toH doc2
    toH (DocParagraph doc) = Html.p $ toH doc
    toH (DocIdentifier identifier) = Html.span $ idToHtml identifier
    toH (DocWarning doc) = Html.div Html.! Attr.class_ "warning" $ toH doc
    toH (DocEmphasis doc) = Html.em $ toH doc
    toH DocEmpty = mempty
    toH (DocBold doc) = Html.b $ toH doc
    toH (DocMonospaced doc) =
      Html.span Html.! Attr.class_ "source-code-font" $ toH doc
    toH (DocUnorderedList docs) = Html.ul $ mapM_ (Html.li . toH) docs
    toH (DocOrderedList docs) = Html.ol $ mapM_ (Html.li . toH) docs
    toH (DocDefList docs) =
      Html.dl $
      mapM_ (\(doc1, doc2) -> Html.dt (toH doc1) >> Html.dd (toH doc2)) docs
    toH (DocCodeBlock doc) = Html.div Html.! Attr.class_ "source-code" $ toH doc
    toH (DocIdentifierUnchecked modName) = modToHtml modName
    toH (DocModule str) = Html.span . Html.toHtml . T.pack $ str
    toH (DocHyperlink (Hyperlink url mbTitle)) =
      Html.a Html.! (Attr.href . Html.textValue . T.pack $ url) $
      Html.toHtml $ fromMaybe url mbTitle
    toH (DocPic (Picture uri mbTitle)) =
      Html.img Html.! (Attr.src . Html.textValue . T.pack $ uri) Html.!
      (Attr.title . Html.textValue . T.pack $ fromMaybe "" mbTitle)
    toH (DocMathInline str) =
      Html.span . Html.toHtml $ T.pack ("\\(" ++ str ++ "\\)")
    toH (DocMathDisplay str) =
      Html.div . Html.toHtml $ T.pack ("\\[" ++ str ++ "\\]")
    toH (DocAName str) =
      Html.a Html.! (Attr.id . Html.textValue . T.pack $ str) $ mempty
    toH (DocProperty str) =
      Html.div Html.! Attr.class_ "source-code" $ Html.toHtml $ T.pack str
    toH (DocExamples examples) =
      Html.div Html.! Attr.class_ "source-code" $
      mapM_
        (\(Example expr results) ->
           let htmlPrompt = Html.span $ Html.toHtml (">>> " :: String)
               htmlExpression = Html.span $ Html.toHtml (expr ++ "\n")
            in htmlPrompt >> htmlExpression >>
               mapM_ (Html.span . Html.toHtml) (unlines results))
        examples
    toH (DocString str) = Html.span . Html.toHtml $ T.pack str
    toH (DocHeader (Header level doc)) = toHeader level $ toH doc
      where
        toHeader 1 = Html.h1
        toHeader 2 = Html.h2
        toHeader 3 = Html.h3
        toHeader 4 = Html.h4
        toHeader 5 = Html.h5
        toHeader _ = Html.h6
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
    toH (DocTable (Table hs bs)) =
      let tableRowToH tdOrTh (TableRow cells) =
            Html.tr $ mapM_ (tableCellToH tdOrTh) cells
          tableCellToH tdOrTh (TableCell colspan rowspan doc) =
            (tdOrTh $ toH doc) Html.!?
            (colspan /= 1, (Attr.colspan (Html.stringValue $ show colspan))) Html.!?
            (rowspan /= 1, (Attr.rowspan (Html.stringValue $ show rowspan)))
       in Html.table $
          Html.thead (mapM_ (tableRowToH Html.th) hs) >>
          Html.tbody (mapM_ (tableRowToH Html.td) bs)
#endif          
        
instance A.ToJSON HaskellModuleName where
  toJSON (HaskellModuleName name) = A.String name
instance A.ToJSON HaskellModulePath where
  toJSON (HaskellModulePath path) = A.String path
instance A.ToJSON HaskellFilePath where
  toJSON (HaskellFilePath path) = A.String path  
instance A.ToJSON LinePragma where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON FileLocation where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON IdentifierInfo where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON InternalId where
  toJSON (InternalId text) = A.toJSON text
instance A.ToJSON ExternalId where
  toJSON (ExternalId text) = A.toJSON text    
instance A.ToJSON ExternalIdentifierInfo where
  toJSON (ExternalIdentifierInfo info) = A.toJSON info
instance A.ToJSON InstanceResolution where
  toJSON (Instance name typ types location instances) =
    A.object
      [ "name" A..= A.toJSON name
      , "types" A..= A.toJSON types
      , "location" A..= A.toJSON location
      , "instanceType" A..= A.toJSON typ
      , "instances" A..=
        (A.Array . V.fromList . Prelude.map A.toJSON $ instances)
      ]
  toJSON Stop = A.Null
instance A.ToJSON IdDetails where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON NameSpace where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON Declaration  
instance A.ToJSON NameSort
instance A.ToJSON OccName where
  toJSON (OccName name) = A.String name
instance A.ToJSON DeclarationSort
instance A.ToJSON PackageId
instance A.ToJSON ComponentId where
  toJSON (ComponentId id) = A.toJSON id
instance A.ToJSON ComponentType
instance A.ToJSON LocationInfo where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON LocatableEntity
instance A.ToJSON IdentifierOccurrence where
  toJSON IdentifierOccurrence {..} =
    A.object $
    [("sort", A.toJSON sort)] ++
    [("description", A.toJSON description)] ++
    [("internalId", A.toJSON internalId) | isJust internalId] ++
    [("isBinder", A.toJSON isBinder) | isBinder] ++
    [("instanceResolution", A.toJSON instanceResolution) | isJust instanceResolution] ++
    [("idOccType", A.toJSON idOccType) | isJust idOccType]
instance A.ToJSON IdentifierOccurrenceSort
instance A.ToJSON TypeComponent where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON Type where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON ExpressionInfo where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON DirTree    
instance A.ToJSON DefinitionSite where
  toJSON = A.genericToJSON omitNothingOptions
instance A.ToJSON IdentifierSrcSpan
instance A.ToJSON (IVM.Interval (Int, Int)) where
  toJSON (IVM.IntervalCO a b) = intervalToValue a b
  toJSON (IVM.ClosedInterval a b) = intervalToValue a b
  toJSON (IVM.OpenInterval a b) = intervalToValue a b
  toJSON (IVM.IntervalOC a b) = intervalToValue a b

intervalToValue :: (Int, Int) -> (Int, Int) -> A.Value
intervalToValue (l1, c1) (l2, c2) =
  A.object
    [ ("start", A.object [("line", A.toJSON l1), ("column", A.toJSON c1)])
    , ("end", A.object [("line", A.toJSON l2), ("column", A.toJSON c2)])
    ]

data SourceCodePreprocessing
  = AfterPreprocessing
  | BeforePreprocessing
  deriving (Show, Eq)

data Log
  = StdOut
  | ToFile FilePath
  deriving (Show, Eq)
