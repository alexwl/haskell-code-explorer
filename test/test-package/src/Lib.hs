module Lib
    ( someFunc
    ) where

import Types(Test(..))

-- | someFunc documentation
someFunc :: IO ()
someFunc = putStrLn "someFunc"

-- | mkTest documentation
mkTest :: Int -> Test
mkTest i = Test i
