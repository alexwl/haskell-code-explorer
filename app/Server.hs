{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PatternGuards #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Main where

import Control.DeepSeq (NFData, force)
import Control.Exception
  ( SomeAsyncException
  , SomeException
  , fromException
  , handle
  , throwIO
  , throwIO
  , try
  )
import Control.Lens hiding(children,index)
import Control.Monad (foldM, unless)
import Control.Monad.Except (ExceptT(..))
import Control.Monad.Reader (MonadIO, MonadReader, ReaderT(..), asks, liftIO)
import Control.Monad.State.Strict (StateT(..))
import qualified Data.Aeson as A
import qualified Data.Aeson.Lens as AL
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Short as BSS
import Data.Default (def)
import Data.Either (lefts, rights)
import qualified Data.HashMap.Strict as HM
import Data.Hashable (Hashable)
import Data.IntervalMap.Interval (Interval(..), subsumes)
import qualified Data.IntervalMap.Strict as IVM
import qualified Data.List as L
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Vector as V
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
import qualified GHC.Compact as C
#else
import Data.Functor.Identity(Identity(..))
#endif
import Data.Pagination
  ( Paginated
  , hasNextPage
  , hasPrevPage
  , mkPagination
  , paginate
  , paginatedItems
  , paginatedPagesTotal
  )
import Data.Proxy (Proxy(..))
import Data.Semigroup ((<>))
import qualified Data.Serialize as Serialize
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Lazy (toStrict)
import Data.Text.Read(decimal)
import Data.Version (Version(..))
import GHC.Exts (Down(..), groupWith)
import GHC.Generics (Generic)
import qualified HaskellCodeExplorer.Types as HCE
import Network.HTTP.Types (hContentEncoding, hContentType, status200, status404)
import Network.URI.Encode (encode)
import Network.Mime (defaultMimeLookup)
import Network.Wai
  ( Application
  , Middleware
  , Response
  , pathInfo
  , requestHeaders
  , responseFile
  , responseLBS
  )
import Network.Wai.Handler.Warp (run)
import qualified Network.Wreq as Wreq
import Network.Wai.Middleware.RequestLogger
  ( Destination(..)
  , OutputFormat(..)
  , RequestLoggerSettings(..)
  , mkRequestLogger
  )
import Numeric.Natural(Natural)
import Options.Applicative
  ( Parser
  , (<**>)
  , (<|>)
  , auto
  , execParser
  , fullDesc
  , help
  , helper
  , info
  , long
  , metavar
  , option
  , optional
  , progDesc
  , short
  , some
  , strOption
  , switch
  )
import Servant
  ( (:<|>)(..)
  , (:>)
  , Capture
  , FromHttpApiData(..)
  , Get
  , Header
  , Headers
  , QueryParam
  , ServantErr
  , ServerT
  , ToHttpApiData(..)
  , addHeader
  , err404
  , err500
  , err502
  , errBody
  , serve
  )
import Servant.API.ContentTypes (AllCTRender(..), JSON)
import Servant.Server (Handler(..), hoistServer)
import Servant.Utils.Links (safeLink)
import System.Directory (doesFileExist)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath.Find
  ( FileType(..)
  , (&&?)
  , (/=?)
  , (==?)
  , (==?)
  , depth
  , filePath
  , fileType
  , find
  )
import System.FilePath.Posix ((</>), takeFileName)
import System.Log.FastLogger
  ( LoggerSet
  , defaultBufSize
  , newFileLoggerSet
  , newStdoutLoggerSet
  )
import Text.Blaze.Html.Renderer.Text (renderHtml)
import qualified Text.Blaze.Html5 as Html hiding (html, source)
import Data.FileEmbed (embedDir, embedFile)
import Data.Bifunctor (second)
import qualified Store

--------------------------------------------------------------------------------
-- Server config
--------------------------------------------------------------------------------

data ServerConfig = ServerConfig
  { configPackagesPath :: !PackagesPath
  , configPort :: !Int
  , configServeStaticFiles :: !Bool
  , configEnableExpressionInfo :: !Bool
  , configIndexDirectoryName :: !(Maybe FilePath)
  , configLog :: !HCE.Log
  , configStaticFilesUrlPrefix :: !String
  , configJsDistDirectory :: !(Maybe String)
  , configMaxPerPage :: !Int
  , configStore :: !(Maybe Store)
  , configUseHoogleApi :: !Bool
  } deriving (Show, Eq)

data PackagesPath
  = DirectoryWithPackages FilePath
  | Directories [FilePath]
  deriving (Show, Eq)

data Store
  = CreateStore FilePath
  | UseStore FilePath
  | UseStoreMmap FilePath
  deriving (Show, Eq)

configParser :: Parser ServerConfig
configParser =
  ServerConfig <$>
  ((DirectoryWithPackages <$>
    strOption
      (long "packages" <> metavar "PATH" <>
       help "Path to a directory with Cabal packages")) <|>
   Directories <$>
   some
     (strOption
        (long "package" <> short 'p' <> metavar "PATH" <>
         help "Path to a Cabal package (Default: '.')"))
   <|> pure (Directories ["."])) <*>
  (pure 8080 <|>
   option
     auto
     (long "port" <> help "Port to use (default is 8080)" <> metavar "PORT")) <*>
  (not <$> switch (long "no-static" <> help "Do not serve static files")) <*>
  (not <$>
   switch
     (long "no-expressions" <>
      help "Disable queries that return expressions inside selected span")) <*>
  optional
    (strOption
       (long "index-directory" <>
        help
          "Name of a directory with index (default is '.haskell-code-explorer')" <>
        metavar "DIRECTORY_NAME")) <*>
  (pure HCE.StdOut <|>
   (HCE.ToFile <$>
    strOption
      (long "logfile" <>
       help "Path to a log file (by default log is written to stdout)" <>
       metavar "PATH"))) <*>
  (pure "files" <|>
   strOption
     (long "static-url-prefix" <> metavar "STRING" <>
      help "URL prefix for static files (default is 'files')")) <*>
  optional
    (strOption
       (long "js-path" <> help "Path to a directory with javascript files" <>
        metavar "PATH")) <*>
  (pure 50 <|>
   option
     auto
     (long "max-per-page" <> metavar "INTEGER" <>
      help "Maximum number of items per page (default is 50)")) <*>
  optional
    (CreateStore <$>
     strOption
       (long "create-store" <>
        help "Create a key-value store from PackageInfo of each indexed package" <>
        metavar "PATH_TO_DATA_DIRECTORY") <|>
     (UseStore <$>
      strOption
        (long "use-store" <>
         help "Use existing key-value store. Read 'values' file into memory." <>
         metavar "PATH_TO_DATA_DIRECTORY")) <|>
     (UseStoreMmap <$>
      strOption
        (long "use-store-mmap" <>
         help "Use existing key-value store. mmap 'values' file." <>
         metavar "PATH_TO_DATA_DIRECTORY"))) <*>
  switch
    (long "use-hoogle-api" <>
     help
       "Use public Hoogle JSON API (https://github.com/ndmitchell/hoogle/blob/3dbf68bfd701f942d3af2e6debb74a0a78cd392e/docs/API.md#json-api) to get documentation for not indexed packages (disabled by default)")

--------------------------------------------------------------------------------
-- Loading packages
--------------------------------------------------------------------------------

data PackageVersions = PackageVersions
  { name :: T.Text
  , versions :: [Version]
  } deriving (Show, Ord, Eq, Generic)

instance Serialize.Serialize PackageVersions

data PackageMap
  = PackageMap (HM.HashMap PackageName (M.Map Version (HCE.PackageInfo HCE.CompactModuleInfo)))
  | PackageMapStore { store :: Store.Store
                    , packageMap :: HM.HashMap PackageName (M.Map Version HCE.PackageId) }

type PackagePathMap = HM.HashMap PackageId FilePath

newtype AllPackages = AllPackages BSL.ByteString

newtype PackageId = PackageId
  { getPackageId :: T.Text
  } deriving (Show, Eq, Hashable, Generic, NFData)

instance Serialize.Serialize PackageId

newtype PackageName = PackageName
  { getPackageName :: T.Text
  } deriving (Show, Eq, Hashable, Generic, NFData)

instance Serialize.Serialize PackageName
instance A.ToJSON PackageVersions

type GlobalReferenceMap = HM.HashMap HCE.ExternalId (S.Set GlobalReferences)
type GlobalIdentifierMap = HCE.Trie Char HCE.ExternalIdentifierInfo

data GlobalReferences = GlobalReferences
  { count :: Int
  , packageId :: T.Text
  } deriving (Show, Eq, Ord, Generic)

instance NFData GlobalReferences

instance Serialize.Serialize GlobalReferences

instance A.ToJSON GlobalReferences

instance Store.StoreItem (HCE.Trie Char HCE.ExternalIdentifierInfo) where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs (HCE.Trie Char HCE.ExternalIdentifierInfo) =
    ( HCE.PackageId
    , String
    , Proxy (HCE.Trie Char HCE.ExternalIdentifierInfo))
  itemKey (packageId, prefix, _) =
    BSS.toShort $ BS.concat
      [ "externalIdInfoMap"
      , "|"
      , TE.encodeUtf8 $ HCE.packageIdToText packageId
      , "|"
      , BSC.pack prefix
      ]

instance Store.StoreItem [HCE.ExternalIdentifierInfo] where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs [HCE.ExternalIdentifierInfo] = ( HCE.PackageId
                                              , String
                                              , Proxy [HCE.ExternalIdentifierInfo])
  itemKey (packageId, prefix, _) =
    BSS.toShort $ BS.concat
      [ "externalIdInfo"
      , "|"
      , TE.encodeUtf8 $ HCE.packageIdToText packageId
      , "|"
      , BSC.pack prefix
      ] 

instance Store.StoreItem (S.Set HCE.IdentifierSrcSpan) where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs (S.Set HCE.IdentifierSrcSpan) = ( HCE.PackageId
                                               , HCE.ExternalId
                                               , Proxy (S.Set HCE.IdentifierSrcSpan))
  itemKey (packageId, HCE.ExternalId extId, _) =
    BSS.toShort $ BS.concat
      [ "externalIdOcc"
      , "|"
      , TE.encodeUtf8 $ HCE.packageIdToText packageId
      , "|"
      , TE.encodeUtf8 extId
      ]

instance Store.StoreItem (HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath)) where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs (HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath)) =
    ( HCE.PackageId
    , Proxy (HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath)))
  itemKey (packageId,_) =
    BSS.toShort $ BS.append "moduleNameMap|" $ TE.encodeUtf8 $ HCE.packageIdToText packageId

