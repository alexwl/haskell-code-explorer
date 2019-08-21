{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Codec.Compression.GZip(compress)
import Control.Exception (SomeException, handle)
import Control.Monad (when)
import Control.Monad.Logger (LogLevel(..), runLoggingT)
import qualified Data.Aeson as A
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSC
import qualified Data.HashMap.Strict as HM
import Data.Maybe (fromMaybe)
import Data.Semigroup ((<>))
import qualified Data.Serialize as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (getZonedTime)
import Data.Version (showVersion)
import HaskellCodeExplorer.PackageInfo (createPackageInfo, ghcVersion)
import qualified HaskellCodeExplorer.Types as HCE
import Network.URI.Encode (encode)
import Options.Applicative
  ( Parser
  , (<|>)
  , execParser
  , flag
  , fullDesc
  , help
  , helper
  , info
  , long
  , many
  , metavar
  , optional
  , progDesc
  , short
  , showDefault
  , strOption
  , value
  )
import Paths_haskell_code_explorer as HSE (version)
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode(..), exitWith)
import System.FilePath ((</>))
import System.Log.FastLogger
  ( LoggerSet
  , ToLogStr(..)
  , defaultBufSize
  , fromLogStr
  , newFileLoggerSet
  , newStdoutLoggerSet
  , pushLogStrLn
  , rmLoggerSet
  )

data IndexerConfig = IndexerConfig
  { configPackageDirectoryPath :: FilePath
  , configPackageDistDirRelativePath :: Maybe FilePath
  , configOutputDirectoryName :: Maybe String
  , configLog :: !HCE.Log
  , configMinLogLevel :: !LogLevel
  , configSourceCodePreprocessing :: !HCE.SourceCodePreprocessing
  , configCompression :: !Compression
  , configGhcOptions :: [String]
  , configIgnoreDirectories :: [String]
  } deriving (Show, Eq)

data Compression
  = Gzip
  | NoCompression
  deriving (Show, Eq)

versionInfo :: String
versionInfo =
  "haskell-code-indexer version " ++
  showVersion version ++ ", GHC version " ++ showVersion ghcVersion

main :: IO ()
main = do
  let description =
        "haskell-code-indexer collects and saves information about the source code of a Cabal package. " ++
        versionInfo
  config <-
    execParser $
    info (helper <*> configParser) (fullDesc <> progDesc description)
  loggerSet <-
    case configLog config of
      HCE.ToFile logfile -> newFileLoggerSet defaultBufSize logfile
      HCE.StdOut -> newStdoutLoggerSet defaultBufSize
  let minLogLevel = configMinLogLevel config
  logger loggerSet minLogLevel LevelInfo versionInfo
  logger loggerSet minLogLevel LevelDebug $ show config
  handle
    (\(e :: SomeException) -> do
       logger loggerSet minLogLevel LevelError (show e)
       rmLoggerSet loggerSet
       exitWith (ExitFailure 1)) $ do
    packageInfo <-
      runLoggingT
        (createPackageInfo
           (configPackageDirectoryPath config)
           (configPackageDistDirRelativePath config)
           (configSourceCodePreprocessing config)
           (configGhcOptions config)
           (configIgnoreDirectories config))
        (\_loc _source level msg -> logger loggerSet minLogLevel level msg)
    let outputDir =
          configPackageDirectoryPath config </>
          fromMaybe
            HCE.defaultOutputDirectoryName
            (configOutputDirectoryName config)
    createDirectoryIfMissing False outputDir
    logger loggerSet minLogLevel LevelDebug $ "Output directory : " ++ outputDir
    BS.writeFile
      (outputDir </> HCE.packageInfoBinaryFileName)
      (S.encode $ HCE.toCompactPackageInfo packageInfo)
    mapM_
      (\(HCE.HaskellModulePath path, modInfo) ->
         let (compressFunction, compressExtension) =
               case configCompression config of
                 Gzip -> (compress, ".gz")
                 NoCompression -> (id, "")
             filePath =
               outputDir </>
               (encode (T.unpack path) ++ ".json" ++ compressExtension)
          in BSL.writeFile filePath . compressFunction . A.encode $ modInfo) .
      HM.toList $
      HCE.moduleMap (packageInfo :: HCE.PackageInfo HCE.ModuleInfo)
    BSL.writeFile
      (outputDir </> HCE.packageInfoJsonFileName)
      (A.encode packageInfo)
    BSL.writeFile (outputDir </> "version.txt") (BSC.pack $ showVersion version)
    logger loggerSet minLogLevel LevelInfo ("Finished" :: T.Text)
    rmLoggerSet loggerSet

configParser :: Parser IndexerConfig
configParser =
  IndexerConfig <$>
  strOption
    (long "package" <> short 'p' <> metavar "PATH" <> value "." <> showDefault <>
     help "Path to a Cabal package") <*>
  optional
    (strOption
       (long "dist" <> metavar "RELATIVE_PATH" <>
        help "Relative path to a dist directory")) <*>
  optional
    (strOption
       (long "output" <> metavar "DIRECTORY_NAME" <>
        help "Output directory (default is '.haskell-code-explorer')")) <*>
  (pure HCE.StdOut <|>
   (HCE.ToFile <$>
    strOption
      (long "logfile" <> metavar "PATH" <>
       help "Path to a log file (by default log is written to stdout)"))) <*>
  flag
    LevelInfo
    LevelDebug
    (long "verbose" <> short 'v' <> help "Write debug information to a log") <*>
  flag
    HCE.AfterPreprocessing
    HCE.BeforePreprocessing
    (long "before-preprocessing" <>
     help
       "Index source code before preprocessor pass (by default source code after preprocessing is indexed)") <*>
  flag
    Gzip
    NoCompression
    (long "no-compression" <>
     help
       "Do not compress json files (by default json files are compressed using gzip)") <*>
  many
    (strOption
       (long "ghc" <> metavar "OPTIONS" <> help "Command-line options for GHC")) <*>
  many
    (strOption
       (long "ignore" <> metavar "DIRECTORY_NAME" <>
        help "Directories to ignore (e.g. node_modules)"))

logger :: ToLogStr msg => LoggerSet -> LogLevel -> LogLevel -> msg -> IO ()
logger loggerSet minLogLevel logLevel msg =
  when (logLevel >= minLogLevel) $ do
    time <- getZonedTime
    let showLogLevel :: LogLevel -> T.Text
        showLogLevel LevelDebug = "[debug]"
        showLogLevel LevelInfo = "[info]"
        showLogLevel LevelWarn = "[warn]"
        showLogLevel LevelError = "[error]"
        showLogLevel (LevelOther t) =  T.concat ["[",t,"]"]
        text =
          T.concat
            [ T.pack $ show time
            , " : "
            , showLogLevel logLevel
            , " "
            , TE.decodeUtf8 . fromLogStr . toLogStr $ msg
            ]
    pushLogStrLn loggerSet $ toLogStr text
