{-# LANGUAGE CPP #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module HaskellCodeExplorer.PackageInfo
  ( createPackageInfo
  , ghcVersion
  ) where

import Control.DeepSeq(deepseq)
import Control.Exception
  ( IOException
  , SomeAsyncException
  , SomeException
  , fromException
  , throw
  , try
  )
import Control.Monad (foldM, join, unless)
import Control.Monad.Extra (anyM, findM)
import Control.Monad.Logger
  ( LoggingT(..)
  , MonadLogger(..)
  , MonadLoggerIO(..)
  , logDebugN
  , logErrorN
  , logInfoN
  )
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Foldable (toList)
import qualified Data.HashMap.Strict as HM
import Data.IORef (readIORef)
import qualified Data.IntMap.Strict as IM
import qualified Data.List as L
import qualified Data.List.NonEmpty as NE
import Data.Maybe (fromMaybe, isJust, maybeToList)
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Version (Version(..), showVersion, parseVersion, makeVersion)
import Text.ParserCombinators.ReadP (readP_to_S)
import Digraph (flattenSCCs)
import Distribution.Helper
  ( ChComponentName(..)
  , ChLibraryName(..)
  , ChEntrypoint(..)
  , ChModuleName(..)
  , ChComponentInfo(..)
  , UnitInfo(..)
  , ProjLoc(..)
  , DistDir(..)
  , compilerVersion
  , allUnits
  , mkQueryEnv
  , runQuery
  )
import DynFlags
  ( DynFlags(..)
  , GeneralFlag(..)
  , GhcMode(..)
  , WarnReason(..)
  , gopt_set
  , parseDynamicFlagsCmdLine
  )
import Exception (ExceptionMonad(..), ghandle)
import GHC
  ( GhcLink(..)
  , HscTarget(..)
  , LoadHowMuch(..)
  , ModLocation(..)
  , ModSummary(..)
  , Severity
  , SrcSpan
  , getModuleGraph
  , getSession
  , getSessionDynFlags
  , guessTarget
  , load
  , noLoc
  , parseModule
  , runGhcT
  , setSessionDynFlags
  , setTargets
  , topSortModuleGraph
  , typecheckModule
  , moduleNameString
  , moduleName  
  )
import GHC.Paths (libdir)
import GhcMonad (GhcT(..), liftIO)
import HaskellCodeExplorer.GhcUtils (isHsBoot,toText)
import HaskellCodeExplorer.ModuleInfo (ModuleDependencies, createModuleInfo)
import qualified HaskellCodeExplorer.Types as HCE
import HscTypes (hsc_EPS, hsc_HPT)
import Outputable (PprStyle, SDoc, neverQualify, showSDocForUser)
import Packages (initPackages)
import Prelude hiding (id)
import qualified Prelude
import System.Directory
  ( doesFileExist  
  , findExecutable
  , setCurrentDirectory
  , getCurrentDirectory
  , makeAbsolute
  )
import qualified System.Directory.Tree as DT
import System.Exit (exitFailure)
import System.FilePath
  ( (</>)
  , addTrailingPathSeparator
  , joinPath
  , normalise
  , replaceExtension
  , splitPath
  , takeExtension
  , takeBaseName
  , takeDirectory
  , splitDirectories  
  )
import System.FilePath.Find
import System.IO (IOMode(..), withFile)
import System.Process (readProcess)

createPackageInfo ::
     FilePath -- ^ Path to a Cabal package
  -> Maybe FilePath -- ^ Relative path to a dist directory
  -> HCE.SourceCodePreprocessing -- ^ Before or after preprocessor
  -> [String] -- ^ Options for GHC
  -> [String] -- ^ Directories to ignore
  -> LoggingT IO (HCE.PackageInfo HCE.ModuleInfo)
createPackageInfo packageDirectoryPath mbDistDirRelativePath sourceCodePreprocessing additionalGhcOptions ignoreDirectories = do
  packageDirectoryAbsPath <- liftIO $ makeAbsolute packageDirectoryPath
  currentDirectory <- liftIO getCurrentDirectory
  liftIO $ setCurrentDirectory packageDirectoryAbsPath
  distDir <-
    case mbDistDirRelativePath of
      Just path -> return $ packageDirectoryAbsPath </> path
      Nothing -> do
        eitherDistDir <- findDistDirectory packageDirectoryAbsPath
        case eitherDistDir of
          Right distDir -> return distDir
          Left errorMessage ->
            logErrorN (T.pack errorMessage) >> liftIO exitFailure
  eitherPackageGhcVersion <- liftIO $ getPackageGhcVersion distDir
  case eitherPackageGhcVersion of
    Right packageGhcVersion ->
      if take 2 (versionBranch packageGhcVersion) == take 2 (versionBranch ghcVersion)
        then return ()
        else let message =
                   "GHC version mismatch. haskell-code-indexer: " ++
                   showVersion ghcVersion ++
                   ", package: " ++
                   showVersion packageGhcVersion
              in logErrorN (T.pack message) >> liftIO exitFailure
    Left err -> logErrorN (T.pack err) >> liftIO exitFailure
  units <- liftIO $ flip runQuery cabalHelperQueryEnv $ allUnits Prelude.id
  let compInfo = concatMap (toList . uiComponents) units
  let (packageName, packageVersion) = uiPackageId (NE.head units)
      --  ^ in V1 projects there's only one package so this is sound but note
      --  this doesn't hold for Stack or V2
      currentPackageId = HCE.PackageId (T.pack packageName) packageVersion
  logInfoN $ T.append "Indexing " $ HCE.packageIdToText currentPackageId
  let buildComponents =
        L.map
          (\c -> let compName = ciComponentName c in
             ( chComponentNameToComponentId compName
             , ciGhcOptions c
             , chEntrypointsToModules (ciEntrypoints c)
             , ciSourceDirs c
             , chComponentNameToComponentType compName)) .
        L.sortBy
          (\c1 c2 -> compare (ciComponentName c1) (ciComponentName c2)) $
        toList compInfo
      libSrcDirs =
        concatMap (\(_, _, _, srcDirs, _) -> srcDirs) .
        filter (\(_, _, _, _, compType) -> HCE.isLibrary compType) $
        buildComponents
  (indexedModules, (_fileMapResult, _defSiteMapResult, modNameMapResult)) <-
    foldM
      (\(modules, (fileMap, defSiteMap, modNameMap)) (compId, options, (mbMain, moduleNames), srcDirs, _) -> do
         mbMainPath <-
           case mbMain of
             Just mainPath ->
               liftIO $
               findM doesFileExist $
               mainPath :
               map (\srcDir -> normalise $ srcDir </> mainPath) srcDirs
             Nothing -> return Nothing
         (modules', (fileMap', defSiteMap', modNameMap')) <-
           indexBuildComponent
             sourceCodePreprocessing
             currentPackageId
             compId
             (fileMap, defSiteMap, modNameMap)
             srcDirs
             libSrcDirs
             (options ++ additionalGhcOptions)
             (maybe moduleNames (: moduleNames) mbMainPath)
         return (modules ++ modules', (fileMap', defSiteMap', modNameMap')))
      ([], (HM.empty, HM.empty, HM.empty))
      buildComponents
  let modId = HCE.id :: HCE.ModuleInfo -> HCE.HaskellModulePath
      moduleMap =
        HM.fromList . map (\modInfo -> (modId modInfo, modInfo)) $
        indexedModules
      references = L.foldl' addReferencesFromModule HM.empty indexedModules
      moduleId = HCE.id :: HCE.ModuleInfo -> HCE.HaskellModulePath
      topLevelIdentifiersTrie =
        L.foldl' addTopLevelIdentifiersFromModule HCE.emptyTrie .
        L.filter (not . isHsBoot . moduleId) $
        indexedModules
  directoryTree <-
    liftIO $
    buildDirectoryTree
      packageDirectoryAbsPath
      ignoreDirectories
      (\path -> HM.member (HCE.HaskellModulePath . T.pack $ path) moduleMap)
  liftIO $ setCurrentDirectory currentDirectory
  return
    HCE.PackageInfo
      { id = currentPackageId
      , moduleMap = moduleMap
      , moduleNameMap = modNameMapResult
      , directoryTree = directoryTree
      , externalIdOccMap = references
      , externalIdInfoMap = topLevelIdentifiersTrie
      }
  where
    chEntrypointsToModules :: ChEntrypoint -> (Maybe String, [String])
    chEntrypointsToModules (ChLibEntrypoint modules otherModules signatures) =
      ( Nothing
      , L.map chModuleToString modules ++
        L.map chModuleToString otherModules ++ L.map chModuleToString signatures)
    chEntrypointsToModules (ChExeEntrypoint mainModule _otherModules) =
      (Just mainModule, [])
    chEntrypointsToModules ChSetupEntrypoint = (Nothing, [])
    chModuleToString :: ChModuleName -> String
    chModuleToString (ChModuleName n) = n
    chComponentNameToComponentType :: ChComponentName -> HCE.ComponentType
    chComponentNameToComponentType ChSetupHsName = HCE.Setup
    chComponentNameToComponentType (ChLibName ChMainLibName) = HCE.Lib
    chComponentNameToComponentType (ChLibName (ChSubLibName name)) =
      HCE.SubLib $ T.pack name
    chComponentNameToComponentType (ChFLibName name) = HCE.FLib $ T.pack name
    chComponentNameToComponentType (ChExeName name) = HCE.Exe $ T.pack name
    chComponentNameToComponentType (ChTestName name) = HCE.Test $ T.pack name
    chComponentNameToComponentType (ChBenchName name) = HCE.Bench $ T.pack name
    chComponentNameToComponentId :: ChComponentName -> HCE.ComponentId
    chComponentNameToComponentId (ChLibName ChMainLibName) = HCE.ComponentId "lib"
    chComponentNameToComponentId (ChLibName (ChSubLibName name)) =
      HCE.ComponentId . T.append "sublib-" . T.pack $ name
    chComponentNameToComponentId (ChFLibName name) =
      HCE.ComponentId . T.append "flib-" . T.pack $ name
    chComponentNameToComponentId (ChExeName name) =
      HCE.ComponentId . T.append "exe-" . T.pack $ name
    chComponentNameToComponentId (ChTestName name) =
      HCE.ComponentId . T.append "test-" . T.pack $ name
    chComponentNameToComponentId (ChBenchName name) =
      HCE.ComponentId . T.append "bench-" . T.pack $ name
    chComponentNameToComponentId ChSetupHsName = HCE.ComponentId "setup"