instance (Serialize.Serialize modInfo) =>
         Store.StoreItem (HM.HashMap HCE.HaskellModulePath modInfo) where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs (HM.HashMap HCE.HaskellModulePath modInfo) =
    (HCE.PackageId,Proxy (HM.HashMap HCE.HaskellModulePath modInfo))    
  itemKey (packageId, _) =
    BSS.toShort $ BS.append "moduleMap|" $ TE.encodeUtf8 $ HCE.packageIdToText packageId

instance Store.StoreItem HCE.ExpressionInfoMap where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs HCE.ExpressionInfoMap = ( HCE.PackageId
                                       , HCE.HaskellModulePath
                                       , BS.ByteString  
                                       , Proxy HCE.ExpressionInfoMap)
  itemKey (packageId, HCE.HaskellModulePath modulePath, topLevelExprKey, _) =
    BSS.toShort $ BS.concat
      [ "exprInfoMap"
      , "|"
      , TE.encodeUtf8 $ HCE.packageIdToText packageId
      , "|"
      , TE.encodeUtf8 modulePath
      , "|"
      , topLevelExprKey  
      ]

instance Store.StoreItem (IVM.IntervalMap (Int, Int) BS.ByteString) where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs (IVM.IntervalMap (Int, Int) BS.ByteString) =
    ( HCE.PackageId
    , HCE.HaskellModulePath
    , Proxy (IVM.IntervalMap (Int, Int) BS.ByteString))
  itemKey (packageId, HCE.HaskellModulePath modulePath, _) =
    BSS.toShort $ BS.concat
      [ "topLevelExpr"
      , "|"
      , TE.encodeUtf8 $ HCE.packageIdToText packageId
      , "|"
      , TE.encodeUtf8 modulePath
      ]
    
instance Store.StoreItem HCE.DefinitionSiteMap where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs HCE.DefinitionSiteMap = ( HCE.PackageId
                                       , HCE.HaskellModulePath
                                       , Proxy HCE.DefinitionSiteMap)
  itemKey (packageId, HCE.HaskellModulePath modulePath, _) =
    BSS.toShort $ BS.concat
      [ "definitionSiteMap"
      , "|"
      , TE.encodeUtf8 $ HCE.packageIdToText packageId
      , "|"
      , TE.encodeUtf8 modulePath
      ]
      
instance Store.StoreItem (V.Vector T.Text) where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs (V.Vector T.Text) = ( HCE.PackageId
                                   , HCE.HaskellModulePath
                                   , Proxy (V.Vector T.Text))
  itemKey (packageId, HCE.HaskellModulePath modulePath, _) =
    BSS.toShort $ BS.concat
      [ "source"
      , "|"
      , TE.encodeUtf8 $ HCE.packageIdToText packageId
      , "|"
      , TE.encodeUtf8 modulePath
      ]

instance Store.StoreItem (HM.HashMap PackageName (M.Map Version HCE.PackageId)) where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs (HM.HashMap PackageName (M.Map Version HCE.PackageId)) =
    Proxy (HM.HashMap PackageName (M.Map Version HCE.PackageId))
  itemKey _ = "packageMap"

instance Store.StoreItem PackagePathMap where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs PackagePathMap = Proxy PackagePathMap
  itemKey _ = "packagePathMap"

instance Store.StoreItem GlobalReferenceMap where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs GlobalReferenceMap = Proxy GlobalReferenceMap
  itemKey _ = "globalReferenceMap"

newtype GlobalIdentifierMapWrapper = GlobalIdentifierMapWrapper
  { getGlobalIdentifierMap :: GlobalIdentifierMap
  }

instance Store.StoreItem GlobalIdentifierMapWrapper where
  toByteString (GlobalIdentifierMapWrapper idMap) = Serialize.encode idMap
  fromByteString bs = GlobalIdentifierMapWrapper <$> Serialize.decode bs
  type KeyArgs GlobalIdentifierMapWrapper = Proxy GlobalIdentifierMapWrapper
  itemKey _ = "globalIdentifierMap"  

instance Store.StoreItem [PackageVersions] where
  toByteString = Serialize.encode
  fromByteString = Serialize.decode
  type KeyArgs [PackageVersions] = Proxy [PackageVersions]
  itemKey _ = "packageVersions"

findTopLevelExpressions :: (Ord k) => IVM.IntervalMap k v -> [(Interval k, v)]
findTopLevelExpressions =
  L.foldl'
    (\topLevel interval ->
       case topLevel of
         [] -> [interval]
         topLevelIntervals@(currentTopLevelInterval:rest)
           | subsumes (fst currentTopLevelInterval) (fst interval) -> topLevelIntervals
           | subsumes (fst interval) (fst currentTopLevelInterval) ->
             interval : rest
           | otherwise -> interval : topLevelIntervals)         
    [] .
  IVM.assocs

splitIntervalMap ::
     (Show k, Ord k)
  => IVM.IntervalMap k v
  -> (IVM.IntervalMap k BS.ByteString, [(BS.ByteString, IVM.IntervalMap k v)])
splitIntervalMap ivmap =
  let topLevelExprs = findTopLevelExpressions ivmap
   in L.foldl'
        (\(index, ivMaps) (interval, _) ->
           let topLevelExpressionKey = BSC.pack $ show interval
            in ( IVM.insert interval topLevelExpressionKey index
               , (topLevelExpressionKey, IVM.within ivmap interval) : ivMaps))
        (IVM.empty, [])
        topLevelExprs

