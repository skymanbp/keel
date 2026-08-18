# Tutorial 4 — dataframe columns into real linear algebra

keel deliberately does **not** ship a dataframe — the
[DataHaskell `dataframe`](https://hackage.haskell.org/package/dataframe)
stack owns that tier. What keel adds is the missing floor underneath it:
`Keel.Bridge` copies columns into `Storable` buffers (honestly — it *is*
an O(n) copy, the same trade numpy↔pandas makes), and `keel-linalg` runs
LAPACK on them through a runtime-loaded OpenBLAS.

## One-time setup

```
$ keel setup blas     # Windows; apt/brew elsewhere (doctor tells you)
$ keel doctor
[ok] keel-linalg (OpenBLAS)  OpenBLAS 0.3.30 ...  @ .../keel/native/openblas/...
```

## Least squares over frame columns

Fit `price ~ area + rooms` by QR least squares:

```haskell
import Data.Text qualified as T
import Data.Vector.Storable qualified as VS
import DataFrame.Internal.DataFrame (DataFrame, insertColumn)
import Keel.Bridge
import Keel.Linalg

fit :: DataFrame -> IO (Either String (VS.Vector Double))
fit df = do
  Right be <- openBackend                      -- the immutable pin
  case ( columnsToMatrix df [T.pack "area", T.pack "rooms"]
       , columnToStorable df (T.pack "price") ) of
    (Right (m, a), Right b) -> do
      r <- dgels be m 2 1 a b                  -- min ||A x - b||, QR
      closeBackend be
      pure $ case r of
        Right x -> Right x                     -- 2 coefficients
        Left i  -> Left ("rank deficient at " <> show i)
    (Left e, _) -> pure (Left (show e))
    (_, Left e) -> pure (Left (show e))
```

`columnsToMatrix` produces exactly the row-major layout every
keel-linalg driver takes, and refuses dishonest inputs: a column with
nulls is a `ColumnHasNulls` error (fill or drop them with dataframe's
own operations first — imputation is a modeling decision, not a
marshalling one), and a non-`Double` column is a `ColumnTypeMismatch`.

## Results back into the frame

```haskell
--  e.g. residuals computed with dgemm, back as a column:
let df' = insertColumn (T.pack "residual") (storableToColumn resid) df
```

## Why the results are trustworthy

Every keel-linalg driver (solve, least squares, SVD, eigen, QR,
Cholesky, inverse) is cross-checked in CI against numpy/LAPACK to
**1e-10 relative error** on random inputs; ill-conditioned systems are
gated on backward error (the thing a correct solve actually guarantees);
SVD/eigen factors are verified through sign-free reconstruction
residuals. The backend pin also guards the classic silent-corruption
traps: ILP64 builds are refused, symbol-renamed wheels are refused, and
the BLAS thread pool is pinned to 1 unless you set
`OPENBLAS_NUM_THREADS` yourself.

*Working code the pieces come from:*
[`packages/keel/test/BridgeTest.hs`](../../packages/keel/test/BridgeTest.hs)
(bridge round-trip, refusals, row-major layout — including that
dataframe pads short columns with nulls, which the bridge catches),
[`packages/keel-linalg/test/Smoke.hs`](../../packages/keel-linalg/test/Smoke.hs) and
[`packages/keel-linalg/test/Oracle.hs`](../../packages/keel-linalg/test/Oracle.hs)
(`dgels` against numpy `lstsq` at 1e-10). The composition above is
assembled from those verified APIs.
