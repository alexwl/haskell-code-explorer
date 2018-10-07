{-# LANGUAGE ScopedTypeVariables, GADTs #-}

import System.Environment (getArgs)
import System.Directory
import System.FilePath
import System.Process
import System.Exit
import System.IO
import Control.Exception as E
import Data.List
import Data.Maybe
import Data.Version
import Data.Functor
import Data.Function
import qualified Distribution.Compat.ReadP as Dist
import Distribution.Version (VersionRange, withinRange)
import Distribution.Text
import Control.Arrow
import Control.Monad
import Prelude

import CabalHelper.Compiletime.Compat.Environment
import CabalHelper.Compiletime.Compat.Version
import CabalHelper.Compiletime.Compile
import CabalHelper.Compiletime.Types
import CabalHelper.Shared.Common

runReadP'Dist :: Dist.ReadP t t -> String -> t
runReadP'Dist p i = case filter ((=="") . snd) $ Dist.readP_to_S p i of
                 (a,""):[] -> a
                 _ -> error $ "Error parsing: " ++ show i

withinRange'CH :: Version -> VersionRange -> Bool
withinRange'CH v r =
    withinRange (fromDataVersion v) r

setupHOME :: IO ()
setupHOME = do
  tmp <- fromMaybe "/tmp" <$> lookupEnv "TMPDIR"
  let home = tmp </> "compile-test-home"
  _ <- rawSystem "rm" ["-r", home]
  createDirectory    home
  setEnv "HOME" home

main :: IO ()
main = do
  args <- getArgs
  case args of
    "list-versions":[] -> do
        mapM_ print =<< (allCabalVersions <$> ghcVersion defaultOptions)
    "list-versions":ghc_ver_str:[] ->
        mapM_ print $ allCabalVersions (parseVer ghc_ver_str)
    _ ->
        test args

test args = do
  let action
       | null args = testAllCabalVersions
       | otherwise = testCabalVersions $ map parseVer' args

  setupHOME

  _ <- rawSystem "cabal" ["update"]

  action

parseVer' :: String -> Either HEAD Version
parseVer' "HEAD" = Left HEAD
parseVer' v      = Right $ parseVer v

allCabalVersions :: Version -> [Version]
allCabalVersions ghc_ver = let
    cabal_versions :: [Version]
    cabal_versions = map parseVer
         -- "1.14.0" -- not supported at runtime
         [ "1.16.0"
         , "1.16.0.1"
         , "1.16.0.2"
         , "1.16.0.3"
         , "1.18.0"
         , "1.18.1"
         , "1.18.1.1"
         , "1.18.1.2"
         , "1.18.1.3"
         , "1.18.1.4"
         , "1.18.1.5"
         , "1.18.1.6"
         , "1.18.1.7"
         , "1.20.0.0"
         , "1.20.0.1"
         , "1.20.0.2"
         , "1.20.0.3"
         , "1.20.0.4"
         , "1.22.0.0"
         , "1.22.1.0"
         , "1.22.1.1"
         , "1.22.2.0"
         , "1.22.3.0"
         , "1.22.4.0"
         , "1.22.5.0"
         , "1.22.6.0"
         , "1.22.7.0"
         , "1.22.8.0"
         , "1.24.0.0"
         , "1.24.1.0"
         , "1.24.2.0"
         , "2.0.0.2"
         , "2.0.1.0"
         , "2.0.1.1"
         , "2.2.0.0"
         , "2.2.0.1"
         ]

    constraint :: VersionRange
    constraint =
        fromMaybe (snd $ last constraint_table) $
        fmap snd $
        find (and . (zipWith (==) `on` versionBranch) ghc_ver . fst) $
        constraint_table

    constraint_table =
        map (parseVer *** runReadP'Dist parse) $
            [ ("7.4"  , ">= 1.14    && < 2")
            , ("7.6"  , ">= 1.16    && < 2")
            , ("7.8"  , ">= 1.18    && < 2")
            , ("7.10" , ">= 1.22.2  && < 2")
            , ("8.0.1", ">= 1.24          ")
            , ("8.0.2", ">= 1.24.2        ")
            , ("8.2.1", ">= 2.0.0.2       ")
            , ("8.2.2", ">= 2.0.0.2       ")
            , ("8.4.1", ">= 2.0.0.2       ")
            , ("8.4.2", ">= 2.2.0.1       ")
            ]
  in
    reverse $ filter (flip withinRange'CH constraint) cabal_versions


testAllCabalVersions :: IO ()
testAllCabalVersions = do
  ghc_ver <- ghcVersion defaultOptions
  let relevant_cabal_versions = allCabalVersions ghc_ver
  testCabalVersions $ map Right relevant_cabal_versions ++ [Left HEAD]

testCabalVersions :: [Either HEAD Version] -> IO ()
testCabalVersions versions = do
  rvs <- forM versions $ \ver -> do
           let sver = either show showVersion ver
           hPutStrLn stderr $ "\n\n\n\n\n\n====== Compiling with Cabal-" ++ sver
           compilePrivatePkgDb ver

  let printStatus (cv, rv) = putStrLn $ "- Cabal "++ver++" "++status
        where  ver = case cv of Left _ -> "HEAD"; Right v -> showVersion v
               status = case rv of
                         Right _ ->
                             "succeeded"
                         Left rvc ->
                             "failed (exit code "++show rvc++")"

  let drvs = versions `zip` rvs

  mapM_ printStatus drvs
  if any isLeft' $ map snd $ filter ((/=Left HEAD) . fst) drvs
     then exitFailure
     else exitSuccess

 where
   isLeft' (Left _) = True
   isLeft' (Right _) = False

compilePrivatePkgDb :: Either HEAD Version -> IO (Either ExitCode FilePath)
compilePrivatePkgDb eCabalVer = do
    res <- E.try $ installCabal defaultOptions { oVerbose = True } eCabalVer
    case res of
      Right (db, cabalVer) ->
          compileWithPkg db cabalVer
      Left (ioe :: IOException) -> do
          print ioe
          return $ Left (ExitFailure 1)

compileWithPkg :: PackageDbDir
               -> CabalVersion
               -> IO (Either ExitCode FilePath)
compileWithPkg db cabalVer = do
    appdir <- appCacheDir
    let comp =
          CompileWithCabalPackage (Just db) cabalVer [cabalPkgId cabalVer] CPSGlobal
    compile
      comp
      (compPaths appdir (error "compile-test: distdir not available") comp)
      defaultOptions { oVerbose = True }


cabalPkgId :: CabalVersion -> String
cabalPkgId (CabalHEAD _commitid) = "Cabal"
cabalPkgId (CabalVersion v) = "Cabal-" ++ showVersion v