createStore :: FilePath -> ServerConfig -> IO ()
createStore storePath config = do
  packageDirectories <- findDirectories (configPackagesPath config)
  Store.createStore storePath $ \fileHandle -> do
    (errors, packageMap', packagePathMap', packageVersions', globalReferenceMap', globalIdentifiers', index'') <-
      foldM
        (\(errors, packageMap, packagePathMap, packageVersions, globalReferenceMap, globalIdentifiers, index) path -> do
           eitherPackageInfo <- loadPackageInfo config path
           case eitherPackageInfo of
             Right (packageInfo, packagePath) -> do
               let packageId =
                     HCE.id
                       (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)
                   addPackageInfo :: StateT Store.State IO ()
                   addPackageInfo = do
                     Store.add
                       (HCE.moduleNameMap packageInfo)
                       ( packageId
                       , Proxy :: Proxy (HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath)))
                     addExternalIdInfo packageId packageInfo
                     mapM_
                       (\(extId, occs) ->
                          Store.add
                            occs
                            ( packageId
                            , extId
                            , Proxy :: Proxy (S.Set HCE.IdentifierSrcSpan)))
                       (HM.toList $ HCE.externalIdOccMap packageInfo)
                     mapM_
                       (\(modulePath, moduleInfo) -> do
                          addExpressionInfo
                            packageId
                            modulePath
                            (HCE.exprInfoMap
                               (moduleInfo :: HCE.CompactModuleInfo))
                          Store.add
                            (HCE.definitionSiteMap
                               (moduleInfo :: HCE.CompactModuleInfo))
                            ( packageId
                            , modulePath
                            , Proxy :: Proxy HCE.DefinitionSiteMap)
                          Store.add
                            (HCE.source (moduleInfo :: HCE.CompactModuleInfo))
                            ( packageId
                            , modulePath
                            , Proxy :: Proxy (V.Vector T.Text))) .
                       HM.toList $
                       HCE.moduleMap packageInfo
               index' <- Store.writeValues fileHandle index addPackageInfo
               print $ T.unpack (HCE.packageIdToText packageId)
               return $
                 force
                   ( errors
                   , let packageVersion = HCE.version packageId
                         val = M.singleton packageVersion packageId
                      in HM.insertWith
                           M.union
                           (PackageName $ HCE.packageName packageInfo)
                           val
                           packageMap
                   , let key = PackageId $ HCE.packageIdToText packageId
                      in HM.insert key packagePath packagePathMap
                   , (\(HCE.PackageId name version) -> (name, [version]))
                       packageId :
                     packageVersions
                   , let references =
                           HM.map
                             (\spans ->
                                S.singleton
                                  (GlobalReferences
                                     (S.size spans)
                                     (HCE.packageIdToText packageId))) .
                           HCE.externalIdOccMap $
                           packageInfo
                      in HM.unionWith S.union references globalReferenceMap
                   , globalIdentifiers ++
                     filter
                       isExportedId
                       (trieValues $ HCE.externalIdInfoMap packageInfo)
                   , index')
             Left (errorMessage, path') ->
               return $
               force
                 ( (errorMessage, path') : errors
                 , packageMap
                 , packagePathMap
                 , packageVersions
                 , globalReferenceMap
                 , globalIdentifiers
                 , index))
        ([], HM.empty, HM.empty, [], HM.empty, [], M.empty)
        packageDirectories
    let versions =
          L.sortOn (T.toLower . (name :: PackageVersions -> T.Text)) .
          map (\(name, vers) -> PackageVersions name (L.sortOn Down vers)) .
          HM.toList . HM.fromListWith (++) $
          packageVersions'
    indexFinal <-
      Store.writeValues fileHandle index'' $ do
        Store.add packagePathMap' (Proxy :: Proxy PackagePathMap)
        Store.add versions (Proxy :: Proxy [PackageVersions])
        Store.add globalReferenceMap' (Proxy :: Proxy GlobalReferenceMap)
        let globalIdentifierMap =
              L.foldl'
                (\trie exportedId@(HCE.ExternalIdentifierInfo HCE.IdentifierInfo {HCE.demangledOccName = name}) ->
                   HCE.insertToTrie S.insert (T.unpack name) exportedId trie)
                HCE.emptyTrie
                globalIdentifiers'
        Store.add
          (GlobalIdentifierMapWrapper globalIdentifierMap)
          (Proxy :: Proxy GlobalIdentifierMapWrapper)
        Store.add
          packageMap'
          (Proxy :: Proxy (HM.HashMap PackageName (M.Map Version HCE.PackageId)))
    unless (null errors) $ do
      putStrLn "Package loading errors : "
      mapM_ (\(err, path) -> putStrLn $ path ++ " : " ++ err) errors
    return indexFinal

addExpressionInfo ::
     ( Show k
     , Ord k
     , Store.StoreItem (IVM.IntervalMap k v)
     , Store.StoreItem (IVM.IntervalMap k BSC.ByteString)
     , Store.KeyArgs (IVM.IntervalMap k BSC.ByteString) ~ ( a
                                                          , b
                                                          , Proxy (IVM.IntervalMap ( Int
                                                                                   , Int) BSC.ByteString))
     , Store.KeyArgs (IVM.IntervalMap k v) ~ ( a
                                             , b
                                             , BSC.ByteString
                                             , Proxy HCE.ExpressionInfoMap)
     )
  => a
  -> b
  -> IVM.IntervalMap k v
  -> StateT Store.State IO ()
addExpressionInfo packageId modulePath ivMap = do
  let (index, ivMaps) = splitIntervalMap ivMap
  Store.add
    index
    ( packageId
    , modulePath
    , Proxy :: Proxy (IVM.IntervalMap (Int, Int) BS.ByteString))
  mapM_
    (\(topLevelExprKey, ivMap') ->
       Store.add
         ivMap'
         ( packageId
         , modulePath
         , topLevelExprKey
         , Proxy :: Proxy HCE.ExpressionInfoMap))
    ivMaps

addExternalIdInfo ::
     HCE.PackageId
  -> HCE.PackageInfo HCE.CompactModuleInfo
  -> StateT Store.State IO ()
addExternalIdInfo packageId packageInfo = do
  let addTrieValues ::
           HCE.Trie Char HCE.ExternalIdentifierInfo
        -> String
        -> StateT Store.State IO ()
      addTrieValues trie name =
        let len = L.length name
         in Store.add
              (let ids =
                     S.toAscList $
                     HCE.match
                       name
                       (trie :: HCE.Trie Char HCE.ExternalIdentifierInfo)
                   (exactMatches, rest) =
                     L.span
                       (\(HCE.ExternalIdentifierInfo HCE.IdentifierInfo {..}) ->
                          T.length demangledOccName == len)
                       ids
                   maxIds = 10
                   exactMatchesCount = L.length exactMatches
                in if exactMatchesCount >= maxIds
                     then exactMatches
                     else exactMatches ++
                          L.take (maxIds - exactMatchesCount) rest)
              (packageId, name, Proxy :: Proxy [HCE.ExternalIdentifierInfo])
  let fullTrie = HCE.externalIdInfoMap packageInfo
  mapM_
    (\(firstLetter, trie) -> do
       mapM_
         (\(secondLetter, trie') -> do
            mapM_
              (\(thirdLetter, trie'') -> do
                 mapM_
                   (\(fourthLetter, trie''') ->
                      Store.add
                        trie'''
                        ( packageId
                        , [firstLetter, secondLetter, thirdLetter, fourthLetter]
                        , Proxy :: Proxy (HCE.Trie Char HCE.ExternalIdentifierInfo)))
                   (HM.toList . HCE.children $ trie'')
                 addTrieValues fullTrie [firstLetter, secondLetter, thirdLetter])
              (HM.toList . HCE.children $ trie')
            addTrieValues fullTrie [firstLetter, secondLetter])
         (HM.toList . HCE.children $ trie)
       addTrieValues fullTrie [firstLetter])
    (HM.toList . HCE.children $ fullTrie)

findDirectories :: PackagesPath -> IO [FilePath]
findDirectories p =
  case p of
    DirectoryWithPackages dir ->
      find (depth ==? 0) (fileType ==? Directory &&? filePath /=? dir) dir
    Directories dirs -> return dirs

loadPackages ::
     ServerConfig
  -> Maybe Store.Store
  -> IO (Maybe ( PackageMap
               , PackagePathMap
               , [PackageVersions]
               , GlobalReferenceMap
               , GlobalIdentifierMap))
loadPackages _config mbStore
  | (Just store) <- mbStore = do
    let eitherPackagePathMap =
          Store.lookup (Proxy :: Proxy PackagePathMap) store
        eitherGlobalReferenceMap =
          Store.lookup (Proxy :: Proxy GlobalReferenceMap) store
        eitherGlobalIdentifierMap =
          getGlobalIdentifierMap <$>
          Store.lookup (Proxy :: Proxy GlobalIdentifierMapWrapper) store
        eitherPackageVersions =
          Store.lookup (Proxy :: Proxy [PackageVersions]) store
        eitherPackageMap =
          Store.lookup
            (Proxy :: Proxy (HM.HashMap PackageName (M.Map Version HCE.PackageId)))
            store
    case (,,,,) <$> (PackageMapStore store <$> eitherPackageMap) <*>
         eitherPackagePathMap <*>
         eitherPackageVersions <*>
         eitherGlobalReferenceMap <*>
         eitherGlobalIdentifierMap of
      Right res -> return $ Just res
      Left _ -> do        
        putStrLn "Store lookup errors : "
        let ignoreRight :: Either a b -> Either a ()
            ignoreRight = second (const ())
        print $
          lefts
            [ ignoreRight eitherGlobalReferenceMap
            , ignoreRight eitherPackageMap
            , ignoreRight eitherPackageVersions
            , ignoreRight eitherGlobalIdentifierMap
            ]
        return Nothing 
loadPackages config _ = do
  packageDirectories <- findDirectories (configPackagesPath config)
  result <- mapM (loadPackageInfo config) packageDirectories
  let loadedPackages = rights result
      packageLoadErrors = lefts result
      packageInfos = map fst loadedPackages
      packageIds =
        map (HCE.id :: HCE.PackageInfo modInfo -> HCE.PackageId) packageInfos
  unless (null packageInfos) $ do
    putStrLn "Loaded packages : "
    mapM_ (print . HCE.packageIdToText) packageIds
  unless (null packageLoadErrors) $ do
    putStrLn "Package loading errors : "
    mapM_ (\(err, path) -> putStrLn $ path ++ " : " ++ err) packageLoadErrors
  if not . null $ loadedPackages
    then do
      let packageVersions =
            L.sortOn (T.toLower . (name :: PackageVersions -> T.Text)) .
            map
              (\(name, versions) ->
                 PackageVersions name (L.sortOn Down versions)) .
            HM.toList .
            HM.fromListWith (++) .
            map (\HCE.PackageId {..} -> (name, [version])) $
            packageIds
          packageMap =
            PackageMap $
            L.foldl'
              (\hMap packageInfo ->
                 let val = M.singleton (packageVersion packageInfo) packageInfo
                  in HM.insertWith M.union (packageName packageInfo) val hMap)
              HM.empty
              packageInfos
          packagePathMap =
            L.foldl'
              (\hMap (packageInfo, path) ->
                 let key =
                       PackageId $
                       HCE.packageIdToText
                         (HCE.id
                            (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo))
                  in HM.insert key path hMap)
              HM.empty
              loadedPackages
          globalReferenceMap =
            L.foldl'
              (\hMap (packageInfo, _path) ->
                 let references =
                       HM.map
                         (\spans ->
                            S.singleton
                              (GlobalReferences
                                 (S.size spans)
                                 (HCE.packageIdToText packageId))) .
                       HCE.externalIdOccMap $
                       packageInfo
                     packageId =
                       HCE.id
                         (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)
                  in HM.unionWith S.union references hMap)
              HM.empty
              loadedPackages
          globalIdentifierMap =
            L.foldl'
              (\trie (packageInfo, _path) ->
                 let exportedIds :: [HCE.ExternalIdentifierInfo]
                     exportedIds =
                       filter isExportedId $
                       trieValues $ HCE.externalIdInfoMap packageInfo
                  in L.foldl
                       (\trie' exportedId@(HCE.ExternalIdentifierInfo (HCE.IdentifierInfo {HCE.demangledOccName = name})) ->
                          HCE.insertToTrie
                            S.insert
                            (T.unpack name)
                            exportedId
                            trie')
                       trie
                       exportedIds)
              HCE.emptyTrie
              loadedPackages
      packageMapCompacted <- ghcCompact packageMap
      packagePathMapCompacted <- ghcCompact packagePathMap
      packageVersionsCompacted <- ghcCompact packageVersions
      globalReferenceMapCompacted <- ghcCompact globalReferenceMap
      globalIdentifierMapCompacted <- ghcCompact globalIdentifierMap
      return . Just $
        ( packageMapCompacted
        , packagePathMapCompacted
        , packageVersionsCompacted
        , globalReferenceMapCompacted
        , globalIdentifierMapCompacted  
        )
    else return Nothing
  where
    packageName :: HCE.PackageInfo HCE.CompactModuleInfo -> PackageName
    packageName =
      PackageName .
      (HCE.name :: HCE.PackageId -> T.Text) .
      (HCE.id :: HCE.PackageInfo modInfo -> HCE.PackageId)
    packageVersion :: HCE.PackageInfo HCE.CompactModuleInfo -> Version
    packageVersion =
      HCE.version . (HCE.id :: HCE.PackageInfo modInfo -> HCE.PackageId)

trieValues :: HCE.Trie k v -> [v]
trieValues (HCE.Trie values children) =
  S.toList values ++ concatMap trieValues (HM.elems children)

isExportedId :: HCE.ExternalIdentifierInfo -> Bool
isExportedId (HCE.ExternalIdentifierInfo HCE.IdentifierInfo {isExported}) =
  isExported

ghcCompact :: forall a. a -> IO a
ghcCompact =
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
  (fmap C.getCompact . C.compact)
#else
  return
#endif

loadPackageInfo ::
     ServerConfig
  -> String
  -> IO (Either (String, FilePath) ( HCE.PackageInfo HCE.CompactModuleInfo
                                   , FilePath))
loadPackageInfo config path =
  handleSync (\e -> return $ Left (show e, path)) $ do
    let indexDirectory =
          fromMaybe
            HCE.defaultOutputDirectoryName
            (configIndexDirectoryName config)
    binaryContent <-
      BS.readFile (path </> indexDirectory </> HCE.packageInfoBinaryFileName)
    let eitherPackageInfo = Serialize.decode binaryContent
        enableExpressionInfo = configEnableExpressionInfo config
    case eitherPackageInfo of
      Right packageInfo ->
        return . Right $
        ( updateEachModuleInfo
            packageInfo
            (\modInfo ->
               if not enableExpressionInfo
                 then modInfo {HCE.exprInfoMap = IVM.empty}
                 else modInfo)
        , path)
      Left e -> return . Left $ (e, path)

updateEachModuleInfo ::
     HCE.PackageInfo HCE.CompactModuleInfo
  -> (HCE.CompactModuleInfo -> HCE.CompactModuleInfo)
  -> HCE.PackageInfo HCE.CompactModuleInfo
updateEachModuleInfo packageInfo update =
  packageInfo {HCE.moduleMap = HM.map update $ HCE.moduleMap packageInfo}

handleSync :: (SomeException -> IO a) -> IO a -> IO a
handleSync onError =
  handle
    (\ex ->
       case fromException ex of
         Just (asyncEx :: SomeAsyncException) -> throwIO asyncEx
         _ -> onError ex)

--------------------------------------------------------------------------------
-- Servant API
--------------------------------------------------------------------------------

type API = GetAllPackages
  :<|> GetDefinitionSite
  :<|> GetExpressions
  :<|> GetReferences
  :<|> GetIdentifiers
  :<|> GetGlobalReferences
  :<|> GetGlobalIdentifiers
  :<|> GetHoogleDocs 

type GetAllPackages = "api" :> "packages" :> Get '[JSON] AllPackages

type GetDefinitionSite = "api" :> "definitionSite"
  :> Capture "packageId" PackageId
  :> Capture "componentId" HCE.ComponentId
  :> Capture "moduleName" HCE.HaskellModuleName
  :> Capture "entity" HCE.LocatableEntity
  :> Capture "name" T.Text
  :> Get '[JSON] HCE.DefinitionSite

type GetExpressions = "api" :> "expressions"
  :> Capture "packageId" PackageId
  :> Capture "modulePath" HCE.HaskellModulePath
  :> Capture "lineStart" Int
  :> Capture "columnStart" Int
  :> Capture "lineEnd" Int
  :> Capture "columnEnd" Int
  :> Get '[JSON] [Expression]

type GetReferences = "api" :> "references"
  :> Capture "packageId" PackageId
  :> Capture "externalId" HCE.ExternalId
  :> QueryParam "page" Int
  :> QueryParam "per_page" Int
  :> Get '[JSON] (Headers '[Header "Link" T.Text,Header "X-Total-Count" Int]
                 [SourceFile])

type GetIdentifiers = "api" :> "identifiers"
  :> Capture "packageId" PackageId
  :> Capture "query" T.Text
  :> QueryParam "page" Int
  :> QueryParam "per_page" Int
  :> Get '[JSON] (Headers '[Header "Link" T.Text,Header "X-Total-Count" Int]
                 [HCE.ExternalIdentifierInfo])

type GetGlobalReferences = "api" :> "globalReferences"
  :> Capture "externalId" HCE.ExternalId  
  :> Get '[JSON] [GlobalReferences]

type GetGlobalIdentifiers = "api" :> "globalIdentifiers"
  :> Capture "query" T.Text
  :> QueryParam "page" Int
  :> QueryParam "per_page" Int
  :> Get '[JSON] (Headers '[Header "Link" T.Text,Header "X-Total-Count" Int]
                 [HCE.ExternalIdentifierInfo])

type GetHoogleDocs = "api" :> "hoogleDocs"
  :> Capture "packageId" PackageId
  :> Capture "moduleName" HCE.HaskellModuleName
  :> Capture "entity" HoogleItemSort
  :> Capture "name" T.Text
  :> Get '[JSON] T.Text  

instance AllCTRender '[ JSON] AllPackages where
  handleAcceptH _ _ (AllPackages bytestring) =
    Just ("application/json", bytestring)

instance FromHttpApiData HCE.LocatableEntity where
  parseQueryParam "Val" = Right HCE.Val
  parseQueryParam "Typ" = Right HCE.Typ
  parseQueryParam "Inst" = Right HCE.Inst
  parseQueryParam "Mod" = Right HCE.Mod
  parseQueryParam val = Left $ T.append "Incorrect LocatableEntity : " val

instance FromHttpApiData HoogleItemSort where
  parseQueryParam "Val" = Right Val
  parseQueryParam "Typ" = Right Typ
  parseQueryParam val = Left $ T.append "Incorrect HoogleItemSort : " val

instance ToHttpApiData HCE.LocatableEntity where
  toUrlPiece HCE.Val = "ValueEntity"
  toUrlPiece HCE.Typ = "TypeEntity"
  toUrlPiece HCE.Inst = "InstanceEntity"
  toUrlPiece HCE.Mod = "ModuleEntity"

instance ToHttpApiData HCE.ExternalId where
  toUrlPiece (HCE.ExternalId i) = i
  
instance ToHttpApiData PackageId where
  toUrlPiece (PackageId p) = p
  
instance FromHttpApiData HCE.HaskellModulePath where
  parseQueryParam = Right . HCE.HaskellModulePath

instance FromHttpApiData HCE.ComponentId where
  parseQueryParam = Right . HCE.ComponentId

instance FromHttpApiData HCE.HaskellModuleName where
  parseQueryParam = Right . HCE.HaskellModuleName

instance FromHttpApiData HCE.ExternalId where
  parseQueryParam = Right . HCE.ExternalId
  
instance FromHttpApiData PackageId where
  parseQueryParam = Right . PackageId
  
--------------------------------------------------------------------------------
-- Request handlers
--------------------------------------------------------------------------------

data Environment = Environment
  { envLogger :: !LoggerSet
  , envPackageMap :: !PackageMap
  , envPackageVersions :: !AllPackages
  , envGlobalReferenceMap :: !GlobalReferenceMap
  , envGlobalIdentifierMap :: !GlobalIdentifierMap
  , envConfig :: !ServerConfig
  }

data Expression = Expression
  { srcSpan :: !(IVM.Interval (Int, Int))
  , info :: !HCE.ExpressionInfo
  } deriving (Show, Eq, Generic)

instance A.ToJSON Expression

data ReferenceWithSource = ReferenceWithSource
  { sourceCodeHtml :: !T.Text
  , idSrcSpan :: !HCE.IdentifierSrcSpan
  } deriving (Show, Eq, Generic)

data SourceFile = SourceFile
  { name :: !T.Text
  , references :: ![ReferenceWithSource]
  } deriving (Show, Eq, Generic)

instance A.ToJSON ReferenceWithSource
instance A.ToJSON SourceFile

getAllPackages :: ReaderT Environment IO AllPackages
getAllPackages = asks envPackageVersions
    
getExpressions ::
     PackageId
  -> HCE.HaskellModulePath
  -> Int -- ^ Start line
  -> Int -- ^ Start column
  -> Int -- ^ End line
  -> Int -- ^ End column
  -> ReaderT Environment IO [Expression]
getExpressions packageId modulePath startLine startColumn endLine endColumn = do
  enableExpressionInfo <- asks (configEnableExpressionInfo . envConfig)
  if not enableExpressionInfo
    then error404 "Expression queries are disabled"
    else withPackageInfo packageId $ \packageInfo' -> do
           maxPerPage <- asks (configMaxPerPage . envConfig)
           let requestedInterval =
                 IVM.ClosedInterval
                   (startLine, startColumn)
                   (endLine, endColumn)
               findInterval ::
                    HCE.ExpressionInfoMap -> ReaderT Environment IO [Expression]
               findInterval exprInfoMap =
                 return .
                 map (uncurry Expression) .
                 L.take maxPerPage . IVM.toList . IVM.within exprInfoMap $
                 requestedInterval
            in case packageInfo' of
                 PackageInfo packageInfo ->
                   withModuleInfo packageInfo modulePath $ \modInfo -> do
                     let exprInfoMap =
                           HCE.exprInfoMap (modInfo :: HCE.CompactModuleInfo)
                     findInterval exprInfoMap
                 PackageInfoStore pId store -> do
                   let topLevelExprKey =
                         ( pId
                         , modulePath
                         , Proxy :: Proxy (IVM.IntervalMap (Int, Int) BS.ByteString))
                       eitherTopLevelExprMap =
                         Store.lookup topLevelExprKey store
                   case eitherTopLevelExprMap of
                     Right topLevelExprMap ->
                       case map snd . IVM.toList $
                            IVM.intersecting topLevelExprMap requestedInterval of
                         exprKey:_ -> do
                           let key =
                                 ( pId
                                 , modulePath
                                 , exprKey
                                 , Proxy :: Proxy HCE.ExpressionInfoMap)
                               eitherExprMap = Store.lookup key store
                           case eitherExprMap of
                             Right exprMap -> findInterval exprMap
                             Left e -> error500 $ BSL.fromStrict $ BSC.pack e
                         _ -> return []
                     Left e -> error500 $ BSL.fromStrict $ BSC.pack e

getDefinitionSite ::
     PackageId
  -> HCE.ComponentId
  -> HCE.HaskellModuleName
  -> HCE.LocatableEntity
  -> T.Text
  -> ReaderT Environment IO HCE.DefinitionSite
getDefinitionSite packageId componentId modName entity name' =
  withPackageInfo packageId $ \packageInfo' ->
    withModulePath packageInfo' componentId modName $ \modPath ->
      let findDefSite ::
               HCE.PackageId
            -> HCE.DefinitionSiteMap
            -> ReaderT Environment IO HCE.DefinitionSite
          findDefSite pId defSiteMap =
            case entity of
              HCE.Mod ->
                return $
                HCE.DefinitionSite
                  (HCE.ExactLocation pId modPath modName 1 1 1 1)
                  Nothing
              _ -> do
                let mbDefinitionSite =
                      let name = fixDots name'
                      in case entity of
                        HCE.Typ ->
                          HM.lookup (HCE.OccName name) $
                          HCE.types (defSiteMap :: HCE.DefinitionSiteMap)
                        HCE.Val ->
                          HM.lookup (HCE.OccName name) $
                          HCE.values (defSiteMap :: HCE.DefinitionSiteMap)
                        HCE.Inst ->
                          HM.lookup name $
                          HCE.instances (defSiteMap :: HCE.DefinitionSiteMap)
                        _ -> Nothing
                case mbDefinitionSite of
                  Just definitionSite -> return definitionSite
                  Nothing ->
                    error404 $
                    BSL.concat
                      [ toLazyBS . T.pack $ show entity
                      , " "
                      , toLazyBS name'
                      , " "
                      , " not found in module "
                      , toLazyBS $ HCE.getHaskellModulePath modPath
                      ]
       in case packageInfo' of
            PackageInfo packageInfo ->
              let pId =
                    HCE.id
                      (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)
               in case HM.lookup
                         modPath
                         (HCE.moduleMap
                            (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)) of
                    Just HCE.CompactModuleInfo {definitionSiteMap = defSiteMap} ->
                      findDefSite pId defSiteMap
                    Nothing ->
                      error404 $
                      BSL.concat
                        [ "Module "
                        , toLazyBS $ HCE.getHaskellModulePath modPath
                        , " is not found in package "
                        , toLazyBS $ HCE.packageIdToText pId
                        ]
            PackageInfoStore pId store -> do
              let eitherDefinitionSiteMap =
                    Store.lookup
                      (pId, modPath, Proxy :: Proxy HCE.DefinitionSiteMap)
                      store
              case eitherDefinitionSiteMap of
                Right definitionSiteMap -> findDefSite pId definitionSiteMap
                Left e -> error500 (BSL.fromStrict $ BSC.pack e)

-- | "." and ".." is a special case because of the Path Segment Normalization:
-- https://tools.ietf.org/html/rfc3986#section-6.2.2.3
-- The segments “..” and “.” can be removed from a URL by a browser.
-- https://stackoverflow.com/questions/3856693/a-url-resource-that-is-a-dot-2e
fixDots :: T.Text -> T.Text
fixDots " ." = "."
fixDots " .." = ".."
fixDots t = t

buildLinkHeader :: T.Text -> Paginated a -> Natural -> Natural -> T.Text
buildLinkHeader url paginated currentPage perPage =
  T.intercalate
    ","
    (let addFirst
           | currentPage /= 1 =
             (:) (link (T.append url $ params 1 perPage) "first")
           | otherwise = id
         addLast
           | currentPage /= paginatedPagesTotal paginated =
             (:)
               (link
                  (T.append url $ params (paginatedPagesTotal paginated) perPage)
                  "last")
           | otherwise = id
         addNext
           | hasNextPage paginated =
             (:) (link (T.append url $ params (currentPage + 1) perPage) "next")
           | otherwise = id
         addPrev
           | hasPrevPage paginated =
             (:) (link (T.append url $ params (currentPage - 1) perPage) "prev")
           | otherwise = id
      in addFirst . addLast . addNext . addPrev $ [])
  where
    link :: T.Text -> T.Text -> T.Text
    link u rel = T.concat ["<", u, ">; rel=\"", rel, "\""]
    params :: Natural -> Natural -> T.Text
    params p pp =
      T.concat ["?page=", T.pack . show $ p, "&per_page=", T.pack . show $ pp]

initializePagination ::
     (MonadReader Environment m)
  => Maybe Int
  -> Maybe Int
  -> m (Natural, Natural)
initializePagination mbPage mbPerPage = do
  maxPerPage <- asks (configMaxPerPage . envConfig)
  let page =
        case mbPage of
          Just p ->
            if p > 0
              then p
              else 1
          Nothing -> 1
      perPage =
        case mbPerPage of
          Just pp ->
            if pp <= maxPerPage && pp > 0
              then pp
              else maxPerPage
          Nothing -> maxPerPage
  return (fromIntegral page, fromIntegral perPage)

getGlobalReferences ::
     HCE.ExternalId -> ReaderT Environment IO [GlobalReferences]
getGlobalReferences externalId = do
  refMap <- asks envGlobalReferenceMap
  return $ maybe [] S.toDescList (HM.lookup externalId refMap)  

getReferences ::
     PackageId
  -> HCE.ExternalId
  -> Maybe Int -- ^ Page number
  -> Maybe Int -- ^ Items per page
  -> ReaderT Environment IO (Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] [SourceFile])
getReferences packageId externalId mbPage mbPerPage =
  withPackageInfo packageId $ \packageInfo' ->
    let mkRefsWithSource ::
             Maybe [HCE.IdentifierSrcSpan]
          -> ReaderT Environment IO (Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] [SourceFile])
        mkRefsWithSource mbReferences =
          case mbReferences of
            Just references -> do
              (paginatedReferences, page, perPage, totalCount) <-
                paginateItems mbPage mbPerPage references
              let url =
                    T.append "/" $
                    toUrlPiece $
                    safeLink
                      (Proxy :: Proxy API)
                      (Proxy :: Proxy GetReferences)
                      packageId
                      externalId
                      Nothing
                      Nothing
                  linkHeader =
                    buildLinkHeader url paginatedReferences page perPage
                  addHeaders ::
                       forall a.
                       a
                    -> Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] a
                  addHeaders = addHeader linkHeader . addHeader totalCount
                  refModulePath :: ReferenceWithSource -> HCE.HaskellModulePath
                  refModulePath =
                    (HCE.modulePath :: HCE.IdentifierSrcSpan -> HCE.HaskellModulePath) .
                    idSrcSpan
              return $
                addHeaders $
                concatMap
                  (\refs ->
                     case refs of
                       ref:_ ->
                         let path =
                               HCE.getHaskellModulePath .
                               (HCE.modulePath :: HCE.IdentifierSrcSpan -> HCE.HaskellModulePath) .
                               idSrcSpan $
                               ref
                          in [SourceFile path refs]
                       _ -> []) $
                groupWith refModulePath $
                mapMaybe
                  (mkReferenceWithSource packageInfo')
                  (L.groupBy (\span1 span2 -> HCE.line span1 == HCE.line span2) $
                   paginatedItems paginatedReferences)
            Nothing ->
              error404 $
              BSL.concat
                [ "Cannot find references to "
                , toLazyBS $ HCE.getExternalId externalId
                ]
     in case packageInfo' of
          PackageInfo packageInfo ->
            mkRefsWithSource $ S.toList <$> HM.lookup externalId (HCE.externalIdOccMap packageInfo)            
          PackageInfoStore pId store -> do
            let eitherOccurrences =
                  Store.lookup
                    ( pId
                    , externalId
                    , Proxy :: Proxy (S.Set HCE.IdentifierSrcSpan))
                    store
            case eitherOccurrences of
              Right occurrences ->
                mkRefsWithSource (Just $ S.toList occurrences)
              Left e -> error500 $ BSL.fromStrict $ BSC.pack e

mkReferenceWithSource ::
     PackageInfo -> [HCE.IdentifierSrcSpan] -> Maybe ReferenceWithSource
mkReferenceWithSource packageInfo' spans@(srcSpan:_) =
  let mkRef :: Maybe (V.Vector T.Text) -> Maybe ReferenceWithSource
      mkRef mbSource =
        case mbSource of
          Just source ->
            let sourceCodeHtml =
                  buildHtmlCodeSnippet
                    source
                    (HCE.line (srcSpan :: HCE.IdentifierSrcSpan))
                    (map
                       (\HCE.IdentifierSrcSpan {..} -> (startColumn, endColumn))
                       spans)
             in Just $ ReferenceWithSource sourceCodeHtml srcSpan
          _ -> Just $ ReferenceWithSource "" srcSpan
   in case packageInfo' of
        PackageInfo packageInfo -> do
          let mbSource =
                (HCE.source :: HCE.CompactModuleInfo -> V.Vector T.Text) <$>
                HM.lookup
                  (HCE.modulePath (srcSpan :: HCE.IdentifierSrcSpan))
                  (HCE.moduleMap
                     (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo))
          mkRef mbSource
        PackageInfoStore packageId store -> do
          let eitherSourceCode =
                Store.lookup
                  ( packageId
                  , HCE.modulePath (srcSpan :: HCE.IdentifierSrcSpan)
                  , Proxy :: Proxy (V.Vector T.Text))
                  store
          case eitherSourceCode of
            Right source -> mkRef (Just source)
            Left _ -> mkRef Nothing
mkReferenceWithSource _ _ = Nothing

buildHtmlCodeSnippet :: V.Vector T.Text -> Int -> [(Int, Int)] -> T.Text
buildHtmlCodeSnippet sourceLines lineNumber positions =
  toStrict $
  renderHtml $ do
    mkLineNumber (lineNumber - 1) >>
      Html.toHtml
        (T.append (fromMaybe "" $ (V.!?) sourceLines (lineNumber - 2)) "\n")
    mkLineNumber lineNumber >>
      highlightIdentifiers
        (T.append (fromMaybe "" $ (V.!?) sourceLines (lineNumber - 1)) "\n")
    mkLineNumber (lineNumber + 1) >>
      Html.toHtml (T.append (fromMaybe "" $ (V.!?) sourceLines lineNumber) "\n")
  where
    mkLineNumber :: Int -> Html.Html
    mkLineNumber i = Html.toHtml (show i ++ "  ")
    highlightIdentifiers :: T.Text -> Html.Html
    highlightIdentifiers line =
      mapM_
        (\(text, _, mbId) ->
           case mbId of
             Just _ -> Html.b (Html.toHtml text)
             Nothing -> Html.toHtml text) $
      HCE.tokenize line (map (, ()) positions)

findIdentifiers ::
     PackageId
  -> T.Text
  -> Maybe Int
  -> Maybe Int
  -> ReaderT Environment IO (Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] [HCE.ExternalIdentifierInfo])
findIdentifiers packageId query' mbPage mbPerPage =  
  withPackageInfo packageId $ \packageInfo' ->
    let query = fixDots query'
        respond identifiers = do
          (paginatedIdentifiers, page, perPage, totalCount) <-
            paginateItems mbPage mbPerPage identifiers
          let url =
                T.append "/" $
                toUrlPiece $
                safeLink
                  (Proxy :: Proxy API)
                  (Proxy :: Proxy GetIdentifiers)
                  packageId
                  query'
                  Nothing
                  Nothing
              linkHeader = buildLinkHeader url paginatedIdentifiers page perPage
              addHeaders ::
                   forall a.
                   a
                -> Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] a
              addHeaders = addHeader linkHeader . addHeader totalCount
          return . addHeaders . paginatedItems $ paginatedIdentifiers
     in case packageInfo' of
          PackageInfo packageInfo -> do
            let identifiers
                  | not $ T.null query =
                    S.toList $
                    HCE.match
                      (T.unpack query)
                      (HCE.externalIdInfoMap packageInfo)
                  | otherwise = []
            respond identifiers
          PackageInfoStore pId store ->
            let findIds :: T.Text -> [HCE.ExternalIdentifierInfo]
                findIds q =
                  let eitherIdInfo =
                        Store.lookup
                          ( pId
                          , T.unpack q
                          , Proxy :: Proxy [HCE.ExternalIdentifierInfo])
                          store
                   in case eitherIdInfo of
                        Right ids -> ids
                        Left _ -> []
             in case T.length query of
                  0 -> respond []
                  1 -> respond $ findIds query
                  2 -> respond $ findIds query
                  3 -> respond $ findIds query
                  _ ->
                    let eitherIdInfoMap =
                          Store.lookup
                            ( pId
                            , T.unpack $ T.take 4 query
                            , Proxy :: Proxy (HCE.Trie Char HCE.ExternalIdentifierInfo))
                            store
                     in case eitherIdInfoMap of
                          Right trie ->
                            respond $
                            S.toList $
                            HCE.match (T.unpack $ T.drop 4 query) trie
                          Left _ -> respond []                          

findGlobalIdentifiers ::
     T.Text
  -> Maybe Int
  -> Maybe Int
  -> ReaderT Environment IO (Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] [HCE.ExternalIdentifierInfo])
