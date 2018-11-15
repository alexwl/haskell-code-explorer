{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
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
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Main where

import Control.Exception
  ( SomeAsyncException
  , SomeException
  , fromException
  , handle
  , throwIO
  , throwIO
  , try
  )
import Control.Monad (unless)
import Control.Monad.Except (ExceptT(..))
import Control.Monad.Reader (MonadIO, MonadReader, ReaderT(..), asks, liftIO)
import qualified Data.Aeson as A
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Data.Default (def)
import Data.Either (lefts, rights)
import qualified Data.HashMap.Strict as HM
import Data.Hashable (Hashable)
import qualified Data.IntervalMap.Strict as IVM
import qualified Data.List as L
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Vector as V
#if MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
import qualified GHC.Compact as C
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
import Network.HTTP.Types
  ( hContentEncoding
  , hContentType
  , status200
  , status404
  )
import Network.Mime (defaultMimeLookup)
import Network.Wai
  ( Application
  , Middleware
  , Response
  , pathInfo
  , responseFile
  , responseLBS
  , requestHeaders
  )
import Network.Wai.Handler.Warp (run)
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
  , some  
  , metavar
  , option
  , optional
  , progDesc
  , short
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
  , errBody
  , serve
  )
import Servant.API.ContentTypes (AllCTRender(..), JSON)
import Servant.Server (Handler(..), hoistServer)
import Servant.Utils.Links (safeLink)
import System.Directory (doesFileExist)
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
import System.FilePath.Posix ((</>),takeFileName)
import System.Log.FastLogger
  ( LoggerSet
  , defaultBufSize
  , newFileLoggerSet
  , newStdoutLoggerSet
  )
import Text.Blaze.Html.Renderer.Text (renderHtml)
import qualified Text.Blaze.Html5 as Html hiding (html, source)
import Data.FileEmbed (embedDir, embedFile)

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
  } deriving (Show, Eq)

data PackagesPath
  = DirectoryWithPackages FilePath
  | Directories [FilePath]
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
         help "Path to a Cabal package"))) <*>
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
      help "Maximum number of items per page (default is 50)"))

--------------------------------------------------------------------------------
-- Loading packages
--------------------------------------------------------------------------------

data PackageVersions = PackageVersions
  { name :: T.Text
  , versions :: [Version]
  } deriving (Show, Ord, Eq, Generic)

type PackageMap
   = HM.HashMap PackageName (M.Map Version (HCE.PackageInfo HCE.CompactModuleInfo))
     
type PackagePathMap = HM.HashMap PackageId FilePath

newtype AllPackages =
  AllPackages BSL.ByteString

newtype PackageId = PackageId
  { getPackageId :: T.Text
  } deriving (Show, Eq, Hashable)

newtype PackageName = PackageName
  { getPackageName :: T.Text
  } deriving (Show, Eq, Hashable)
  
instance A.ToJSON PackageVersions

type GlobalReferenceMap = HM.HashMap HCE.ExternalId (S.Set GlobalReferences)

data GlobalReferences = GlobalReferences
  { count :: Int
  , packageId :: HCE.PackageId
  } deriving (Show, Eq, Ord, Generic)

instance A.ToJSON GlobalReferences

loadPackages ::
     ServerConfig
  -> IO (Maybe (PackageMap, PackagePathMap, [PackageVersions], GlobalReferenceMap))
loadPackages config = do
  packageDirectories <-
    case configPackagesPath config of
      DirectoryWithPackages dir ->
        find (depth ==? 0) (fileType ==? Directory &&? filePath /=? dir) dir
      Directories dirs -> return dirs
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
          globalReferences =
            L.foldl'
              (\hMap (packageInfo, _path) ->
                 let references =
                       HM.map
                         (\spans ->
                            S.singleton
                              (GlobalReferences (S.size spans) packageId)) .
                       HCE.externalIdOccMap $
                       packageInfo
                     packageId =
                       HCE.id
                         (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)
                  in HM.unionWith S.union references hMap)
              HM.empty
              loadedPackages
      packageMapCompacted <- ghcCompact packageMap
      packagePathMapCompacted <- ghcCompact packagePathMap
      packageVersionsCompacted <- ghcCompact packageVersions
      globalReferencesCompacted <- ghcCompact globalReferences
      return . Just $
        ( packageMapCompacted
        , packagePathMapCompacted
        , packageVersionsCompacted
        , globalReferencesCompacted)
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

