module Str.String where

import Prelude hiding (null)
import qualified Prelude as P

type Str = String

null :: Str -> Bool
null = P.null

singleton :: Char -> Str
singleton c = [c]

splits :: Str -> [(Str, Str)]
splits [] = [([], [])]
splits (c:cs) = ([], c:cs):[(c:s1,s2) | (s1,s2) <- splits cs]

parts :: Str -> [[Str]]
parts [] = [[]]
parts [c] = [[[c]]]
parts (c:cs) = concat [[(c:p):ps, [c]:p:ps] | p:ps <- parts cs]
