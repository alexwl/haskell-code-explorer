{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE StrictData #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- |  Read-only on-disk key-value store

module Store where

import Control.DeepSeq (NFData)
import Control.Monad.IO.Class (liftIO)
import qualified Control.Monad.State.Strict as S
import qualified Data.ByteString as BS
import qualified Data.ByteString.Short as BSS
import Data.Either (Either)
import qualified Data.Map.Strict as M
import Data.Serialize (Serialize, decode, encode, get, put)
import GHC.Generics (Generic)
import Prelude hiding (lookup)
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import System.IO (Handle, IOMode(..), hTell, withFile)
import System.IO.MMap (mmapFileByteString)

data Store = Store
  { index :: M.Map BSS.ShortByteString Location
  , values :: BS.ByteString
  }
  
data Location = Location
  { offset :: Int
  , length :: Int
  } deriving (Show, Eq, Ord, Generic, NFData)

instance Serialize Location

#if MIN_VERSION_cereal(0,5,8)
#else
instance Serialize BSS.ShortByteString where
  put = put . BSS.fromShort
  get = BSS.toShort <$> get
#endif  

class StoreItem item where
  toByteString :: item -> BS.ByteString
  fromByteString :: BS.ByteString -> Either String item
  type KeyArgs item = arg | arg -> item
  itemKey :: KeyArgs item -> BSS.ShortByteString

indexFileName :: FilePath
indexFileName = "index"

valuesFileName :: FilePath
valuesFileName = "values"

data ReadMode
  = ReadEntireFile
  | MemoryMapFile
  deriving (Show, Eq)
 
load :: FilePath -> ReadMode -> IO (Either String Store)
load directoryPath readMode = do
  let valuesFilePath = directoryPath </> valuesFileName
      indexFilePath = directoryPath </> indexFileName
  (valuesFileExists, indexFileExists) <-
    (,) <$> doesFileExist indexFilePath <*> doesFileExist valuesFilePath
  case (valuesFileExists, indexFileExists) of
    (True, True) -> do
      indexFile <- BS.readFile indexFilePath
      valuesFile <-
        case readMode of
          ReadEntireFile -> BS.readFile valuesFilePath
          MemoryMapFile -> mmapFileByteString valuesFilePath Nothing
      let eitherIndex = decode @(M.Map BSS.ShortByteString Location) indexFile
      case eitherIndex of
        Right locMap -> return . Right $ Store {index = locMap, values = valuesFile}
        Left err -> return . Left $ "Error while decoding index : " ++ err
    (False, False) ->
      return . Left $ "Cannot find index and values in " ++ directoryPath
    (True, False) -> return . Left $ "Cannot find index in " ++ directoryPath
    (False, True) -> return . Left $ "Cannot find values in " ++ directoryPath

lookup :: (StoreItem item) => KeyArgs item -> Store -> Either String item
lookup keyArgs = lookupByteString (itemKey keyArgs)
      
lookupByteString ::
     (StoreItem item) => BSS.ShortByteString -> Store -> Either String item
lookupByteString key store =
  case M.lookup key (index store) of
    Just (Location off len) ->
      fromByteString . BS.take len . BS.drop off $ values store
    Nothing -> Left $ "Cannot find item with key " ++ show key

data State =
  State (M.Map BSS.ShortByteString Location)
        Handle

add :: (StoreItem item) => item -> KeyArgs item -> S.StateT State IO ()
add item keyArgs = do
  let bs = toByteString item
      len = BS.length bs
  State locMap handle <- S.get
  off <- liftIO $ fromIntegral <$> hTell handle
  _ <- liftIO $ BS.hPut handle bs
  S.put $ State (M.insert (itemKey keyArgs) (Location off len) locMap) handle

createStore ::
     FilePath -> (Handle -> IO (M.Map BSS.ShortByteString Location)) -> IO ()
createStore directoryPath action =
  withFile (directoryPath </> valuesFileName) WriteMode $ \valuesHandle -> do
    locMap <- action valuesHandle
    BS.writeFile (directoryPath </> indexFileName) (encode locMap)
  
writeValues ::
     Handle
  -> M.Map BSS.ShortByteString Location
  -> S.StateT State IO ()
  -> IO (M.Map BSS.ShortByteString Location)
writeValues handle locMap action = do
  State locMap' _ <- S.execStateT action (State locMap handle)
  return locMap'
