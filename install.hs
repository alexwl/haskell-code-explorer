#!/usr/bin/env stack
{- stack script
  --resolver lts-13.12
  --ghc-options -Wall
-}

{-# LANGUAGE CPP #-}
-- = About
--
-- Install multiple versions of haskell-code-indexer, each with the version of
-- GHC it was built with appended to the executable name.
--
-- = Original
--
-- Modified from the BSD3 licensed script at:
-- https://github.com/haskell/haskell-ide-engine/blob/ec5e34ca52d389b713df918f02ff63920aede4be/install.hs
--
-- Thanks haskell-ide-engine folks!
--
-- = Changes from the original
--
-- + Switched from Shake to IO script
-- + Added optparse-applicative
-- + Switched to Stack only (PRs welcome to support other tools)
module Main (main) where

import Control.Monad
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isSpace)
import Data.Foldable
import Data.List (dropWhileEnd)
import qualified Data.Text as T
import Data.Text.Encoding
import System.FilePath ((<.>), (</>))
import Options.Applicative
import System.Directory (copyFile, removeFile)
import System.Process.Typed

-- | Keep this in sync with the stack.yamls at the top level of the project.
supportedGhcVersions :: [Version]
supportedGhcVersions =
  map Version ["8.0.2", "8.2.2", "8.4.3", "8.4.4", "8.6.3", "8.6.4"]

newtype Version = Version { unVersion :: String } deriving Eq

-- * CLI args

data Args = Args
  { argBuildVersions :: [Version]
  , argBuildServer :: Bool
  }

cliArgs :: IO Args
cliArgs =
  customExecParser (prefs showHelpOnError) argsParser

argsParser :: ParserInfo Args
argsParser =
  fmap defaultToAll $
    info (helper <*> parser) (fullDesc <> progDesc desc)
  where
    parser :: Parser Args
    parser =
      Args
        <$> (some indexVersion <|> pure mempty)
        <*> switch
              (  long "server"
              <> help "Build haskell-code-server"
              )

    indexVersion :: Parser Version
    indexVersion =
      argument (eitherReader checkVersion)
        ( metavar "INDEX_VERSION"
        <> help "haskell-code-indexer-X-Y-Z version to build"
        )

    checkVersion :: String -> Either String Version
    checkVersion s =
        case find ((==) (Version s)) supportedGhcVersions of
          Nothing ->
            Left . unwords $
                "Not a supported GHC version. Currently supported versions are:"
              : map unVersion supportedGhcVersions

          Just v ->
            Right v

    defaultToAll :: Args -> Args
    defaultToAll args =
      if argBuildVersions args == mempty && argBuildServer args == False
        then Args (reverse supportedGhcVersions) True -- reverse to build latest first
        else args

    desc :: String
    desc =
      "Install haskell-code-indexer executables with the GHC version they were"
      <> " compiled with appended to their name. Builds everything if you don't"
      <> " specify options. Note that if you already have an indexer executable"
      <> " without the GHC version appended in your Stack's local bin"
      <> " it will be deleted."

-- * Build

main :: IO ()
main =
  run =<< cliArgs

run :: Args -> IO ()
run args = do
  putStrLn (startupNotice args)
  when (argBuildServer args) buildServer
  for_ (argBuildVersions args) buildVersion

startupNotice :: Args -> String
startupNotice args =
  unlines
     $ "Building:"
     : (if argBuildServer args
         then ["  + haskell-code-explorer"]
         else mempty)
    <> map versionEntry (argBuildVersions args)
  where
    versionEntry :: Version -> String
    versionEntry v =
      "  + haskell-code-indexer-" <> unVersion v

buildServer :: IO ()
buildServer =
  void $ execStack ["build", "--copy-bins", "haskell-code-explorer:haskell-code-server"]

buildVersion :: Version -> IO ()
buildVersion v = do
  execStackWithVersion_ v ["build", "--copy-bins", "haskell-code-explorer:haskell-code-indexer"]
  localBinDir <- getLocalBin

  let
    -- exe is "exe" on Windows and "" otherwise
    fromFile = localBinDir </> "haskell-code-indexer" <.> exe
    toFile = localBinDir </> "haskell-code-indexer-" ++ unVersion v <.> exe

  copyFile fromFile toFile
  removeFile fromFile

exe :: String
#if defined(mingw32_HOST_OS)
exe = "exe"
#else
exe = ""
#endif

-- | E.g. @"/home/user/bin"@.
getLocalBin :: IO FilePath
getLocalBin = do
  stackLocalDir' <- decodeUtf8 <$> execStack ["path", "--stack-yaml=stack.yaml", "--local-bin"]
  pure $ trimEnd (T.unpack stackLocalDir')

-- | Uses the stack.yaml for the given @Version@.
execStackWithVersion_ :: Version -> [String] -> IO ()
execStackWithVersion_ v args = do
  let stackFile = "stack-" ++ unVersion v ++ ".yaml"
  void $ execStack (("--stack-yaml=" ++ stackFile) : args)

execStack :: [String] -> IO ByteString
execStack =
  fmap LBS.toStrict . readProcessStdout_ . proc "stack"

trimEnd :: String -> String
trimEnd = dropWhileEnd isSpace
