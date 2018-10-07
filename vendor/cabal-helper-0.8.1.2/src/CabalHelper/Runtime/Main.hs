-- cabal-helper: Simple interface to Cabal's configuration state
-- Copyright (C) 2015-2018  Daniel Gröber <cabal-helper@dxld.at>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE CPP, BangPatterns, RecordWildCards, RankNTypes, ViewPatterns #-}

#ifdef MIN_VERSION_Cabal
#undef CH_MIN_VERSION_Cabal
#define CH_MIN_VERSION_Cabal MIN_VERSION_Cabal
#endif

import Distribution.Simple.Utils (cabalVersion)
import Distribution.Simple.Configure
import Distribution.Package
  ( PackageIdentifier
  , InstalledPackageId
  , PackageId
  , packageName
  , packageVersion
  )
import Distribution.PackageDescription
  ( PackageDescription
  , GenericPackageDescription(..)
  , Flag(..)
  , FlagName(..)
  , FlagAssignment
  , Executable(..)
  , Library(..)
  , TestSuite(..)
  , Benchmark(..)
  , BuildInfo(..)
  , TestSuiteInterface(..)
  , BenchmarkInterface(..)
  , withLib
  )
import Distribution.PackageDescription.Configuration
  ( flattenPackageDescription
  )
import Distribution.Simple.Program
  ( requireProgram
  , ghcProgram
  )
import Distribution.Simple.Program.Types
  ( ConfiguredProgram(..)
  )
import Distribution.Simple.Configure
  ( getPersistBuildConfig
  )
import Distribution.Simple.LocalBuildInfo
  ( LocalBuildInfo(..)
  , Component(..)
  , ComponentName(..)
  , ComponentLocalBuildInfo(..)
  , componentBuildInfo
  , externalPackageDeps
  , withComponentsLBI
  , withLibLBI
  , withExeLBI
  )
import Distribution.Simple.GHC
  ( componentGhcOptions
  )
import Distribution.Simple.Program.GHC
  ( GhcOptions(..)
  , renderGhcOptions
  )
import Distribution.Simple.Setup
  ( ConfigFlags(..)
  , Flag(..)
  , fromFlagOrDefault
  )
import Distribution.Simple.Build
  ( initialBuildSteps
  )
import Distribution.Simple.BuildPaths
  ( autogenModuleName
  , cppHeaderName
  )
import Distribution.Simple.Compiler
  ( PackageDB(..)
  , compilerId
  )
import Distribution.Compiler
  ( CompilerId(..)
  )
import Distribution.ModuleName
  ( components
  )
import qualified Distribution.ModuleName as C
  ( ModuleName
  )
import Distribution.Text
  ( display
  )
import Distribution.Verbosity
  ( Verbosity
  , silent
  , deafening
  , normal
  )
import Distribution.Version
  ( Version
  )

#if CH_MIN_VERSION_Cabal(1,22,0)
-- CPP >= 1.22
import Distribution.Utils.NubList
#endif

#if CH_MIN_VERSION_Cabal(1,23,0)
-- >= 1.23
import Distribution.Simple.LocalBuildInfo
  ( localUnitId
  )
#else
-- <= 1.22
import Distribution.Simple.LocalBuildInfo
  ( inplacePackageId
  )
#endif

#if CH_MIN_VERSION_Cabal(1,25,0)
-- >=1.25
import Distribution.PackageDescription
  ( unFlagName
  -- , mkFlagName
  )
import Distribution.Types.ForeignLib
  ( ForeignLib(..)
  )
import Distribution.Types.UnqualComponentName
  ( unUnqualComponentName
  )
#endif

#if CH_MIN_VERSION_Cabal(2,0,0)
-- CPP >= 2.0
import Distribution.Simple.LocalBuildInfo
  ( allLibModules
  , componentBuildDir
  )
import Distribution.Simple.Register
  ( internalPackageDBPath
  )
import Distribution.Backpack
  ( OpenUnitId(..),
    OpenModule(..)
  )
import Distribution.ModuleName
  ( ModuleName
  )
import Distribution.Types.ComponentId
  ( unComponentId
  )
