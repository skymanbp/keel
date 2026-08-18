-- | The explicit frame ↔ buffer copy: dataframe 'Column's to
-- 'VS.Vector' buffers (ready for keel-linalg \/ keel-abi) and back.
--
-- This module is keel's ONLY point of contact with the dataframe stack,
-- and it is honest about the cost: every conversion here is an O(n)
-- copy — dataframe's unboxed columns and Storable vectors are different
-- memory representations, exactly the trade numpy↔pandas makes. No API
-- here pretends a zero-copy path exists where the representation cannot
-- provide one.
--
-- Nulls are refused, not imputed: a column with missing values raises
-- 'ColumnHasNulls' — fill or drop them with dataframe's own operations
-- first, where that decision belongs.
module Keel.Bridge
  ( BridgeError (..)
  , columnToStorable
  , columnsToMatrix
  , storableToColumn
  ) where

import Data.Text qualified as T
import Data.Vector.Generic qualified as VG
import Data.Vector.Storable qualified as VS

import DataFrame.Internal.Column
  ( Column
  , columnLength
  , fromUnboxedVector
  , numElements
  , toUnboxedVector
  )
import DataFrame.Internal.DataFrame (DataFrame, getColumn)

-- | Why a frame ↔ buffer conversion was refused.
data BridgeError
  = ColumnNotFound T.Text
    -- ^ No column of that name in the frame.
  | ColumnHasNulls T.Text Int
    -- ^ The column has this many missing values; handle them in
    -- dataframe first (fill\/drop) — the bridge never imputes.
  | ColumnTypeMismatch T.Text String
    -- ^ The column does not hold @Double@s (upstream's own type error
    -- is carried verbatim).
  | ColumnLengthMismatch T.Text Int Int
    -- ^ (column, expected rows, actual rows) while assembling a matrix.
    -- Defensive: dataframe pads short columns with nulls on insert, so
    -- columns from one frame are always equal-length (a padded column
    -- trips 'ColumnHasNulls' first); this guards the invariant anyway.
  deriving (Eq, Show)

-- | O(n) copy of a @Double@ column out of a frame into a Storable
-- buffer.
columnToStorable :: DataFrame -> T.Text -> Either BridgeError (VS.Vector Double)
columnToStorable df name = do
  col <- maybe (Left (ColumnNotFound name)) Right (getColumn name df)
  let nulls = columnLength col - numElements col
  if nulls > 0
    then Left (ColumnHasNulls name nulls)
    else case toUnboxedVector col of
      Left e -> Left (ColumnTypeMismatch name (show e))
      Right vu -> Right (VG.convert vu)

-- | O(n·k) copy of @k@ same-length @Double@ columns into one row-major
-- @rows × k@ matrix (the layout every keel-linalg driver takes).
-- Returns the row count alongside the buffer.
columnsToMatrix :: DataFrame -> [T.Text] -> Either BridgeError (Int, VS.Vector Double)
columnsToMatrix df names = do
  cols <- traverse (\n -> (,) n <$> columnToStorable df n) names
  case cols of
    [] -> Right (0, VS.empty)
    (_, c0) : rest -> do
      let m = VS.length c0
      mapM_
        ( \(n, c) ->
            if VS.length c == m
              then Right ()
              else Left (ColumnLengthMismatch n m (VS.length c))
        )
        rest
      let k = length cols
          vecs = map snd cols
      Right (m, VS.generate (m * k) (\i -> (vecs !! (i `mod` k)) VS.! (i `div` k)))

-- | O(n) copy of a Storable buffer back into a (null-free) dataframe
-- column, e.g. to insert a keel-linalg result as a new column.
storableToColumn :: VS.Vector Double -> Column
storableToColumn = fromUnboxedVector . VG.convert
