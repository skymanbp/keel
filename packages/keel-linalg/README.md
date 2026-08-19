# keel-linalg

Dense linear algebra with zero build-time native dependencies: CBLAS
level-3 and LAPACKE drivers over `Storable` vectors, resolved at run
time from an OpenBLAS shared library through
[keel-dyn](https://hackage.haskell.org/package/keel-dyn).

```haskell
import Keel.Linalg

main :: IO ()
main = do
  Right be <- loadBackend defaultOpenBlasSpec
  -- row-major dgemm: C := A(2x3) * B(3x2)
  c <- dgemm be NoTrans NoTrans 2 2 3 1.0 a b 0.0
  print c
```

The backend is located by the documented keel search policy
(`KEEL_OPENBLAS` env override, the per-user keel data dir — populated
by `keel setup openblas` from the umbrella package — then the system
search path), probed for ILP64 misconfiguration via
`openblas_get_config`, and pinned immutably in a `Backend` handle:
no global state, no backend swapping under a pure API.

Every driver is checked against numpy/scipy oracles in the test suite
(GEMM, LU/solve/inverse, Cholesky, QR, SVD, symmetric and general
eigenvalues, least squares — agreement within 1e-10).

Part of the keel workspace — see the
[project repository](https://github.com/skymanbp/keel).