import Distribution.Types.ComponentLocalBuildInfo
  ( maybeComponentInstantiatedWith
  )
import Distribution.Types.ModuleRenaming
  ( ModuleRenaming(..),
    isDefaultRenaming
  )
import Distribution.Types.MungedPackageId
  ( MungedPackageId
  )
import Distribution.Types.UnitId
  ( UnitId
  , unDefUnitId
  , unUnitId
  )
import Distribution.Types.UnitId
  ( DefUnitId
  )
import Distribution.Utils.NubList
  ( toNubListR
  )
import Distribution.Version
  ( versionNumbers
  , mkVersion
  )
import qualified Distribution.InstalledPackageInfo as Installed
#endif

#if CH_MIN_VERSION_Cabal(2,2,0)
import Distribution.Types.GenericPackageDescription
  ( unFlagAssignment
  )
#endif

import Control.Applicative ((<$>))
import Control.Arrow (first, second, (&&&))
import Control.Monad
import Control.Exception (catch, PatternMatchFail(..))
import Data.List
import qualified Data.Map as Map
import Data.Maybe
import Data.Monoid
import Data.IORef
import qualified Data.Version as DataVersion
import System.Environment
import System.Directory
import System.FilePath
import System.Exit
import System.IO
import System.IO.Unsafe (unsafeInterleaveIO, unsafePerformIO)
import Text.Printf

import CabalHelper.Shared.Sandbox
import CabalHelper.Shared.Common
import CabalHelper.Shared.InterfaceTypes

usage :: IO ()
usage = do
  prog <- getProgName
  hPutStr stderr $ "Usage: " ++ prog ++ " " ++ usageMsg
 where
   usageMsg = ""
     ++"PROJ_DIR DIST_DIR [--with-* ...] (\n"
     ++"    version\n"
     ++"  | print-lbi [--human]\n"
     ++"  | package-id\n"
     ++"  | flags\n"
     ++"  | config-flags\n"
     ++"  | non-default-config-flags\n"
     ++"  | write-autogen-files\n"
     ++"  | compiler-version\n"
     ++"  | ghc-options     [--with-inplace]\n"
     ++"  | ghc-src-options [--with-inplace]\n"
     ++"  | ghc-pkg-options [--with-inplace]\n"
     ++"  | ghc-merged-pkg-options [--with-inplace]\n"
     ++"  | ghc-lang-options [--with-inplace]\n"
     ++"  | package-db-stack\n"
     ++"  | entrypoints\n"
     ++"  | needs-build-output\n"
     ++"  | source-dirs\n"
     ++"  ) ...\n"

commands :: [String]
commands = [ "print-lbi"
           , "package-id"
           , "flags"
           , "config-flags"
           , "non-default-config-flags"
           , "write-autogen-files"
           , "compiler-version"
           , "ghc-options"
           , "ghc-src-options"
           , "ghc-pkg-options"
           , "ghc-lang-options"
           , "package-db-stack"
           , "entrypoints"
           , "needs-build-output"
           , "source-dirs"
           ]

