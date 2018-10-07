-- cabal-helper: Simple interface to Cabal's configuration state
-- Copyright (C) 2017-2018  Daniel Gröber <cabal-helper@dxld.at>
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

{-# LANGUAGE CPP #-}
module CabalHelper.Compiletime.Compat.Version
    ( DataVersion
    , toDataVersion
    , fromDataVersion
    , Data.Version.showVersion
    , makeDataVersion
    ) where

import qualified Data.Version
import qualified Distribution.Version (Version)
#if MIN_VERSION_Cabal(2,0,0)
import qualified Distribution.Version  (versionNumbers, mkVersion)
#endif

type DataVersion = Data.Version.Version

toDataVersion :: Distribution.Version.Version -> Data.Version.Version
fromDataVersion :: Data.Version.Version -> Distribution.Version.Version
#if MIN_VERSION_Cabal(2,0,0)
toDataVersion v = Data.Version.Version (Distribution.Version.versionNumbers v) []
fromDataVersion (Data.Version.Version vs _) = Distribution.Version.mkVersion vs
#else
toDataVersion = id
fromDataVersion = id
#endif

makeDataVersion :: [Int] -> Data.Version.Version
#if MIN_VERSION_base(4,8,0)
makeDataVersion = Data.Version.makeVersion
#else
makeDataVersion xs = Data.Version.Version xs []
#endif