-- | Parses the header of setup-config file.
-- The header is generated by Cabal:
-- https://github.com/haskell/cabal/blob/5be57c0d251be40a6263cd996d99703b8de1ed79/Cabal/Distribution/Simple/Configure.hs#L286-L295
getPackageGhcVersion :: FilePath -> IO (Either String Version)
getPackageGhcVersion distDir =
  withFile (distDir </> "setup-config") ReadMode $ \handle -> do
    header <- BSC.hGetLine handle
    let parseHeader :: BSC.ByteString -> Maybe BSC.ByteString
        parseHeader hdr =
          case BSC.words hdr of
            ["Saved", "package", "config", "for", _package, "written", "by", _cabal, "using", compiler] ->
              Just compiler
            _ -> Nothing
        parseCompiler :: BSC.ByteString -> Maybe BSC.ByteString
        parseCompiler compiler =
          case BSC.split '-' compiler of
            ["ghc", version] -> Just version
            _ -> Nothing
        parseGhcVersion :: BSC.ByteString -> Maybe Version
        parseGhcVersion version =
          case filter ((== "") . snd) $
               readP_to_S parseVersion $ BSC.unpack version of
            [(ver, "")] -> Just ver
            _ -> Nothing
    case parseHeader header >>= parseCompiler >>= parseGhcVersion of
      Just version -> return $ Right version
      _ ->
        return $
        Left $
        "Unexpected setup-config header: \"" ++
        BSC.unpack header ++
        "\"\nIt may mean that the version of Cabal used to build this package is not supported by haskell-code-indexer yet."