ghcCompact :: forall a. a -> IO  a
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
               let source =
                     HCE.source :: HCE.CompactModuleInfo -> V.Vector T.Text
                in if not enableExpressionInfo
                     then modInfo
                            { HCE.exprInfoMap = IVM.empty
                            , HCE.source = V.force $ source modInfo
                            -- 'force' fixes this error: Data.Vector.Mutable: uninitialised element CallStack (from HasCallStack): error, called at ./Data/Vector/Mutable.hs:188:17 in vector-0.12.0.1-GGZqQZyzchy8YFPCF67wxL:Data.Vector.Mutable
                            }
                     else modInfo {HCE.source = V.force $ source modInfo})
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
  :> Capture "name" HCE.ExternalId
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
  :> Capture "name" HCE.ExternalId :> Get '[JSON] [GlobalReferences]

instance AllCTRender '[ JSON] AllPackages where
  handleAcceptH _ _ (AllPackages bytestring) =
    Just ("application/json", bytestring)

instance FromHttpApiData HCE.LocatableEntity where
  parseQueryParam "Val" = Right HCE.Val
  parseQueryParam "Typ" = Right HCE.Typ
  parseQueryParam "Inst" = Right HCE.Inst
  parseQueryParam "Mod" = Right HCE.Mod
  parseQueryParam val = Left $ T.append "Incorrect LocatableEntity : " val

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

getPackageInfoAndModulePath ::
     PackageId
  -> HCE.ComponentId
  -> HCE.HaskellModuleName
  -> ReaderT Environment IO ( HCE.PackageInfo HCE.CompactModuleInfo
                            , HCE.HaskellModulePath)
getPackageInfoAndModulePath packageId componentId moduleName =
  withPackageInfo packageId $ \packageInfo ->
    case HM.lookup moduleName (HCE.moduleNameMap packageInfo) of
      Just modulePathMap ->
        case HM.lookup componentId modulePathMap of
          Just path -> return (packageInfo, path)
          Nothing ->
            error404 $
            BSL.concat
              [ "Module "
              , toLazyBS $ HCE.getHaskellModuleName moduleName
              , " not found in component "
              , toLazyBS $ HCE.getComponentId componentId
              ]
      Nothing ->
        error404 $
        BSL.concat
          [ "Module "
          , toLazyBS $ HCE.getHaskellModuleName moduleName
          , " not found in package "
          , toLazyBS $ getPackageId packageId
          ]

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
    else withPackageInfo packageId $ \packageInfo ->
           withModuleInfo packageInfo modulePath $ \modInfo -> do
             maxPerPage <- asks (configMaxPerPage . envConfig)
             let exprInfoMap =
                   HCE.exprInfoMap (modInfo :: HCE.CompactModuleInfo)
                 requestedInterval =
                   IVM.ClosedInterval
                     (startLine, startColumn)
                     (endLine, endColumn)
             return .
               map (uncurry Expression) .
               L.take maxPerPage . IVM.toList . IVM.within exprInfoMap $
               requestedInterval

getDefinitionSite ::
     PackageId
  -> HCE.ComponentId
  -> HCE.HaskellModuleName
  -> HCE.LocatableEntity
  -> T.Text
  -> ReaderT Environment IO HCE.DefinitionSite
