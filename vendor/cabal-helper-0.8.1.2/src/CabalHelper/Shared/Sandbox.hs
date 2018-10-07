-- cabal-helper: Simple interface to Cabal's configuration state
-- Copyright (C) 2015-2017  Daniel Gröber <cabal-helper@dxld.at>
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

{-|
Module      : CabalHelper.Shared.Sandbox
Description : Extracting information from @cabal.sandbox.config@ files
License     : GPL-3
-}

module CabalHelper.Shared.Sandbox where

import Control.Applicative
import Data.Char
import Data.Maybe
import Data.List
import Data.Version
import System.FilePath
import System.Directory
import Prelude

import qualified Data.Traversable as T

-- | Get the path to the sandbox package-db in a project
getSandboxPkgDb :: FilePath
             -- ^ Path to the cabal package root directory (containing the
             -- @cabal.sandbox.config@ file)
             -> String
             -- ^ Cabal build platform, i.e. @buildPlatform@
             -> Version
             -- ^ GHC version (@cProjectVersion@ is your friend)
             -> IO (Maybe FilePath)
getSandboxPkgDb d platform ghcVer = do
  mConf <- T.traverse readFile =<< mightExist (d </> "cabal.sandbox.config")
  return $ fixPkgDbVer <$> (extractSandboxDbDir =<< mConf)

 where
   fixPkgDbVer dir =
       case takeFileName dir == ghcSandboxPkgDbDir platform ghcVer of
         True -> dir
         False -> takeDirectory dir </> ghcSandboxPkgDbDir platform ghcVer

ghcSandboxPkgDbDir :: String -> Version -> String
ghcSandboxPkgDbDir platform ghcVer =
   platform ++ "-ghc-" ++ showVersion ghcVer ++ "-packages.conf.d"

-- | Extract the sandbox package db directory from the cabal.sandbox.config
-- file. Exception is thrown if the sandbox config file is broken.
extractSandboxDbDir :: String -> Maybe FilePath
extractSandboxDbDir conf = extractValue <$> parse conf
  where
    key = "package-db:"
    keyLen = length key

    parse = listToMaybe . filter (key `isPrefixOf`) . lines
    extractValue = CabalHelper.Shared.Sandbox.dropWhileEnd isSpace . dropWhile isSpace . drop keyLen


mightExist :: FilePath -> IO (Maybe FilePath)
mightExist f = do
  exists <- doesFileExist f
  return $ if exists then (Just f) else (Nothing)

-- dropWhileEnd is not provided prior to base 4.5.0.0.
dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd p = foldr (\x xs -> if p x && null xs then [] else x : xs) []