#if MIN_VERSION_GLASGOW_HASKELL(8,6,4,0)
ghcVersion :: Version
ghcVersion = makeVersion [8, 6, 4, 0]
#elif MIN_VERSION_GLASGOW_HASKELL(8,6,3,0)
ghcVersion :: Version
ghcVersion = makeVersion [8, 6, 3, 0]
#elif MIN_VERSION_GLASGOW_HASKELL(8,4,4,0)
ghcVersion :: Version
ghcVersion = makeVersion [8, 4, 4, 0]
#elif MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)
ghcVersion :: Version
ghcVersion = makeVersion [8, 4, 3, 0]
#elif MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)
ghcVersion :: Version
ghcVersion = makeVersion [8, 2, 2, 0]
#else
ghcVersion :: Version
ghcVersion = makeVersion [8, 0, 2, 0]
#endif
buildDirectoryTree :: FilePath -> [FilePath] -> (FilePath -> Bool) -> IO HCE.DirTree
buildDirectoryTree path ignoreDirectories isHaskellModule = do
  (_dir DT.:/ tree) <- DT.readDirectoryWith (const . return $ ()) path
  -- Tuple up the complete file path with the file contents, by building up the path,
  -- trie-style, from the root. The filepath will be relative to "anchored" directory.
  let treeWithPaths = DT.zipPaths ("" DT.:/ DT.filterDir (not . ignore) tree)
  return $ toDirTree (removeTopDir . fst <$> treeWithPaths)
  where
    ignore :: DT.DirTree a -> Bool
    ignore (DT.Dir dirName _)
      | "." `L.isPrefixOf` dirName = True
      | dirName == "dist" = True
      | dirName == "dist-newstyle" = True
      | dirName == "tmp" = True
      | otherwise = dirName `elem` ignoreDirectories
    ignore (DT.Failed _ _) = True
    ignore _ = False
    removeTopDir :: FilePath -> FilePath
    removeTopDir p =
      case splitPath p of
        _x:xs -> joinPath xs
        [] -> ""
    toDirTree :: DT.DirTree FilePath -> HCE.DirTree
    toDirTree (DT.Dir name contents) =
      HCE.Dir name (map toDirTree . filter (not . DT.failed) $ contents)
    toDirTree (DT.File name filePath) =
      HCE.File name filePath (isHaskellModule filePath)
    toDirTree (DT.Failed name err) =
      HCE.File (name ++ " : " ++ show err) "" False
        