getDefinitionSite packageId componentId modName entity name =
  withPackageInfo packageId $ \packageInfo ->
    withModulePath packageInfo componentId modName $ \modPath ->
      case entity of
        HCE.Mod ->
          return $
          HCE.DefinitionSite
            (HCE.ExactLocation
               (HCE.id (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo))
               modPath
               modName
               1
               1
               1
               1)
            Nothing
        _ ->
          withModuleInfo packageInfo modPath $ \modInfo -> do
            let defSites =
                  HCE.definitionSiteMap (modInfo :: HCE.CompactModuleInfo)
                mbDefinitionSite =
                  case entity of
                    HCE.Typ ->
                      HM.lookup (HCE.OccName name) $
                      HCE.types (defSites :: HCE.DefinitionSiteMap)
                    HCE.Val ->
                      HM.lookup (HCE.OccName name) $
                      HCE.values (defSites :: HCE.DefinitionSiteMap)
                    HCE.Inst ->
                      HM.lookup name $
                      HCE.instances (defSites :: HCE.DefinitionSiteMap)
                    _ -> Nothing
            case mbDefinitionSite of
              Just definitionSite -> return definitionSite
              Nothing ->
                error404 $
                BSL.concat
                  [ toLazyBS . T.pack $ show entity
                  , " "
                  , toLazyBS name
                  , " "
                  , " not found in a module "
                  , toLazyBS $ HCE.getHaskellModulePath modPath
                  ]
              
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

-- | Returns references in the current package
getReferences ::
     PackageId
  -> HCE.ExternalId
  -> Maybe Int -- ^ Page number
  -> Maybe Int -- ^ Items per page
  -> ReaderT Environment IO (Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] [SourceFile])
getReferences packageId externalId mbPage mbPerPage =
  withPackageInfo packageId $ \packageInfo ->
    case S.toList <$> HM.lookup externalId (HCE.externalIdOccMap packageInfo) of
      Just references -> do
        (page, perPage) <- initializePagination mbPage mbPerPage
        pagination <- mkPagination perPage page
        let totalCount = L.length references
        paginatedReferences <-
          paginate
            pagination
            (fromIntegral totalCount)
            (\offset limit -> return . L.take limit . L.drop offset $ references)
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
            linkHeader = buildLinkHeader url paginatedReferences page perPage
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
            (mkReferenceWithSource packageInfo)
            (L.groupBy (\span1 span2 -> HCE.line span1 == HCE.line span2) $
             paginatedItems paginatedReferences)
      Nothing ->
        error404 $
        BSL.concat
          [ "Cannot find references to "
          , toLazyBS $ HCE.getExternalId externalId
          ]

mkReferenceWithSource ::
     HCE.PackageInfo HCE.CompactModuleInfo
  -> [HCE.IdentifierSrcSpan]
  -> Maybe ReferenceWithSource
mkReferenceWithSource packageInfo spans@(span:_) =
  let mbModule =
        HM.lookup
          (HCE.modulePath (span :: HCE.IdentifierSrcSpan))
          (HCE.moduleMap (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo))
   in case mbModule of
        Just modInfo ->
          let sourceCodeHtml =
                buildHtmlCodeSnippet
                  (HCE.source (modInfo :: HCE.CompactModuleInfo))
                  (HCE.line (span :: HCE.IdentifierSrcSpan))
                  (map
                     (\HCE.IdentifierSrcSpan {..} -> (startColumn, endColumn))
                     spans)
           in Just $ ReferenceWithSource sourceCodeHtml span
        _ -> Just $ ReferenceWithSource "" span
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
  -> ReaderT Environment IO (Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int]
                                      [HCE.ExternalIdentifierInfo])
findIdentifiers packageId query mbPage mbPerPage =
  withPackageInfo packageId $ \packageInfo -> do
    let identifiers
          | not $ T.null query =
            S.toList $
            HCE.match (T.unpack query) (HCE.externalIdInfoMap packageInfo)
          | otherwise = []
    (page, perPage) <- initializePagination mbPage mbPerPage
    let totalCount = L.length identifiers
    pagination <- mkPagination perPage page
    paginatedIdentifiers <-
      paginate
        pagination
        (fromIntegral totalCount)
        (\offset limit -> return . L.take limit . L.drop offset $ identifiers)
    let url =
          T.append "/" $
          toUrlPiece $
          safeLink
            (Proxy :: Proxy API)
            (Proxy :: Proxy GetIdentifiers)
            packageId
            query
            Nothing
            Nothing
        linkHeader = buildLinkHeader url paginatedIdentifiers page perPage
        addHeaders ::
             forall a.
             a
          -> Headers '[ Header "Link" T.Text, Header "X-Total-Count" Int] a
        addHeaders = addHeader linkHeader . addHeader totalCount
    return . addHeaders . paginatedItems $ paginatedIdentifiers