findGlobalIdentifiers query' mbPage mbPerPage = do
  let query = fixDots query'
  globalIdentifierMap <- asks envGlobalIdentifierMap
  let maxItems = 500
  let identifiers
        | T.length query > 0 =
          L.take maxItems $
          S.toList $ HCE.match (T.unpack query) globalIdentifierMap
        | otherwise = []
  (paginatedIdentifiers, page, perPage, totalCount) <-
    paginateItems mbPage mbPerPage identifiers
  let url =
        T.append "/" $
        toUrlPiece $
        safeLink
          (Proxy :: Proxy API)
          (Proxy :: Proxy GetGlobalIdentifiers)
          query'
          Nothing
          Nothing
      linkHeader = buildLinkHeader url paginatedIdentifiers page perPage
      addHeaders ::
           forall a.
           a
        -> Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] a
      addHeaders = addHeader linkHeader . addHeader totalCount
  return . addHeaders . paginatedItems $ paginatedIdentifiers

data HoogleResultItem = HoogleResultItem
  { sort :: HoogleItemSort
  , moduleName :: T.Text
  , htmlDocs :: T.Text
  } deriving (Show, Eq)

data HoogleItemSort
  = Val
  | Typ
  deriving (Show, Eq)

valueToHoogleResultItem :: A.Value -> Maybe HoogleResultItem
valueToHoogleResultItem value =
  let mbHtmlDocs = value ^? AL.key "docs" . AL._String
      mbModuleName = value ^? AL.key "module" . AL.key "name" . AL._String
      urlToSort :: T.Text -> Maybe HoogleItemSort
      urlToSort url
        | T.isInfixOf "#v" url = Just Val
      urlToSort url
        | T.isInfixOf "#t" url = Just Typ
      urlToSort _ = Nothing
      mbResultSort = value ^? AL.key "url" . AL._String >>= urlToSort
   in HoogleResultItem <$> mbResultSort <*> mbModuleName <*> mbHtmlDocs      