addTopLevelIdentifiersFromModule ::
     HCE.Trie Char HCE.ExternalIdentifierInfo
  -> HCE.ModuleInfo
  -> HCE.Trie Char HCE.ExternalIdentifierInfo
addTopLevelIdentifiersFromModule trieIdInfo HCE.ModuleInfo {..} =
  L.foldl'
    (\trie idInfo@(HCE.ExternalIdentifierInfo HCE.IdentifierInfo {..}) ->
       HCE.insertToTrie S.insert (T.unpack demangledOccName) idInfo trie)
    trieIdInfo
    externalIds
  
addReferencesFromModule ::     
     HM.HashMap HCE.ExternalId (S.Set HCE.IdentifierSrcSpan)
  -> HCE.ModuleInfo
  -> HM.HashMap HCE.ExternalId (S.Set HCE.IdentifierSrcSpan)
addReferencesFromModule references modInfo@HCE.ModuleInfo {..} =
  eachIdentifierOccurrence
    references
    modInfo
    (\occMap lineNumber startCol endCol occ ->
       let mbIdExternalId =
             join $
             HCE.externalId <$>
             maybe
               Nothing
               (`HM.lookup` idInfoMap)
               (HCE.internalId (occ :: HCE.IdentifierOccurrence))
           idSrcSpan =
             HCE.IdentifierSrcSpan
               { modulePath = id
               , line = lineNumber
               , startColumn = startCol
               , endColumn = endCol
               }
        in case mbIdExternalId of
             Just externalId ->
               HM.insertWith S.union externalId (S.singleton idSrcSpan) occMap
             Nothing -> occMap)

