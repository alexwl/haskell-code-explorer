module Regex where

import Prelude hiding (null)
import Str
import Regex.Types

accept :: Reg -> Str -> Bool
accept Eps       u = null u
accept (Sym c)   u = u == singleton c
accept (Alt p q) u = accept p u || accept q u
accept (Seq p q) u =
    or [accept p u1 && accept q u2 | (u1, u2) <- splits u]
accept (Rep r) u =
    or [and [accept r ui | ui <- ps] | ps <- parts u]