hoogleApiHost :: String
hoogleApiHost = "https://hoogle.haskell.org/"

getHoogleDocs ::
     PackageId
  -> HCE.HaskellModuleName
  -> HoogleItemSort
  -> T.Text
  -> ReaderT Environment IO T.Text
getHoogleDocs packageId (HCE.HaskellModuleName moduleName) itemSort name
  | Just (packageName, _mbVersion) <- parsePackageId packageId = do
    useHoogle <- asks (configUseHoogleApi . envConfig)
    unless useHoogle $ error404 "Hoogle API is disabled"
    let hoogleQuery =
          T.unpack name ++
          " is:exact package:" ++ T.unpack (getPackageName packageName)
        url = hoogleApiHost ++ "?hoogle=" ++ encode hoogleQuery ++ "&mode=json"        
        error502 e =
          throwServantError $
          err502 {errBody = BSL.fromStrict $ BSC.pack $ show e}
    response <- liftIO $ handleSync error502 (Wreq.get url)
    let body = response ^. Wreq.responseBody
    case A.decode body of
      Just (value :: A.Value) ->
        case value of
          A.Array vector ->
            let items = mapMaybe valueToHoogleResultItem $ V.toList vector
                findItem :: Bool -> [HoogleResultItem] -> Maybe HoogleResultItem
                findItem exactModuleMatch =
                  L.find
                    (\HoogleResultItem {sort = s, moduleName = m} ->
                       s == itemSort && (exactModuleMatch || m == moduleName))
             in case findItem True items <|> findItem False items of
                  Just item -> return $ htmlDocs item
                  _ -> error404 ""
          _ ->
            error500 $
            BSL.append "Unexpected JSON response from hoogle.haskell.org" body
      Nothing ->
        error500 $
        BSL.append "Unexpected response from hoogle.haskell.org: " body