findDistDirectory :: FilePath -> LoggingT IO (Either String FilePath)
findDistDirectory packagePath = do
  let parents =
        reverse . map joinPath . filter (not . null) . L.inits . splitPath $
        packagePath
  -- e.g., ["/dir/subdir/subsubdir","/dir/subdir/","/dir/","/"]
  hasStackYaml <-
    liftIO $ anyM (\path -> doesFileExist (path </> "stack.yaml")) parents
  mbStackExecutable <- liftIO $ findExecutable "stack"
  case (hasStackYaml, mbStackExecutable) of
    (True, Just stack) -> do
      let removeEndOfLine str
            | null str = str
            | otherwise = init str
      logInfoN
        "Found stack.yaml. Executing \"stack path --dist-dir\" to get dist directory."
      eitherDistDir :: (Either IOException String) <-
        liftIO .
        try . fmap removeEndOfLine . readProcess stack ["path", "--dist-dir"] $
        ""
      case eitherDistDir of
        Right distDir -> do
          logInfoN $ T.append "Stack dist directory : " $ T.pack distDir
          hasSetupConfig <- liftIO $ doesFileExist $ distDir </> "setup-config"
          if hasSetupConfig
            then return $ Right distDir
            else return $
                 Left
                   "Cannot find setup-config file in a dist directory. Has the package been built?"
        Left exception ->
          return $
          Left $
          "Error while executing \"stack path --dist-dir\" : " ++ show exception
    _ -> do
      logInfoN "Trying to find dist directory"
      setupConfigPaths <-
        liftIO $
        map (takeDirectory . normalise) <$>
        find always (fileName ==? "setup-config") "."
      case setupConfigPaths of
        [] ->
          return $
          Left "Cannot find dist directory. Has the package been built?"
        [path] -> do
          logInfoN $ T.append "Found dist directory : " $ T.pack path
          return $ Right path
        _ ->
          return $
          Left $
          "Found multiple possible dist directories : \n" ++
          show setupConfigPaths ++ " \nPlease specify --dist option"
          
eachIdentifierOccurrence ::
     forall a.
     a
  -> HCE.ModuleInfo
  -> (a -> IM.Key -> Int -> Int -> HCE.IdentifierOccurrence -> a)
  -> a
eachIdentifierOccurrence accumulator HCE.ModuleInfo {..} f =
  IM.foldlWithKey'
    (\acc lineNumber occurences ->
       L.foldl'
         (\a ((startCol, endCol), occ) -> f a lineNumber startCol endCol occ)
         acc
         occurences)
    accumulator
    idOccMap

instance ExceptionMonad (LoggingT IO) where
  gcatch act h =
    LoggingT $ \logFn ->
      runLoggingT act logFn `gcatch` \e -> runLoggingT (h e) logFn
  gmask f =
    LoggingT $ \logFn ->
      gmask $ \io_restore ->
        let g_restore (LoggingT m) = LoggingT $ \lf -> io_restore (m lf)
         in runLoggingT (f g_restore) logFn

instance MonadLoggerIO (GhcT (LoggingT IO)) where
  askLoggerIO = GhcT $ const askLoggerIO

instance MonadLogger (GhcT (LoggingT IO)) where
  monadLoggerLog loc source level =
    GhcT . const . monadLoggerLog loc source level

gtrySync :: (ExceptionMonad m) => m a -> m (Either SomeException a)
gtrySync action = ghandleSync (return . Left) (fmap Right action)

ghandleSync :: (ExceptionMonad m) => (SomeException -> m a) -> m a -> m a
ghandleSync onError =
  ghandle
    (\ex ->
       case fromException ex of
         Just (asyncEx :: SomeAsyncException) -> throw asyncEx
         _ -> onError ex)
    
