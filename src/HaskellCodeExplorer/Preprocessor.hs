{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module HaskellCodeExplorer.Preprocessor
  ( createSourceCodeTransformation
  ) where

import Control.Applicative ((<|>))
import qualified Data.Attoparsec.Text as AT
import Data.Foldable (foldl')
import qualified Data.HashMap.Strict as HM
import qualified Data.List as L
import qualified Data.Set as S
import qualified Data.Text as T
import HaskellCodeExplorer.Types
  ( FileLocation(..)
  , HaskellFilePath(..)
  , HaskellModulePath(..)
  , LinePragma(..)
  , SourceCodeTransformation(..)
  , haskellPreprocessorExtensions  
  )
import System.FilePath (normalise,takeExtension,takeFileName)

-- | Finds locations of line pragmas and creates an index
createSourceCodeTransformation ::
     HaskellModulePath -> T.Text -> T.Text -> (SourceCodeTransformation, T.Text)
createSourceCodeTransformation currentModulePath originalSourceCode sourceCodeAfterPreprocessing =
  let sourceCodeLines = T.splitOn "\n" sourceCodeAfterPreprocessing
      numberedLines = zip [1 :: Int ..] sourceCodeLines
      currentFilePath =
        HaskellFilePath . getHaskellModulePath $ currentModulePath
      addPragma :: [LinePragma] -> (Int, T.Text) -> [LinePragma]
      addPragma acc (lineNumber, line) =
        case AT.parseOnly linePragmaParser line of
          Right (originalLineNumber, mbFileName) ->
            LinePragma
              (maybe
                 currentFilePath
                 (HaskellFilePath . T.pack . normalise . T.unpack)
                 mbFileName)
              lineNumber
              originalLineNumber :
            acc
          Left _ -> acc
      totalLines = length numberedLines
      pragmas = L.reverse . L.foldl' addPragma [] $ numberedLines
      pragmaPath = filePath :: LinePragma -> HaskellFilePath
      currentFileExtension =
        takeExtension . T.unpack . getHaskellFilePath $ currentFilePath
      standardHeaderFiles =
        [ "stdc-predef.h"
        , "cabal_macros.h"
        , "ghcversion.h"
        , "HsVersions.h"
        , "ghc_boot_platform.h"
        , "ghcautoconf.h"
        ]
      hasIncludedFiles =
        L.any
          ((\path ->
              let fileName = takeFileName . T.unpack . getHaskellFilePath $ path
               in (path /= currentFilePath) &&
                  (path /= HaskellFilePath "<built-in>") &&
                  (path /= HaskellFilePath "<command-line>") &&
                  not ("ghc_" `L.isPrefixOf` fileName) &&
                  (fileName `notElem` standardHeaderFiles)) .
           pragmaPath)
          pragmas
   in if hasIncludedFiles ||
         currentFileExtension `elem` haskellPreprocessorExtensions
        then ( SourceCodeTransformation
                 totalLines
                 currentModulePath
                 (S.fromList pragmas)
                 (indexLocations totalLines currentFilePath pragmas)
             , sourceCodeAfterPreprocessing)
        else ( SourceCodeTransformation
                 (length $ T.splitOn "\n" originalSourceCode)
                 currentModulePath
                 S.empty
                 HM.empty
             , originalSourceCode)

-- | Parses line pragma
linePragmaParser :: AT.Parser (Int, Maybe T.Text)
linePragmaParser = pragma1 <|> pragma2
  where   
    pragma1 :: AT.Parser (Int, Maybe T.Text)
    pragma1 = parser "#" "line"
    
    pragma2 :: AT.Parser (Int, Maybe T.Text)
    pragma2 = parser "{-#" "LINE"
    
    parser :: T.Text -> T.Text -> AT.Parser (Int, Maybe T.Text)
    parser start line = do
      _ <- AT.string start
      _ <- AT.takeWhile (== ' ')
      _ <- AT.string line <|> return ""
      _ <- AT.takeWhile (== ' ')
      num <- AT.decimal
      _ <- AT.takeWhile (== ' ')
      mbName <- (Just <$> fileName) <|> return Nothing
      return (num, mbName)
      
    fileName :: AT.Parser T.Text
    fileName = AT.string "\"" *> AT.takeTill (== '\"') <* AT.string "\""    

data Line = FirstLine | LastLine Int | Pragma LinePragma deriving (Show,Eq)

-- | Creates a HashMap whose keys are filenames and values are locations in a
-- preprocessed source code
indexLocations ::
     Int
  -> HaskellFilePath
  -> [LinePragma]
  -> HM.HashMap HaskellFilePath (S.Set FileLocation)
indexLocations totalLines preprocessedFilePath pragmas =
  foldl' add HM.empty . (zip <*> tail) $
  (FirstLine : map Pragma pragmas) ++ [LastLine totalLines]
  where
    add ::
         HM.HashMap HaskellFilePath (S.Set FileLocation)
      -> (Line, Line)
      -> HM.HashMap HaskellFilePath (S.Set FileLocation)
    -- Interval between the first line and the first pragma
    add hMap (FirstLine, Pragma LinePragma {..})
      | lineNumberPreprocessed > 1 =
        HM.insertWith
          S.union
          preprocessedFilePath
          (S.singleton (FileLocation 1 lineNumberPreprocessed 0))
          hMap
      | otherwise = hMap
    -- Interval between two pragmas
    add hMap (Pragma (LinePragma fileName lineNumberPreprocessed1 lineNumberOriginal1),
              Pragma (LinePragma _ lineNumberPreprocessed2 _))
      | lineNumberPreprocessed2 - lineNumberPreprocessed1 > 1 =
        HM.insertWith
          S.union
          fileName
          (S.singleton
             (FileLocation
                lineNumberOriginal1
                (lineNumberOriginal1 +
                 (lineNumberPreprocessed2 - lineNumberPreprocessed1 - 2))
                (lineNumberPreprocessed1 - lineNumberOriginal1 + 1)))
          hMap
      | otherwise = hMap
    -- Interval between the last pragma and the last line
    add hMap (Pragma (LinePragma fileName lineNumberPreprocessed lineNumberOriginal),
              LastLine lastLineNumberPreprocessed)
      | lastLineNumberPreprocessed - lineNumberPreprocessed > 1 =
        HM.insertWith
          S.union
          fileName
          (S.singleton
             (FileLocation
                lineNumberOriginal
                (lineNumberOriginal + (lastLineNumberPreprocessed - lineNumberPreprocessed - 2))
                (lineNumberPreprocessed - lineNumberOriginal + 1)))
          hMap
      | otherwise = hMap
    add hMap _ = hMap