error404 :: BSL.ByteString -> ReaderT Environment IO a
error404 body = throwServantError $ err404 {errBody = body}

toLazyBS :: T.Text -> BSL.ByteString
toLazyBS = BSL.fromStrict . TE.encodeUtf8
  
withPackageInfo ::
     PackageId
  -> (HCE.PackageInfo HCE.CompactModuleInfo -> ReaderT Environment IO a)
  -> ReaderT Environment IO a
withPackageInfo packageId action
  | Just (packageName, mbVersion) <- parsePackageId packageId = do
    packageMap <- asks envPackageMap
    let mbPackageInfo =
          HM.lookup packageName packageMap >>=
          (\packages ->
             let findLastVersion :: M.Map k v -> Maybe v
                 findLastVersion = fmap (snd . fst) . L.uncons . M.toDescList
              in case mbVersion of
                   Just version ->
                     M.lookup version packages <|> findLastVersion packages
                   Nothing -> findLastVersion packages)
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
     HCE.PackageInfo HCE.CompactModuleInfo
  -> HCE.ComponentId
  -> HCE.HaskellModuleName
  -> (HCE.HaskellModulePath -> ReaderT Environment IO a)
  -> ReaderT Environment IO a
withModulePath packageInfo componentId moduleName action =
  case HM.lookup
         (ghcPrimHack packageInfo moduleName)
         (HCE.moduleNameMap packageInfo) of
    Just modulePathMap ->
      case HM.lookup componentId modulePathMap of
        Just path -> action path
        Nothing ->
          case HM.lookup (HCE.ComponentId "lib") modulePathMap of
            Just path -> action path
            Nothing ->
              error404 $
              BSL.concat
                [ "Module "
                , toLazyBS $ HCE.getHaskellModuleName moduleName
                , " is not found in component "
                , toLazyBS $ HCE.getComponentId componentId
                ]
    Nothing ->
      error404 $
      BSL.concat
        [ "Module "
        , toLazyBS $ HCE.getHaskellModuleName moduleName
        , " is not found in package "
        , toLazyBS $
          HCE.packageIdToText $
          HCE.id (packageInfo :: HCE.PackageInfo HCE.CompactModuleInfo)
        ]

-- | Workaround for :
-- https://github.com/ghc/ghc/blob/ghc-8.2.2-release/compiler/main/Finder.hs#L310-L315
ghcPrimHack ::
     HCE.PackageInfo HCE.CompactModuleInfo
  -> HCE.HaskellModuleName
  -> HCE.HaskellModuleName
ghcPrimHack packageInfo (HCE.HaskellModuleName modName)
  | HCE.packageName packageInfo == "ghc-prim" && modName == "GHC.Prim" =
    HCE.HaskellModuleName "GHC.Prim_"
  | otherwise = HCE.HaskellModuleName modName
  
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
                fromMaybe [] $
                map T.strip . T.splitOn "," . TE.decodeUtf8 <$>
                lookup "Accept-Encoding" (requestHeaders req)
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
     getGlobalReferences)
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
            "haskell-code-server provides an HTTP API for Haskell code explorer"))
  print config
  packages <- loadPackages config
  case packages of
    Just (packageMap, packagePathMap, packageVersions,globalReferences) -> do
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
              globalReferences
              config
          static =
            if configServeStaticFiles config
              then staticMiddleware staticFilePrefix packagePathMap mbJsDistPath
              else id
      run
        (configPort config)
        (loggerMiddleware . static $ application environment)
    Nothing -> putStrLn "No packages found."