getHoogleDocs packageId _ _ _ =
  error404 $
  BSL.append "Incorrect package id: " (toLazyBS $ getPackageId packageId)

paginateItems ::
     Maybe Int
  -> Maybe Int
  -> [a]
  -> ReaderT Environment IO (Paginated a, Natural, Natural, Int)
paginateItems mbPage mbPerPage items = do
  (page, perPage) <- initializePagination mbPage mbPerPage
  let totalCount = L.length items
  pagination <- mkPagination perPage page
  paginated <-
    paginate
      pagination
      (fromIntegral totalCount)
      (\offset limit -> return . L.take limit . L.drop offset $ items)
  return (paginated, page, perPage, totalCount)
    
error404 :: BSL.ByteString -> ReaderT Environment IO a
error404 body = throwServantError $ err404 {errBody = body}

error500 :: BSL.ByteString -> ReaderT Environment IO a
error500 body = throwServantError $ err500 {errBody = body}

toLazyBS :: T.Text -> BSL.ByteString
toLazyBS = BSL.fromStrict . TE.encodeUtf8

data PackageInfo
  = PackageInfo (HCE.PackageInfo HCE.CompactModuleInfo)
  | PackageInfoStore HCE.PackageId
                     Store.Store
  
withPackageInfo ::
     PackageId
  -> (PackageInfo -> ReaderT Environment IO a)
  -> ReaderT Environment IO a
