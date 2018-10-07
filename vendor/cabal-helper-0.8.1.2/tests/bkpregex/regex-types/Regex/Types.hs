module Regex.Types where

data Reg = Eps
         | Sym Char
         | Alt Reg Reg
         | Seq Reg Reg
         | Rep Reg
