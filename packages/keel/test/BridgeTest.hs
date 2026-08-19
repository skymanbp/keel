-- | Bridge invariants: the copy round-trips exactly, every refusal path
-- (missing column, wrong type, nulls, ragged lengths) fires, and the
-- matrix layout is row-major as keel-linalg expects.
module Main (main) where

import Control.Monad (unless)
import Data.Text qualified as T
import Data.Vector.Storable qualified as VS

import DataFrame.Internal.Column (Column, columnLength, fromList, fromUnboxedVector, numElements)
import DataFrame.Internal.DataFrame (DataFrame, fromNamedColumns)
import Data.Vector.Unboxed qualified as VU
import Keel.Bridge

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

col :: [Double] -> Column
col = fromUnboxedVector . VU.fromList

frame :: DataFrame
frame =
  fromNamedColumns
    [ (T.pack "x", col [1, 2, 3])
    , (T.pack "y", col [4, 5, 6])
    , (T.pack "short", col [7, 8])
    , (T.pack "ints", fromList [1 :: Int, 2, 3])
    , (T.pack "holey", fromList [Just (1 :: Double), Nothing, Just 3])
    ]

main :: IO ()
main = do
  -- sanity: the Maybe column really carries a null per dataframe itself
  let holey = fromList [Just (1 :: Double), Nothing, Just 3]
  expect (columnLength holey == 3 && numElements holey == 2)
    ("null column not represented as expected: length "
      <> show (columnLength holey) <> ", elements " <> show (numElements holey))

  -- round-trip: frame -> buffer -> column -> buffer, exact
  x <- either (fail . show) pure (columnToStorable frame (T.pack "x"))
  expect (VS.toList x == [1, 2, 3]) ("columnToStorable: " <> show (VS.toList x))
  let back = storableToColumn x
      reframe = fromNamedColumns [(T.pack "x2", back)]
  x2 <- either (fail . show) pure (columnToStorable reframe (T.pack "x2"))
  expect (VS.toList x2 == [1, 2, 3]) ("round-trip: " <> show (VS.toList x2))

  -- refusals (ColumnLengthMismatch is unreachable through a real frame:
  -- dataframe pads short columns with nulls on insert, so the "short"
  -- column must surface as ColumnHasNulls instead — assert exactly that)
  expect (isLeft (columnToStorable frame (T.pack "nope")) ColumnNotFound')
    "missing column not refused"
  expect (isLeft (columnToStorable frame (T.pack "ints")) ColumnTypeMismatch')
    "Int column not refused for Double extraction"
  expect (isLeft (columnToStorable frame (T.pack "holey")) ColumnHasNulls')
    "null-bearing column not refused"
  expect (isLeft (columnsToMatrix frame [T.pack "x", T.pack "short"]) ColumnHasNulls')
    "frame-padded short column not refused as null-bearing"

  -- row-major layout: [x | y] as 3x2 must interleave rows
  (m, mat) <- either (fail . show) pure (columnsToMatrix frame [T.pack "x", T.pack "y"])
  expect (m == 3) ("matrix rows: " <> show m)
  expect (VS.toList mat == [1, 4, 2, 5, 3, 6])
    ("row-major layout: " <> show (VS.toList mat))

  -- wide frame: k=100 columns of 5 rows, cell (i,j) holds 100*i + j,
  -- which in row-major layout equals its own flat index — checks the
  -- per-cell column lookup and the layout at width in one identity
  let wideCols =
        [ (T.pack ("c" <> show j), col [fromIntegral (100 * i + j) | i <- [0 .. 4 :: Int]])
        | j <- [0 .. 99 :: Int]
        ]
  (wm, wmat) <- either (fail . show) pure (columnsToMatrix (fromNamedColumns wideCols) (map fst wideCols))
  expect (wm == 5) ("wide matrix rows: " <> show wm)
  expect (VS.length wmat == 500) ("wide matrix size: " <> show (VS.length wmat))
  expect (wmat == VS.generate 500 fromIntegral)
    "wide matrix cells differ from their flat index"

  putStrLn "keel-bridge-test: round-trip, refusals and layout all verified"

-- lightweight constructor tags for refusal checks
data ErrTag = ColumnNotFound' | ColumnHasNulls' | ColumnTypeMismatch' | ColumnLengthMismatch'

isLeft :: Either BridgeError a -> ErrTag -> Bool
isLeft (Left e) tag = case (e, tag) of
  (ColumnNotFound _, ColumnNotFound') -> True
  (ColumnHasNulls _ _, ColumnHasNulls') -> True
  (ColumnTypeMismatch _ _, ColumnTypeMismatch') -> True
  (ColumnLengthMismatch {}, ColumnLengthMismatch') -> True
  _ -> False
isLeft (Right _) _ = False
