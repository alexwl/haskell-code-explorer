{-# LANGUAGE OverloadedStrings #-}
module Main where

import Regex.Types
import qualified Regex.String
import qualified Regex.ByteString

nocs = Rep (Alt (Sym 'a') (Sym 'b'))
onec = Seq nocs (Sym 'c')
evencs = Seq (Rep (Seq onec onec)) nocs
main = print (Regex.String.accept evencs "acc") >>
       print (Regex.ByteString.accept evencs "acc")