main :: IO ()
main = do
  args <- getArgs

  projdir:distdir:args' <- case args of
                    [] -> usage >> exitFailure
                    _ -> return args

  ddexists <- doesDirectoryExist distdir
  when (not ddexists) $ do
         errMsg $ "distdir '"++distdir++"' does not exist"
         exitFailure

  [cfile] <- filter isCabalFile <$> getDirectoryContents projdir

  v <- maybe silent (const deafening) . lookup  "CABAL_HELPER_DEBUG" <$> getEnvironment
  lbi <- unsafeInterleaveIO $ getPersistBuildConfig distdir
  gpd <- unsafeInterleaveIO $ readPackageDescription v (projdir </> cfile)
  let pd = localPkgDescr lbi
  let lvd = (lbi, v, distdir)

  let
      -- a =<< b $$ c   ==  (a =<< b) $$ c
      infixr 2 $$
      ($$) = ($)

      collectCmdOptions :: [String] -> [[String]]
      collectCmdOptions =
          reverse . map reverse . foldl f [] . dropWhile isOpt
       where
         isOpt = ("--" `isPrefixOf`)
         f [] x = [[x]]
         f (a:as) x
             | isOpt x = (x:a):as
             | otherwise = [x]:(a:as)

  let cmds = collectCmdOptions args'

  if any (["version"] `isPrefixOf`) cmds
    then do
      putStrLn $
       printf "using version %s of the Cabal library" (display cabalVersion)
      exitSuccess
    else return ()

  print =<< flip mapM cmds $$ \x -> do
  case x of
    "flags":[] -> do
      return $ Just $ ChResponseFlags $ sort $
        map (flagName' &&& flagDefault) $ genPackageFlags gpd

    "config-flags":[] -> do
      return $ Just $ ChResponseFlags $ sort $
        map (first unFlagName)
#if CH_MIN_VERSION_Cabal(2,2,0)
          $ unFlagAssignment $ configConfigurationsFlags
#else
          $ configConfigurationsFlags
#endif
          $ configFlags lbi

    "non-default-config-flags":[] -> do
      let flagDefinitons = genPackageFlags gpd
          flagAssgnments =
#if CH_MIN_VERSION_Cabal(2,2,0)
            unFlagAssignment $ configConfigurationsFlags
#else
            configConfigurationsFlags
#endif
              $ configFlags lbi
          nonDefaultFlags =
              [ (flag_name, val)
              | MkFlag {flagName=(unFlagName -> flag_name'), flagDefault=def_val} <- flagDefinitons
              , (unFlagName -> flag_name, val) <- flagAssgnments
              , flag_name == flag_name'
              , val /= def_val
              ]
      return $ Just $ ChResponseFlags $ sort nonDefaultFlags

    "write-autogen-files":[] -> do
      initialBuildStepsForAllComponents distdir pd lbi v
      return Nothing

    "compiler-version":[] -> do
      let CompilerId comp ver = compilerId $ compiler lbi
      return $ Just $ ChResponseVersion (show comp) (toDataVersion ver)

    "ghc-options":flags -> do
      res <- componentOptions lvd True flags id
      return $ Just $ ChResponseCompList (res ++ [(ChSetupHsName, [])])

    "ghc-src-options":flags -> do
      res <- componentOptions lvd False flags $ \opts -> mempty {
               -- Not really needed but "unexpected package db stack: []"
               ghcOptPackageDBs      = [GlobalPackageDB, UserPackageDB],

               ghcOptCppOptions      = ghcOptCppOptions opts,
               ghcOptCppIncludePath  = ghcOptCppIncludePath opts,
               ghcOptCppIncludes     = ghcOptCppIncludes opts,
               ghcOptFfiIncludes     = ghcOptFfiIncludes opts,
               ghcOptSourcePathClear = ghcOptSourcePathClear opts,
               ghcOptSourcePath      = ghcOptSourcePath opts
              }
      return $ Just $ ChResponseCompList (res ++ [(ChSetupHsName, [])])

    "ghc-pkg-options":flags -> do
      res <- componentOptions lvd True flags $ \opts -> mempty {
                       ghcOptPackageDBs = ghcOptPackageDBs opts,
                       ghcOptPackages   = ghcOptPackages opts,
                       ghcOptHideAllPackages = ghcOptHideAllPackages opts
                   }
      return $ Just $ ChResponseCompList (res ++ [(ChSetupHsName, [])])

    "ghc-merged-pkg-options":flags -> do
      res <- mconcat . map snd <$> (componentOptions' lvd True flags (\_ _ o -> return o) $ \opts -> mempty {
                       ghcOptPackageDBs = [],
                       ghcOptHideAllPackages = NoFlag,
                       ghcOptPackages   = ghcOptPackages opts
                   })

      let res' = nubPackageFlags $ res { ghcOptPackageDBs = withPackageDB lbi
                                       , ghcOptHideAllPackages = Flag True
                                       }

      Just . ChResponseList <$> renderGhcOptions' lbi v res'

    "ghc-lang-options":flags -> do
      res <- componentOptions lvd False flags $ \opts -> mempty {
                       ghcOptPackageDBs      = [GlobalPackageDB, UserPackageDB],

                       ghcOptLanguage = ghcOptLanguage opts,
                       ghcOptExtensions = ghcOptExtensions opts,
                       ghcOptExtensionMap = ghcOptExtensionMap opts
                   }
      return $ Just $ ChResponseCompList (res ++ [(ChSetupHsName, [])])

    "package-db-stack":[] -> do
      let
          pkgDb GlobalPackageDB = ChPkgGlobal
          pkgDb UserPackageDB   = ChPkgUser
          pkgDb (SpecificPackageDB s) = ChPkgSpecific s

      -- TODO: Setup.hs has access to the sandbox as well: ghc-mod#478
      return $ Just $ ChResponsePkgDbs $ map pkgDb $ withPackageDB lbi

    "entrypoints":[] -> do
#if CH_MIN_VERSION_Cabal(2,0,0)
      includeDirMap <- recursiveDepInfo lbi v distdir
      eps <- componentsMap lbi v distdir $ \c clbi _bi -> do
               case needsBuildOutput includeDirMap (componentUnitId clbi) of
                 ProduceBuildOutput -> return $ componentEntrypoints c
                 NoBuildOutput -> return seps
                   where (_,_,seps) = recursiveIncludeDirs includeDirMap (componentUnitId clbi)
#else
      eps <- componentsMap lbi v distdir $ \c _clbi _bi ->
               return $ componentEntrypoints c
#endif
      -- MUST append Setup component at the end otherwise CabalHelper gets
      -- confused
      let eps' = eps ++ [(ChSetupHsName, ChSetupEntrypoint)]
      return $ Just $ ChResponseEntrypoints eps'

    "needs-build-output":[] -> do
#if CH_MIN_VERSION_Cabal(2,0,0)
      includeDirMap <- recursiveDepInfo lbi v distdir
      nbs <- componentsMap lbi v distdir $ \c clbi _bi ->
               return $ needsBuildOutput includeDirMap (componentUnitId clbi)
#else
      nbs <- componentsMap lbi v distdir $ \c _clbi _bi ->
               return $ NoBuildOutput
#endif
      return $ Just $ ChResponseNeedsBuild nbs

    "source-dirs":[] -> do
      res <- componentsMap lbi v distdir $$ \_ _ bi -> return $ hsSourceDirs bi
      return $ Just $ ChResponseCompList (res ++ [(ChSetupHsName, [])])

    "print-lbi":flags ->
      case flags of
        ["--human"] -> print lbi >> return Nothing
        []          -> return $ Just $ ChResponseLbi $ show lbi

    cmd:_ | not (cmd `elem` commands) ->
            errMsg ("Unknown command: " ++ cmd) >> usage >> exitFailure
    _ ->
            errMsg "Invalid usage!" >> usage >> exitFailure

flagName' = unFlagName . flagName

-- getLibrary :: PackageDescription -> Library
-- getLibrary pd = unsafePerformIO $ do
--   lr <- newIORef (error "libraryMap: empty IORef")
--   withLib pd (writeIORef lr)
--   readIORef lr

getLibraryClbi pd lbi = unsafePerformIO $ do
  lr <- newIORef Nothing

  withLibLBI pd lbi $ \ lib clbi ->
      writeIORef lr $ Just (lib,clbi)

  readIORef lr


getExeClbi pd lbi = unsafePerformIO $ do
  lr <- newIORef Nothing

  withExeLBI pd lbi $ \ exe clbi ->
      writeIORef lr $ Just (exe,clbi)

  readIORef lr


componentsMap :: LocalBuildInfo
              -> Verbosity
              -> FilePath
              -> (   Component
                  -> ComponentLocalBuildInfo
                  -> BuildInfo
                  -> IO a)
              -> IO [(ChComponentName, a)]
componentsMap lbi _v _distdir f = do
    let pd = localPkgDescr lbi

    lr <- newIORef []

    -- withComponentsLBI is deprecated but also exists in very old versions
    -- it's equivalent to withAllComponentsInBuildOrder in newer versions
    withComponentsLBI pd lbi $ \c clbi -> do
        let bi = componentBuildInfo c
            name = componentNameFromComponent c

        l' <- readIORef lr
        r <- f c clbi bi
#if CH_MIN_VERSION_Cabal(2,0,0)
        writeIORef lr $ (componentNameToCh (unUnitId $ componentUnitId clbi) name, r):l'
#else
        writeIORef lr $ (componentNameToCh "" name, r):l'
#endif

    reverse <$> readIORef lr

componentOptions' (lbi, v, distdir) inplaceFlag flags rf f = do
  let pd = localPkgDescr lbi
#if CH_MIN_VERSION_Cabal(2,0,0)
  includeDirMap <- recursiveDepInfo lbi v distdir
#endif

  componentsMap lbi v distdir $ \c clbi bi ->
         let
           outdir = componentOutDir lbi c
           (clbi', adopts) = case flags of
                               _ | not inplaceFlag -> (clbi, mempty)
                               ["--with-inplace"] -> (clbi, mempty)
#if CH_MIN_VERSION_Cabal(2,0,0)
                               [] -> removeInplaceDeps v lbi pd clbi includeDirMap
#else
                               [] -> removeInplaceDeps v lbi pd clbi
#endif
           opts = componentGhcOptions normal lbi bi clbi' outdir
           opts' = f opts

         in rf lbi v $ nubPackageFlags $ opts' `mappend` adopts

componentOptions (lbi, v, distdir) inplaceFlag flags f =
    componentOptions' (lbi, v, distdir) inplaceFlag flags renderGhcOptions' f

gmModuleName :: C.ModuleName -> ChModuleName
gmModuleName = ChModuleName . intercalate "." . components

#if CH_MIN_VERSION_Cabal(2,0,0)
removeInplaceDeps :: Verbosity
                  -> LocalBuildInfo
                  -> PackageDescription
                  -> ComponentLocalBuildInfo
                  -> Map.Map UnitId SubDeps
                  -> (ComponentLocalBuildInfo, GhcOptions)
removeInplaceDeps _v lbi pd clbi includeDirs = let
    removeInplace c =
      let
        (ideps, incs) = partition (isInplaceCompInc c) (componentIncludes c)
        hasIdeps' = not $ null ideps
        c' = c { componentPackageDeps  = error "using deprecated field:componentPackageDeps"
               , componentInternalDeps = []
               , componentIncludes     = incs }
      in (hasIdeps',c')

    needsBuild = needsBuildOutput includeDirs (componentUnitId clbi)

    cleanRecursiveOpts :: Component
                       -> BuildInfo -> ComponentLocalBuildInfo -> GhcOptions
    cleanRecursiveOpts comp libbi libclbi =
      let
        liboutdir = componentOutDir lbi comp
        (_,libclbi') = removeInplace libclbi
        (extraIncludes,extraDeps',_ems) = recursiveIncludeDirs includeDirs (componentUnitId libclbi)
        (_,extraDeps) = partition (isInplaceCompInc libclbi) extraDeps'
        opts = (componentGhcOptions normal lbi libbi libclbi' liboutdir) {
                  ghcOptPackageDBs = []
               }

      in
        opts { ghcOptSourcePath = ghcOptSourcePath opts <> toNubListR extraIncludes
             , ghcOptPackages   = ghcOptPackages   opts <> toNubListR extraDeps }

    libopts =
      case (getLibraryClbi pd lbi,getExeClbi pd lbi) of
        (Just (lib, libclbi),_) | hasIdeps ->
          let
            libbi = libBuildInfo lib
            opts = cleanRecursiveOpts (CLib lib) libbi libclbi
          in
            opts { ghcOptInputModules = ghcOptInputModules opts <> (toNubListR $ allLibModules lib libclbi) }
        (_,Just (exe,execlbi)) | hasIdeps ->
          let
            exebi = buildInfo exe
          in
            cleanRecursiveOpts (CExe exe) exebi execlbi
        _ -> mempty

    distDir = fromFlagOrDefault ("." </> "dist") (configDistPref $ configFlags lbi)
    packageDbDir = internalPackageDBPath lbi distDir
    (hasIdeps,clbi') = case needsBuild of
                         NoBuildOutput -> removeInplace clbi
                         ProduceBuildOutput -> (False, clbi)
    libopts' = case needsBuild of
                 NoBuildOutput -> libopts
                 ProduceBuildOutput -> mempty { ghcOptPackageDBs = [SpecificPackageDB packageDbDir] }
  in (clbi', libopts')
#else
removeInplaceDeps :: Verbosity
                  -> LocalBuildInfo
                  -> PackageDescription
                  -> ComponentLocalBuildInfo
                  -> (ComponentLocalBuildInfo, GhcOptions)
removeInplaceDeps _v lbi pd clbi = let
    (ideps, deps) = partition (isInplaceDep lbi) (componentPackageDeps clbi)
    hasIdeps = not $ null ideps
    libopts =
      case getLibraryClbi pd lbi of
        Just (lib, libclbi) | hasIdeps ->
          let
            libbi = libBuildInfo lib
            liboutdir = componentOutDir lbi (CLib lib)
          in
            (componentGhcOptions normal lbi libbi libclbi liboutdir) {
                ghcOptPackageDBs = []
            }
        _ -> mempty
    clbi' = clbi { componentPackageDeps = deps }
  in (clbi', libopts)
#endif


#if CH_MIN_VERSION_Cabal(2,0,0)
recursiveDepInfo lbi v distdir = do
  includeDirs <- componentsMap lbi v distdir $ \c clbi bi -> do
    return (componentUnitId clbi
           , ( SubDeps
                { sdComponentInternalDeps = componentInternalDeps clbi
                , sdHsSourceDirs          = hsSourceDirs bi
                , sdComponentIncludes     = componentIncludes clbi
                , sdComponentEntryPoints  = componentEntrypoints c})  )
  return $ Map.fromList $ map snd includeDirs

data SubDeps = SubDeps
  { sdComponentInternalDeps :: [UnitId]
  , sdHsSourceDirs          :: [FilePath]
  , sdComponentIncludes     :: [(OpenUnitId, ModuleRenaming)]
  , sdComponentEntryPoints  :: ChEntrypoint
  }

recursiveIncludeDirs :: Map.Map UnitId SubDeps
                     -> UnitId -> ([FilePath], [(OpenUnitId, ModuleRenaming)]
                                  , ChEntrypoint)
recursiveIncludeDirs includeDirs unit = go ([],[],Nothing) [unit]
  where
    go (afp,aci,Nothing  ) [] = (afp,aci,error "recursiveIncludeDirs:no ChEntrypoint")
    go (afp,aci,Just amep) [] = (afp,aci,amep)
    go acc@(afp,aci,amep) (u:us) = case Map.lookup u includeDirs of
      Nothing -> go acc us
      Just (SubDeps us' sfp sci sep) -> go (afp++sfp,aci++sci,Just (combineEp amep sep)) (us++us')

needsBuildOutput :: Map.Map UnitId SubDeps -> UnitId -> NeedsBuildOutput
needsBuildOutput includeDirs unit = go [unit]
  where
    isIndef (IndefFullUnitId _ _) = True
    isIndef _                     = False
    go [] = NoBuildOutput
    go (u:us) = case Map.lookup u includeDirs of
      Nothing -> go us
      Just (SubDeps us' sfp sci sep) ->
        if any (isIndef . fst) sci
          then ProduceBuildOutput
          else go (us++us')

-- | combineEP is used to combine the entrypoints when recursively chasing
-- through the dependencies of a given entry point. The first parameter is the
-- current accumulated value, and the second one is the current sub-dependency
-- being considered. So the bias should be to preserve the type of entrypoint
-- from the first parameter.
combineEp Nothing e = e
combineEp (Just ChSetupEntrypoint) e = e
combineEp (Just (ChLibEntrypoint es1 os1 ss1))   (ChLibEntrypoint es2 os2 ss2) = (ChLibEntrypoint (nub $ es2++es1) (nub $ os2++os1) (nub $ ss2++ss1))
combineEp _                                    e@(ChExeEntrypoint  mi os2)     = error $ "combineEP: cannot have a sub exe:" ++ show e
combineEp (Just (ChExeEntrypoint  mi os1))       (ChLibEntrypoint es2 os2 ss2) = (ChExeEntrypoint mi  (nub $ os1++es2++os2++ss2))

-- no, you unconditionally always wrap the result in Just, so instead of `f x = Just y; f x = Just z` do `f x = y; f x = z` and use f as `Just . f`



instantiatedGhcPackage :: (ModuleName,OpenModule) -> [(OpenUnitId, ModuleRenaming)]
instantiatedGhcPackage (_,OpenModule oui@(DefiniteUnitId _) _) = [(oui,DefaultRenaming)]
instantiatedGhcPackage (_, _) = []
#endif

initialBuildStepsForAllComponents distdir pd lbi v =
  initialBuildSteps distdir pd lbi v






#if !CH_MIN_VERSION_Cabal(1,25,0)
-- CPP < 1.25
unFlagName (FlagName n) = n
-- mkFlagName n = FlagName n
#endif

toDataVersion :: Version -> DataVersion.Version
--fromDataVersion :: DataVersion.Version -> Version
#if CH_MIN_VERSION_Cabal(2,0,0)
toDataVersion v = DataVersion.Version (versionNumbers v) []
--fromDataVersion (DataVersion.Version vs _) = mkVersion vs
#else
toDataVersion = id
--fromDataVersion = id
#endif

componentNameToCh _uid CLibName = ChLibName
#if CH_MIN_VERSION_Cabal(1,25,0)
-- CPP >= 1.25
#if CH_MIN_VERSION_Cabal(2,0,0)
componentNameToCh uid (CSubLibName n) = ChSubLibName uid
#else
componentNameToCh _uid (CSubLibName n) = ChSubLibName (unUnqualComponentName' n)
#endif
componentNameToCh uid (CFLibName   n) = ChFLibName (unUnqualComponentName' n)
#endif
componentNameToCh _uid (CExeName n) = ChExeName (unUnqualComponentName' n)
componentNameToCh _uid (CTestName n) = ChTestName (unUnqualComponentName' n)
componentNameToCh _uid (CBenchName n) = ChBenchName (unUnqualComponentName' n)

#if CH_MIN_VERSION_Cabal(1,25,0)
-- CPP >= 1.25
unUnqualComponentName' = unUnqualComponentName
#else
unUnqualComponentName' = id
#endif

#if !CH_MIN_VERSION_Cabal(1,25,0)
-- CPP < 1.25
componentNameFromComponent (CLib Library {}) = CLibName
#elif CH_MIN_VERSION_Cabal(1,25,0)
-- CPP >= 1.25 (redundant)
componentNameFromComponent (CLib Library { libName = Nothing }) = CLibName
componentNameFromComponent (CLib Library { libName = Just n })  = CSubLibName n
componentNameFromComponent (CFLib ForeignLib {..}) = CFLibName foreignLibName
#endif
componentNameFromComponent (CExe Executable {..}) = CExeName exeName
componentNameFromComponent (CTest TestSuite {..}) = CTestName testName
componentNameFromComponent (CBench Benchmark {..}) = CBenchName benchmarkName

componentOutDir lbi (CLib Library {..})=
    buildDir lbi
#if CH_MIN_VERSION_Cabal(2,0,0)
componentOutDir lbi (CFLib ForeignLib {..}) =
    componentOutDir' lbi (unUnqualComponentName foreignLibName)
#endif
componentOutDir lbi (CExe Executable {..}) =
    componentOutDir' lbi (unUnqualComponentName' exeName)
componentOutDir lbi (CTest TestSuite { testInterface = TestSuiteExeV10 _ _, ..}) =
    componentOutDir' lbi (unUnqualComponentName' testName)
componentOutDir lbi (CTest TestSuite { testInterface = TestSuiteLibV09 _ _, ..}) =
    componentOutDir' lbi (unUnqualComponentName' testName ++ "Stub")
componentOutDir lbi (CBench Benchmark { benchmarkInterface = BenchmarkExeV10 _ _, ..})=
    componentOutDir' lbi (unUnqualComponentName' benchmarkName)

componentOutDir' :: LocalBuildInfo -> String -> FilePath
componentOutDir' lbi compName' =
  ----- Copied from Distribution/Simple/GHC.hs:buildOrReplExe
  let targetDir = (buildDir lbi) </> compName'
      compDir    = targetDir </> (compName' ++ "-tmp")
  in compDir

componentEntrypoints :: Component -> ChEntrypoint
componentEntrypoints (CLib Library {..})
    = ChLibEntrypoint
        (map gmModuleName exposedModules)
        (map gmModuleName $ otherModules libBuildInfo)
#if CH_MIN_VERSION_Cabal(2,0,0)
        (map gmModuleName signatures)
#else
        [] -- no signatures prior to Cabal 2.0
#endif
#if CH_MIN_VERSION_Cabal(2,0,0)
componentEntrypoints (CFLib (ForeignLib{..}))
    = ChLibEntrypoint
        []
        (map gmModuleName $ otherModules foreignLibBuildInfo)
        []
#endif
componentEntrypoints (CExe Executable {..})
    = ChExeEntrypoint
        modulePath
        (map gmModuleName $ otherModules buildInfo)
componentEntrypoints (CTest TestSuite { testInterface = TestSuiteExeV10 _ fp, ..})
    = ChExeEntrypoint fp (map gmModuleName $ otherModules testBuildInfo)
componentEntrypoints (CTest TestSuite { testInterface = TestSuiteLibV09 _ mn, ..})
    = ChLibEntrypoint [gmModuleName mn] (map gmModuleName $ otherModules testBuildInfo) []
componentEntrypoints (CTest TestSuite {})
    = ChLibEntrypoint [] [] []
componentEntrypoints (CBench Benchmark { benchmarkInterface = BenchmarkExeV10 _  fp, ..})
    = ChExeEntrypoint fp (map gmModuleName $ otherModules benchmarkBuildInfo)
componentEntrypoints (CBench Benchmark {})
    = ChLibEntrypoint [] [] []

#if CH_MIN_VERSION_Cabal(2,0,0)
isInplaceCompInc :: ComponentLocalBuildInfo -> (OpenUnitId, ModuleRenaming) -> Bool
isInplaceCompInc clbi (DefiniteUnitId uid, _mr)     = unDefUnitId uid `elem` componentInternalDeps clbi
isInplaceCompInc clbi (IndefFullUnitId uid _, _mmr) = False
#endif

#if CH_MIN_VERSION_Cabal(2,0,0)
isInplaceDep :: LocalBuildInfo -> ComponentLocalBuildInfo -> (UnitId, MungedPackageId) -> Bool
isInplaceDep lbi clbi (uid, _mpid) = uid `elem` componentInternalDeps clbi
#else
isInplaceDep :: LocalBuildInfo -> (InstalledPackageId, PackageId) -> Bool
#  if CH_MIN_VERSION_Cabal(1,23,0)
-- CPP >= 1.23
isInplaceDep lbi (ipid, _pid) = localUnitId lbi == ipid
#  else
-- CPP <= 1.22
isInplaceDep _lbi (ipid, pid) = inplacePackageId pid == ipid
#  endif
#endif

#if CH_MIN_VERSION_Cabal(1,22,0)
-- CPP >= 1.22
-- >= 1.22 uses NubListR
nubPackageFlags opts = opts
#else
nubPackageFlags opts = opts { ghcOptPackages = nub $ ghcOptPackages opts }
#endif

renderGhcOptions' :: LocalBuildInfo
                  -> Verbosity
                  -> GhcOptions
                  -> IO [String]
#if !CH_MIN_VERSION_Cabal(1,20,0)
renderGhcOptions' lbi v opts = do
-- CPP < 1.20
  (ghcProg, _) <- requireProgram v ghcProgram (withPrograms lbi)
  let Just ghcVer = programVersion ghcProg
  return $ renderGhcOptions ghcVer opts
#elif CH_MIN_VERSION_Cabal(1,20,0) && !CH_MIN_VERSION_Cabal(1,24,0)
renderGhcOptions' lbi _v opts = do
-- CPP >= 1.20 && < 1.24
  return $ renderGhcOptions (compiler lbi) opts
#else
renderGhcOptions' lbi _v opts = do
-- CPP >= 1.24
  return $ renderGhcOptions (compiler lbi) (hostPlatform lbi) opts
#endif