withPackageInfo packageId action
  | Just (packageName, mbVersion) <- parsePackageId packageId = do
    packageMap <- asks envPackageMap
    let findPackage ::
             (Hashable k, Eq k, Ord k1)
          => k
          -> Maybe k1
          -> HM.HashMap k (M.Map k1 v)
          -> Maybe v
        findPackage name mbVer pMap =
          HM.lookup name pMap >>=
          (\packages ->
             let findLastVersion :: M.Map k v -> Maybe v
                 findLastVersion = fmap (snd . fst) . L.uncons . M.toDescList
              in case mbVer of
                   Just version ->
                     M.lookup version packages <|> findLastVersion packages
                   Nothing -> findLastVersion packages)
        mbPackageInfo =
          case packageMap of
            PackageMap pMap ->
              PackageInfo <$> findPackage packageName mbVersion pMap
            PackageMapStore store pMap ->
              case findPackage packageName mbVersion pMap of
                Just pId -> Just $ PackageInfoStore pId store
                Nothing -> Nothing
    case mbPackageInfo of
      Just p -> action p
      Nothing -> packageNotFound packageId
withPackageInfo packageId _ = packageNotFound packageId

packageNotFound :: PackageId -> ReaderT Environment IO a
packageNotFound packageId =
  error404 $
  BSL.concat ["Package ", toLazyBS $ getPackageId packageId, " is not found."]

withModuleInfo ::
     HCE.PackageInfo HCE.CompactModuleInfo
  -> HCE.HaskellModulePath
  -> (HCE.CompactModuleInfo -> ReaderT Environment IO a)
  -> ReaderT Environment IO a
withModuleInfo packageInfo path action =
  case HM.lookup
         path
         (HCE.moduleMap (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)) of
    Just modInfo -> action modInfo
    Nothing ->
      error404 $
      BSL.concat
        [ "Module "
        , toLazyBS $ HCE.getHaskellModulePath path
        , " is not found in package "
        , toLazyBS $
          HCE.packageIdToText $
          HCE.id (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)
        ]

withModulePath ::
     PackageInfo
  -> HCE.ComponentId
  -> HCE.HaskellModuleName
  -> (HCE.HaskellModulePath -> ReaderT Environment IO a)
  -> ReaderT Environment IO a
