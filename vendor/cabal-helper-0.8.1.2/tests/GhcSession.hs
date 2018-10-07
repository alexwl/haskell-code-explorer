{-# LANGUAGE TupleSections, ScopedTypeVariables #-}
module Main where

import GHC
import GHC.Paths (libdir)
import DynFlags

import qualified Control.Exception as E
import Control.Monad
import Control.Monad.IO.Class
import Data.List
import Data.Version
import System.Environment (getArgs)
import System.Exit
import System.FilePath ((</>))
import System.Directory
import System.IO
import System.IO.Temp
import System.Process (rawSystem, readProcess)

import Distribution.Helper

import CabalHelper.Shared.Common


main :: IO ()
main = do
  args <- getArgs
  topdir <- getCurrentDirectory
  res <- mapM (setup topdir test) $ case args of
    [] -> [ ("tests/exelib"   , parseVer "1.10", parseVer "0")
          , ("tests/exeintlib", parseVer "2.0",  parseVer "0")
          , ("tests/fliblib"  , parseVer "2.0",  parseVer "0")
          , ("tests/bkpregex" , parseVer "2.0",  parseVer "8.1")
          --           min Cabal lib ver -^   min GHC ver -^
          ]
    xs -> map (, parseVer "0", parseVer "0") xs

  if any (==False) $ concat res
    then exitFailure
    else exitSuccess

cabalInstallVersion :: IO Version
cabalInstallVersion =
    parseVer . trim <$> readProcess "cabal" ["--numeric-version"] ""

ghcVersion :: IO Version
ghcVersion =
    parseVer . trim <$> readProcess "ghc" ["--numeric-version"] ""

cabalInstallBuiltinCabalVersion :: IO Version
cabalInstallBuiltinCabalVersion =
    parseVer . trim <$> readProcess "cabal"
        ["act-as-setup", "--", "--numeric-version"] ""

setup :: FilePath -> (FilePath -> IO [Bool]) -> (FilePath, Version, Version) -> IO [Bool]
setup topdir act (srcdir, min_cabal_ver, min_ghc_ver) = do
    ci_ver <- cabalInstallVersion
    c_ver <- cabalInstallBuiltinCabalVersion
    g_ver <- ghcVersion
    let mreason
          | (ci_ver < parseVer "1.24") =
            Just $ "cabal-install-" ++ showVersion ci_ver ++ " is too old"
          | c_ver < min_cabal_ver =
            Just $ "Cabal-" ++ showVersion c_ver
                   ++ " < " ++ showVersion min_cabal_ver
          | g_ver < min_ghc_ver =
            Just $ "ghc-" ++ showVersion g_ver
                   ++ " < " ++ showVersion min_ghc_ver
          | otherwise =
            Nothing

    case mreason of
      Just reason -> do
        putStrLn $ "Skipping test '" ++ srcdir ++ "' because " ++ reason ++ "."
        return []
      Nothing -> do
        putStrLn $ "Running test '" ++ srcdir ++ "' ------------------------------"
        withSystemTempDirectory "cabal-helper.ghc-session.test" $ \dir -> do
          setCurrentDirectory $ topdir </> srcdir
          run "cabal" [ "sdist", "--output-dir", dir ]

          setCurrentDirectory dir
          run "cabal" [ "configure" ]

          act dir

run :: String -> [String] -> IO ()
run x xs = do
  print $ x:xs
  ExitSuccess <- rawSystem x xs
  return ()

test :: FilePath -> IO [Bool]
test dir = do
    let qe = mkQueryEnv dir (dir </> "dist")
    cs <- runQuery qe $ components $ (,,,) <$> entrypoints <.> ghcOptions <.> needsBuildOutput
    forM cs $ \(ep, opts, nb, cn) -> do

        putStrLn $ "\n" ++ show cn ++ ":::: " ++ show nb

        when (nb == ProduceBuildOutput) $ do
          run "cabal" [ "build" ]

        let opts' = "-Werror" : opts

        let sopts = intercalate " " $ map formatArg $ "\nghc" : opts'
        putStrLn $ "\n" ++ show cn ++ ": " ++ sopts
        hFlush stdout
        compileModule nb ep opts'
  where
    formatArg x
        | "-" `isPrefixOf` x = "\n  "++x
        | otherwise          = x


compileModule :: NeedsBuildOutput -> ChEntrypoint -> [String] -> IO Bool
compileModule nb ep opts = do

    putStrLn $ "compiling:" ++ show ep ++ " (" ++ show nb ++ ")"

    E.handle (\(ec :: ExitCode) -> print ec >> return False) $ do

    defaultErrorHandler defaultFatalMessager defaultFlushOut $ do

    runGhc (Just libdir) $ do

    handleSourceError (\e -> GHC.printException e >> return False) $ do

    let target = case nb of
          ProduceBuildOutput -> HscNothing -- AZ: what should this be?
          NoBuildOutput      -> HscInterpreted

    dflags0 <- getSessionDynFlags
    let dflags1 = dflags0 {
        ghcMode   = CompManager
      , ghcLink   = LinkInMemory
      , hscTarget = target
      , optLevel  = 0
      }

    (dflags2, _, _) <- parseDynamicFlags dflags1 (map noLoc opts)
    _ <- setSessionDynFlags dflags2

    ts <- mapM (\t -> guessTarget t Nothing) $
         case ep of
           ChLibEntrypoint ms ms' ss -> map unChModuleName $ ms ++ ms' ++ ss
           ChExeEntrypoint m'  ms    ->
             let

               -- The options first clear out includes, then put in the build dir. We want the
               -- first one after that, so "regex-example" in the following case
               --
               -- ,"-i"
               -- ,"-idist/build/regex-example"
               -- ,"-iregex-example"
               firstInclude = drop 2 $ head $ drop 2 $ filter (isPrefixOf "-i") opts
               m = firstInclude </> m'
             in [m] ++ map unChModuleName ms
           ChSetupEntrypoint         -> ["Setup.hs"]

    let ts' = case nb of
                NoBuildOutput -> map (\t -> t { targetAllowObjCode = False }) ts
                ProduceBuildOutput -> ts

    setTargets ts'
    _ <- load LoadAllTargets

    when (nb == NoBuildOutput) $ do
      setContext $ case ep of
        ChLibEntrypoint ms ms' ss ->
            map (IIModule . mkModuleName . unChModuleName) $ ms ++ ms' ++ ss
        ChExeEntrypoint _  ms  ->
            map (IIModule . mkModuleName . unChModuleName) $ ChModuleName "Main" : ms
        ChSetupEntrypoint      ->
            map (IIModule . mkModuleName) ["Main"]

    liftIO $ print ExitSuccess
    return True

unChModuleName :: ChModuleName -> String
unChModuleName (ChModuleName  mn) = mn