indexBuildComponent ::
     HCE.SourceCodePreprocessing -- ^ Before or after preprocessor
  -> HCE.PackageId -- ^ Current package id
  -> HCE.ComponentId -- ^ Current component id
  -> ModuleDependencies -- ^ Already indexed modules
  -> [FilePath] -- ^ Src dirs
  -> [FilePath] -- ^ Src dirs of libraries
  -> [String] -- ^ Command-line options for GHC
  -> [String] -- ^ Modules to compile
  -> LoggingT IO ([HCE.ModuleInfo],ModuleDependencies)
indexBuildComponent sourceCodePreprocessing currentPackageId componentId deps@(fileMap, defSiteMap, modNameMap) srcDirs libSrcDirs options modules = do
  let onError ex = do
        logErrorN $
          T.concat
            [ "Error while indexing component "
            , HCE.getComponentId componentId
            , " : "
            , T.pack . show $ ex
            ]
        return ([], deps)
  ghandleSync onError $
    runGhcT (Just libdir) $ do
      logDebugN (T.append "Component id : " $ HCE.getComponentId componentId)
      logDebugN (T.append "Modules : " $ T.pack $ show modules)
      logDebugN
        (T.append "GHC command line options : " $
         T.pack $ L.intercalate " " (options ++ modules))
      flags <- getSessionDynFlags
      (flags', _, _) <-
        parseDynamicFlagsCmdLine
          flags
          (L.map noLoc . L.filter ("-Werror" /=) $ options) -- -Werror flag makes warnings fatal
      (flags'', _) <- liftIO $ initPackages flags'
      logFn <- askLoggerIO
      let logAction ::
               DynFlags
            -> WarnReason
            -> Severity
            -> SrcSpan
            -> Outputable.PprStyle
            -> SDoc
            -> IO ()
          logAction fs _reason _severity srcSpan _stype msg =
            runLoggingT
              (logDebugN
                 (T.append "GHC message : " $
                  T.pack $
                  showSDocForUser fs neverQualify msg ++
                  " , SrcSpan : " ++ show srcSpan))
              logFn
          mbTmpDir =
            case hiDir flags'' of
              Just buildDir ->
                Just $ buildDir </> (takeBaseName buildDir ++ "-tmp")
              Nothing -> Nothing
      _ <-
        setSessionDynFlags $
        L.foldl'
          gopt_set
          (flags''
             { hscTarget = HscAsm
             , ghcLink = LinkInMemory
             , ghcMode = CompManager
             , log_action = logAction
             , importPaths = importPaths flags'' ++ maybeToList mbTmpDir
             })
          [Opt_Haddock]
      targets <- mapM (`guessTarget` Nothing) modules
      setTargets targets
      _ <- load LoadAllTargets
      modGraph <- getModuleGraph
      let topSortMods = flattenSCCs (topSortModuleGraph False modGraph Nothing)
          buildDir =
            addTrailingPathSeparator . normalise . fromMaybe "" . hiDir $
            flags''
          pathsModuleName =
            "Paths_" ++
            map
              (\c ->
                 if c == '-'
                   then '_'
                   else c)
              (T.unpack (HCE.name (currentPackageId :: HCE.PackageId)))
      (modSumWithPath, modulesNotFound) <-
        (\(mods, notFound) ->
           ( L.reverse .
             L.foldl'
               (\acc (mbPath, modSum) ->
                  case mbPath of
                    Just path
                      | not $ HM.member path defSiteMap -> (path, modSum) : acc
                    _ -> acc)
               [] $
             mods
           , map snd notFound)) .
        L.partition (\(mbPath, _) -> isJust mbPath) <$>
        mapM
          (\modSum ->
             liftIO $
             (, modSum) <$>
             findHaskellModulePath buildDir (srcDirs ++ libSrcDirs) modSum)
          (filter
             (\modSum ->
                pathsModuleName /=
                (moduleNameString . moduleName $ ms_mod modSum))
             topSortMods)
      unless (null modulesNotFound) $
        logErrorN $
        T.append
          "Cannot find module path : "
          (toText flags'' $ map ms_mod modulesNotFound)
      foldM
        (\(indexedModules, (fileMap', defSiteMap', modNameMap')) (modulePath, modSum) -> do
           result <-
             indexModule
               sourceCodePreprocessing
               componentId
               currentPackageId
               flags''
               (fileMap', defSiteMap', modNameMap')
               (modulePath, modSum)
           case result of
             Right (modInfo, (fileMap'', defSiteMap'', modNameMap'')) ->
               return
                 ( modInfo : indexedModules
                 , (fileMap'', defSiteMap'', modNameMap''))
             Left exception -> do
               logErrorN $
                 T.concat
                   [ "Error while indexing "
                   , T.pack . show $ modulePath
                   , " : "
                   , T.pack . show $ exception
                   ]
               return (indexedModules, (fileMap', defSiteMap', modNameMap')))
        ([], (fileMap, defSiteMap, modNameMap))
        modSumWithPath
          
findHaskellModulePath ::
     FilePath -> [FilePath] -> ModSummary -> IO (Maybe HCE.HaskellModulePath)
findHaskellModulePath buildDir srcDirs modSum =
  case normalise <$> (ml_hs_file . ms_location $ modSum) of
    Just modulePath ->
      let toHaskellModulePath = return . Just . HCE.HaskellModulePath . T.pack
          removeTmpDir path =
            case splitDirectories path of
              parent:rest ->
                if "-tmp" `L.isSuffixOf` parent
                  then joinPath rest
                  else path
              _ -> path
       in case removeTmpDir <$> L.stripPrefix buildDir modulePath of
            -- File is in the build directory        
            Just path
              | takeExtension path == ".hs-boot" -> do
                let possiblePaths = path : map (</> path) srcDirs
                mbFoundPath <- findM doesFileExist possiblePaths
                case mbFoundPath of
                  Just p -> toHaskellModulePath p
                  _ -> return Nothing
              | takeExtension path == ".hs" -> do
                let paths =
                      map
                        (replaceExtension path)
                        HCE.haskellPreprocessorExtensions
                    possiblePaths =
                      paths ++
                      concatMap (\srcDir -> map (srcDir </>) paths) srcDirs
                mbFoundPath <- findM doesFileExist possiblePaths
                case mbFoundPath of
                  Just p -> toHaskellModulePath p
                  _ -> return Nothing
              | otherwise -> return Nothing
            Nothing -> toHaskellModulePath modulePath
    Nothing -> return Nothing

indexModule ::
     HCE.SourceCodePreprocessing
  -> HCE.ComponentId
  -> HCE.PackageId
  -> DynFlags
  -> ModuleDependencies
  -> (HCE.HaskellModulePath, ModSummary)
  -> GhcT (LoggingT IO) (Either SomeException ( HCE.ModuleInfo
                                              , ModuleDependencies))
indexModule sourceCodePreprocessing componentId currentPackageId flags deps (modulePath, modSum) =
  gtrySync $ do
    logDebugN (T.append "Indexing " $ HCE.getHaskellModulePath modulePath)
    parsedModule <- parseModule modSum
    typecheckedModule <- typecheckModule parsedModule
    hscEnv <- getSession
    externalPackageState <- liftIO . readIORef . hsc_EPS $ hscEnv
    originalSourceCode <-
      liftIO $
      T.replace "\t" "        " . TE.decodeUtf8 <$>
      BS.readFile (T.unpack . HCE.getHaskellModulePath $ modulePath)
    let (modInfo, (fileMap', exportMap', moduleNameMap'), typeErrors) =
          createModuleInfo
            deps
            ( flags
            , typecheckedModule
            , hsc_HPT hscEnv
            , externalPackageState
            , modSum)
            modulePath
            currentPackageId
            componentId
            (originalSourceCode, sourceCodePreprocessing)
    unless (null typeErrors) $
      logInfoN $ T.append "Type errors : " $ T.pack $ show typeErrors
    deepseq modInfo $ return (modInfo, (fileMap', exportMap', moduleNameMap'))
