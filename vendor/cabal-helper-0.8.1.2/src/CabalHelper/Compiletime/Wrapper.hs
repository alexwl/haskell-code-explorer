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
{-# LANGUAGE RecordWildCards, NamedFieldPuns, FlexibleContexts, ViewPatterns #-}
module Main where

import Cabal.Plan
import Control.Applicative
import Control.Monad
import Data.Char
import Data.List
import Data.Maybe
import Data.String
import Text.Printf
import Text.Show.Pretty
import System.Console.GetOpt
import System.Environment
import System.Directory
import System.FilePath
import System.Process
import System.Exit
import System.IO
import Prelude

import qualified Data.Text as Text
import qualified Data.Map.Strict as Map

import Distribution.System (buildPlatform)
import Distribution.Text (display)
import Distribution.Verbosity (silent, deafening)
import Distribution.Package (packageName, packageVersion)
import Distribution.Simple.GHC as GHC (configure)

import Paths_cabal_helper (version)
import CabalHelper.Compiletime.Compat.ProgramDb
    ( defaultProgramDb, programPath, lookupProgram, ghcProgram, ghcPkgProgram)
import CabalHelper.Compiletime.Compat.Version
import CabalHelper.Compiletime.Compile
import CabalHelper.Compiletime.Types
import CabalHelper.Shared.Common
import CabalHelper.Shared.InterfaceTypes

usage :: IO ()
usage = do
  prog <- getProgName
  hPutStr stderr $ "Usage: " ++ prog ++ " " ++ usageMsg
 where
   usageMsg = "\
\( print-appcachedir\n\
\| print-build-platform\n\
\| [--verbose]\n\
\  [--with-ghc=GHC_PATH]\n\
\  [--with-ghc-pkg=GHC_PKG_PATH]\n\
\  [--with-cabal=CABAL_PATH]\n\
\  [--with-cabal-version=VERSION]\n\
\  [--with-cabal-pkg-db=PKG_DB]\n\
\  v1-style PROJ_DIR DIST_DIR \n\
\      ( print-exe | package-id | [CABAL_HELPER_ARGS...] )\n\
\  v2-style PROJ_DIR DIST_NEWSTYLE_DIR DIST_DIR\n\
\      ( print-exe | package-id | [CABAL_HELPER_ARGS...] )\n\
\)\n"

globalArgSpec :: [OptDescr (Options -> Options)]
globalArgSpec =
      [ option "h" ["help"] "Display help message" $
              NoArg $ \o -> o { oHelp = True }
      , option "" ["verbose"] "Be more verbose" $
              NoArg $ \o -> o { oVerbose = True }

      , option "" ["with-ghc"] "GHC executable to use" $
              reqArg "PROG" $ \p o -> o { oGhcProgram = p }

      , option "" ["with-ghc-pkg"] "ghc-pkg executable to use (only needed when guessing from GHC path fails)" $
              reqArg "PROG" $ \p o -> o { oGhcPkgProgram = p }

      , option "" ["with-cabal"] "cabal-install executable to use" $
               reqArg "PROG" $ \p o -> o { oCabalProgram = p }

      , option "" ["with-cabal-version"] "Cabal library version to use" $
               reqArg "VERSION" $ \p o -> o { oCabalVersion = Just $ parseVer p }

      , option "" ["with-cabal-pkg-db"] "package database to look for Cabal library in" $
               reqArg "PKG_DB" $ \p o -> o { oCabalPkgDb = Just (PackageDbDir p) }

      ]
 where
   option :: [Char] -> [String] -> String -> ArgDescr a -> OptDescr a
   option s l udsc dsc = Option s l dsc udsc

   reqArg :: String -> (String -> a) -> ArgDescr a
   reqArg udsc dsc = ReqArg dsc udsc

parseCommandArgs :: Options -> [String] -> (Options, [String])
parseCommandArgs opts argv
    = case getOpt RequireOrder globalArgSpec argv of
        (o,r,[])   -> (foldr id opts o, r)
        (_,_,errs) ->
            panic $ "Parsing command options failed:\n" ++ concat errs

guessProgramPaths :: Options -> IO Options
guessProgramPaths opts = do
    let v | oVerbose opts = deafening
          | otherwise     = silent

        mGhcPath0    | same oGhcProgram opts dopts = Nothing
                     | otherwise = Just $ oGhcProgram opts
        mGhcPkgPath0 | same oGhcPkgProgram opts dopts = Nothing
                     | otherwise = Just $ oGhcPkgProgram opts

    (_compiler, _mplatform, progdb)
        <- GHC.configure
               v
               mGhcPath0
               mGhcPkgPath0
               defaultProgramDb

    let mghcPath1    = programPath <$> lookupProgram ghcProgram progdb
        mghcPkgPath1 = programPath <$> lookupProgram ghcPkgProgram progdb

    return $ opts { oGhcProgram    = fromMaybe (oGhcProgram opts) mghcPath1
                  , oGhcPkgProgram = fromMaybe (oGhcProgram opts) mghcPkgPath1
                  }
 where
   same f o o'  = f o == f o'
   dopts = defaultOptions

overrideVerbosityEnvVar :: Options -> IO Options
overrideVerbosityEnvVar opts = do
  x <- lookup  "CABAL_HELPER_DEBUG" <$> getEnvironment
  return $ case x of
    Just _  -> opts { oVerbose = True }
    Nothing -> opts

main :: IO ()
main = handlePanic $ do
  (opts', args) <- parseCommandArgs defaultOptions <$> getArgs
  opts <- overrideVerbosityEnvVar =<< guessProgramPaths opts'
  case args of
    _ | oHelp opts -> usage
    [] -> usage
    "help":[] -> usage
    "version":[] -> putStrLn $ showVersion version
    "print-appdatadir":[] -> putStrLn =<< appCacheDir
    "print-appcachedir":[] -> putStrLn =<< appCacheDir
    "print-build-platform":[] -> putStrLn $ display buildPlatform

    _:projdir:_distdir:"package-id":[] -> do
      let v | oVerbose opts = deafening
            | otherwise    = silent
      -- ghc-mod will catch multiple cabal files existing before we get here
      [cfile] <- filter isCabalFile <$> getDirectoryContents projdir
      gpd <- readPackageDescription v (projdir </> cfile)
      putStrLn $ show $
        [Just $ ChResponseVersion (display (packageName gpd)) (toDataVersion $ packageVersion gpd)]

    "v2-style":projdir:distdir_newstyle:unitid':args' -> do
      let unitid = UnitId $ Text.pack unitid'
      let plan_path = distdir_newstyle </> "cache" </> "plan.json"
      plan@PlanJson {pjCabalLibVersion=Ver (makeDataVersion -> pjCabalLibVersion) }
          <- decodePlanJson plan_path
      case oCabalVersion opts of
        Just ver | pjCabalLibVersion /= ver -> let
            sver = showVersion ver
            spjVer = showVersion pjCabalLibVersion
          in panic $ printf "\
\Cabal version %s was requested but plan.json was written by version %s" sver spjVer
        _ -> case Map.lookup unitid $ pjUnits plan of
               Just u@Unit {uType} | uType /= UnitTypeLocal -> do
                 panic $ "\
\UnitId '"++ unitid' ++"' points to non-local unit: " ++ ppShow u
               Just Unit {uDistDir=Nothing} -> panic $ printf "\
\plan.json doesn't contain 'dist-dir' for UnitId '"++ unitid' ++"'"
               Just Unit {uType=UnitTypeLocal, uDistDir=Just distdir} ->
                 runHelper opts projdir (Just (plan, distdir_newstyle)) distdir pjCabalLibVersion args'
               _ -> let
                   units = map (\(UnitId u) -> Text.unpack u)
                         $ Map.keys
                         $ Map.filter ((==UnitTypeLocal) . uType)
                         $ pjUnits plan

                   units_list = unlines $ map ("  "++) units
                 in
                   panic $ "\
\UnitId '"++ unitid' ++"' not found in plan.json, available local units:\n" ++ units_list

    "v1-style":projdir:distdir:args' -> do
      cfgf <- canonicalizePath (distdir </> "setup-config")
      mhdr <- getCabalConfigHeader cfgf
      case (mhdr, oCabalVersion opts) of
        (Nothing, _) -> panic $ printf "\
\Could not read Cabal's persistent setup configuration header\n\
\- Check first line of: %s\n\
\- Maybe try: $ cabal configure" cfgf
        (Just (hdrCabalVersion, _), Just ver)
          | hdrCabalVersion /= ver -> panic $ printf "\
\Cabal version %s was requested but setup configuration was\n\
\written by version %s" (showVersion ver) (showVersion hdrCabalVersion)
        (Just (hdrCabalVersion, _), _) ->
          runHelper opts projdir Nothing distdir hdrCabalVersion args'
    _ -> do
      hPutStrLn stderr "Invalid command line!"
      usage
      exitWith $ ExitFailure 1

runHelper :: Options -> FilePath -> Maybe (PlanJson, FilePath) -> FilePath -> DataVersion -> [String] -> IO ()
runHelper opts projdir mnewstyle distdir cabal_ver args' = do
  eexe <- compileHelper opts cabal_ver projdir mnewstyle distdir
  case eexe of
      Left e -> exitWith e
      Right exe -> do
        case args' of
          "print-exe":_ -> putStrLn exe
          _ -> do
            (_,_,_,h) <- createProcess $ proc exe $ projdir : distdir : args'
            exitWith =<< waitForProcess h