withModulePath packageInfo' componentId moduleName action =
  case packageInfo' of
    PackageInfo packageInfo ->
      case HM.lookup
             (ghcPrimHack packageInfo' moduleName)
             (HCE.moduleNameMap packageInfo) of
        Just modulePathMap ->
          case HM.lookup componentId modulePathMap of
            Just modulePath -> action modulePath
            Nothing ->
              case HM.lookup (HCE.ComponentId "lib") modulePathMap of
                Just path -> action path
                Nothing -> notFoundInComponent
        Nothing -> notFoundInPackage (HCE.id (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo))
    PackageInfoStore packageId store -> do
      let eitherModNameMap =
              Store.lookup
                ( packageId
                , Proxy :: Proxy (HM.HashMap HCE.HaskellModuleName (HM.HashMap HCE.ComponentId HCE.HaskellModulePath)))
                store
      case eitherModNameMap of
          Right modNameMap ->
            case HM.lookup (ghcPrimHack packageInfo' moduleName) modNameMap of 
              Just componentMap -> case HM.lookup componentId componentMap of
                Just modulePath -> action modulePath
                Nothing -> case HM.lookup (HCE.ComponentId "lib") componentMap of
                  Just modulePath -> action modulePath
                  Nothing -> notFoundInComponent
              Nothing -> notFoundInPackage packageId
          Left e -> error500 (BSL.fromStrict $ BSC.pack e)
  where
    notFoundInComponent =
      error404 $
      BSL.concat
        [ "Module "
        , toLazyBS $ HCE.getHaskellModuleName moduleName
        , " is not found in component "
        , toLazyBS $ HCE.getComponentId componentId
        ]
    notFoundInPackage packageId =
      error404 $
      BSL.concat
        [ "Module "
        , toLazyBS $ HCE.getHaskellModuleName moduleName
        , " is not found in package "
        , toLazyBS $ HCE.packageIdToText packageId
        ]

-- | Workaround for :
-- https://github.com/ghc/ghc/blob/ghc-8.2.2-release/compiler/main/Finder.hs#L310-L315
ghcPrimHack :: PackageInfo -> HCE.HaskellModuleName -> HCE.HaskellModuleName
ghcPrimHack packageInfo' modName@(HCE.HaskellModuleName name) =
  case packageInfo' of
    PackageInfo packageInfo
      | HCE.packageName packageInfo == "ghc-prim" && name == "GHC.Prim" ->
        HCE.HaskellModuleName "GHC.Prim_"
      | otherwise -> modName
    PackageInfoStore (HCE.PackageId packageName _) _
      | packageName == "ghc-prim" && name == "GHC.Prim" ->
        HCE.HaskellModuleName "GHC.Prim_"
      | otherwise -> modName
  
parsePackageId :: PackageId -> Maybe (PackageName, Maybe Version)
parsePackageId (PackageId text) =
  case T.splitOn "-" text of
    [name] -> Just (PackageName name, Nothing)
    chunks@(_x:_xs) ->
      case mapM decimal . T.splitOn "." . last $ chunks of
        Right numbers ->
          Just
            ( PackageName $ T.intercalate "-" . init $ chunks
            , Just $ Version (map fst numbers) [])
        Left _ -> Just (PackageName text, Nothing)
    _ -> Nothing

staticMiddleware :: String -> PackagePathMap -> Maybe FilePath -> Middleware
staticMiddleware staticFilesPrefix packagePathMap _ app req callback
  | ("api":_) <- pathInfo req = app req callback
  | (prefix:packageId:rest) <- pathInfo req
  , prefix == T.pack staticFilesPrefix =
    case HM.lookup (PackageId packageId) packagePathMap of
      Just basePath
        | ".." `notElem` rest -> do
          let clientAcceptsEncoding =
                maybe
                  []
                  (map T.strip . T.splitOn "," . TE.decodeUtf8)
                  (lookup "Accept-Encoding" (requestHeaders req))
              clientAcceptsGzip = "gzip" `elem` clientAcceptsEncoding
              path = basePath </> T.unpack (T.intercalate "/" rest)
              gzPath = path ++ ".gz"
          sendGzipFile <-
            if clientAcceptsGzip
              then doesFileExist gzPath
              else return False
          if sendGzipFile
            then callback $
                 responseFile
                   status200
                   [ (hContentEncoding, "gzip")
                   , ( hContentType
                     , defaultMimeLookup . T.pack . takeFileName $ path)
                   ]
                   gzPath
                   Nothing
            else do
              exists <- doesFileExist path
              if exists
                then callback $ sendFile path
                else callback fileNotFound
      _ -> callback fileNotFound     
staticMiddleware _ _ mbJsDistPath _app req callback =
  case mbJsDistPath of
    Just jsDistPath -> do
      let path = jsDistPath </> T.unpack (T.intercalate "/" $ pathInfo req)
      exists <- doesFileExist path
      if exists
         then callback $ sendFile path
         else callback $ sendFile (jsDistPath </> "index.html")
    Nothing -> do
      let path = T.unpack $ T.intercalate "/" $ pathInfo req
      if path == ""
        then callback $ sendEmbeddedFile "index.html" indexHtml
        else case HM.lookup path staticAssets of
          Just bs -> callback $ sendEmbeddedFile path bs
          Nothing -> callback $ sendEmbeddedFile "index.html" indexHtml

staticAssets :: HM.HashMap FilePath BS.ByteString
staticAssets = HM.fromList $(embedDir "javascript/release")

indexHtml :: BS.ByteString
indexHtml = $(embedFile "javascript/release/index.html")

sendFile :: FilePath -> Response
sendFile path =
  responseFile
    status200
    [(hContentType, defaultMimeLookup $ T.pack $ takeFileName path)]
    path
    Nothing

sendEmbeddedFile :: FilePath -> BS.ByteString -> Response
sendEmbeddedFile path bs =
  responseLBS
    status200
    [(hContentType, defaultMimeLookup $ T.pack $ takeFileName path)]
    (BSL.fromStrict bs)    

fileNotFound :: Response
fileNotFound =
  responseLBS status404 [("Content-Type", "text/plain")] "Not found"

throwServantError :: (MonadIO m) => ServantErr -> m a
throwServantError = liftIO . throwIO 

server :: Environment -> ServerT API Handler
server env =
  hoistServer
    (Proxy :: Proxy API)
    toServantHandler
    (getAllPackages :<|>
     getDefinitionSite :<|>     
     getExpressions :<|>
     getReferences :<|>
     findIdentifiers :<|>
     getGlobalReferences :<|>
     findGlobalIdentifiers :<|>
     getHoogleDocs)
  where
    toServantHandler :: ReaderT Environment IO a -> Handler a
    toServantHandler ma = Handler . ExceptT . try . runReaderT ma $ env

application :: Environment -> Application
application env = serve (Proxy :: Proxy API) (server env)

main :: IO ()
main = do
  config <-
    execParser
      (Options.Applicative.info
         (configParser <**> helper)
         (fullDesc <>
          progDesc
            "haskell-code-server provides an HTTP API for Haskell Code Explorer"))
  print config
  mbStore <-
    let loadStore :: FilePath -> Store.ReadMode -> IO (Maybe Store.Store)
        loadStore path readOrMmap = do
          eitherStore <- Store.load path readOrMmap
          case eitherStore of
            Right store -> return $ Just store
            Left e -> putStrLn e >> exitFailure
     in case configStore config of
          Just (UseStore path) -> loadStore path Store.ReadEntireFile
          Just (UseStoreMmap path) -> loadStore path Store.MemoryMapFile
          Just (CreateStore path) -> do
            createStore path config
            exitSuccess
          Nothing -> return Nothing
  packages <- loadPackages config mbStore
  case packages of
    Just (packageMap, packagePathMap, packageVersions, globalReferenceMap, globalIdentifierMap) -> do
      loggerSet <-
        case configLog config of
          HCE.ToFile logfile -> newFileLoggerSet defaultBufSize logfile
          HCE.StdOut -> newStdoutLoggerSet defaultBufSize
      loggerMiddleware <-
        liftIO $
        mkRequestLogger
          def {outputFormat = Detailed True, destination = Logger loggerSet}      
      let staticFilePrefix = configStaticFilesUrlPrefix config
          mbJsDistPath = configJsDistDirectory config
          environment =
            Environment
              loggerSet
              packageMap
              (AllPackages . A.encode $ packageVersions)
              globalReferenceMap
              globalIdentifierMap
              config
          static =
            if configServeStaticFiles config
              then staticMiddleware staticFilePrefix packagePathMap mbJsDistPath
              else id
      run
        (configPort config)
        (loggerMiddleware . static $ application environment)
    Nothing -> putStrLn "No packages found."
