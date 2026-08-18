-- | Smoke tests against a real OpenBLAS: probe machinery plus
-- exact-value checks (small integer inputs stay exact in double
-- precision, so equality is legitimate here). Backend discovery and the
-- SKIP-vs-require policy live in "TestBackend".
module Main (main) where

import Control.Exception (try)
import Control.Monad (unless)
import Data.Vector.Storable qualified as VS
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr)
import System.Environment (lookupEnv)

import Keel.Dyn (capLibrary, resolveOptional)
import Keel.Linalg
import Keel.Linalg.Backend (isILP64Config)
import TestBackend (withTestBackend)

foreign import ccall unsafe "dynamic"
  callGetNumThreads :: FunPtr (IO CInt) -> IO CInt

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

main :: IO ()
main = do
  -- unit-test the ILP64 classifier on both polarities first (no backend
  -- needed; the local wheel is LP64 so only strings can cover this)
  expect (isILP64Config "OpenBLAS 0.3.30 USE64BITINT DYNAMIC_ARCH NO_AFFINITY")
    "ILP64 config not detected"
  expect (not (isILP64Config "OpenBLAS 0.3.30 DYNAMIC_ARCH NO_AFFINITY Cooperlake"))
    "LP64 config misclassified as ILP64"

  withTestBackend "KEEL_LINALG_REQUIRE_OPENBLAS" run

run :: Backend -> IO ()
run be = do
  putStrLn ("backend: " <> backendConfig be)
  expect (take 8 (backendConfig be) == "OpenBLAS") "config string does not name OpenBLAS"

  -- thread-pin hazard: unless the user chose a thread count themselves,
  -- openBackend must have pinned the OpenBLAS pool to 1 (read back via
  -- the optional openblas_get_num_threads)
  userThreads <- lookupEnv "OPENBLAS_NUM_THREADS"
  mGet <- resolveOptional (capLibrary be) "openblas_get_num_threads"
  case (userThreads, mGet) of
    (Nothing, Just fp) -> do
      nthr <- callGetNumThreads fp
      expect (nthr == 1) ("BLAS pool not pinned to 1 thread: " <> show nthr)
    (Just _, _) -> putStrLn "note: OPENBLAS_NUM_THREADS set by user, pin check skipped"
    (Nothing, Nothing) -> putStrLn "note: openblas_get_num_threads absent, pin unverifiable"

  -- ddot: [1,2,3] . [4,5,6] = 32
  d <- ddot be (VS.fromList [1, 2, 3]) (VS.fromList [4, 5, 6])
  expect (d == 32) ("ddot: " <> show d)

  -- ddot dimension mismatch must throw before calling BLAS
  bad <- try (ddot be (VS.fromList [1, 2]) (VS.fromList [1, 2, 3]))
        :: IO (Either LinalgError Double)
  expect (either (const True) (const False) bad) "ddot length mismatch not rejected"

  -- dgemm NoTrans/NoTrans: [[1,2],[3,4]] x [[5,6],[7,8]] = [[19,22],[43,50]]
  c1 <- dgemm be NoTrans NoTrans 2 2 2 1 (VS.fromList [1, 2, 3, 4]) (VS.fromList [5, 6, 7, 8])
  expect (VS.toList c1 == [19, 22, 43, 50]) ("dgemm NN: " <> show (VS.toList c1))

  -- dgemm Trans on A: A stored [[1,3],[2,4]] (2x2), op(A) = [[1,2],[3,4]]
  c2 <- dgemm be Trans NoTrans 2 2 2 1 (VS.fromList [1, 3, 2, 4]) (VS.fromList [5, 6, 7, 8])
  expect (VS.toList c2 == [19, 22, 43, 50]) ("dgemm TN: " <> show (VS.toList c2))

  -- rectangular: (1x3) x (3x1) = [[32]], alpha = 2 -> [[64]]
  c3 <- dgemm be NoTrans NoTrans 1 1 3 2 (VS.fromList [1, 2, 3]) (VS.fromList [4, 5, 6])
  expect (VS.toList c3 == [64]) ("dgemm alpha: " <> show (VS.toList c3))

  -- dgesv: [[2,0],[0,4]] x = [3,8] -> x = [1.5, 2] (exact for powers of 2)
  s1 <- dgesv be 2 1 (VS.fromList [2, 0, 0, 4]) (VS.fromList [3, 8])
  case s1 of
    Right x -> expect (VS.toList x == [1.5, 2]) ("dgesv: " <> show (VS.toList x))
    Left i -> fail ("dgesv reported singular at " <> show i)

  -- dgesv on an exactly singular matrix reports Left, not garbage
  s2 <- dgesv be 2 1 (VS.fromList [1, 2, 2, 4]) (VS.fromList [1, 1])
  expect (either (const True) (const False) s2) "singular matrix not reported"

  -- dgesv dimension mismatch must throw before calling LAPACK
  s3 <- try (dgesv be 2 1 (VS.fromList [1, 2, 3]) (VS.fromList [1, 1]))
        :: IO (Either LinalgError (Either Int (VS.Vector Double)))
  expect (either (const True) (const False) s3) "dgesv bad dims not rejected"

  -- dposv on SPD [[4,2],[2,3]], b=[10,8]: x=[1.75,1.5] — near-equality,
  -- the Cholesky pivot sqrt(2) is irrational so the result rounds
  p1 <- unwrap "dposv" =<< dposv be Upper 2 1 (VS.fromList [4, 2, 2, 3]) (VS.fromList [10, 8])
  expect (approxEq 1e-14 (VS.toList p1) [1.75, 1.5]) ("dposv: " <> show (VS.toList p1))

  -- dposv rejects a non-positive-definite matrix
  p2 <- dposv be Upper 2 1 (VS.fromList [-1, 0, 0, 1]) (VS.fromList [1, 1])
  expect (either (const True) (const False) p2) "non-PD matrix not reported"

  -- dtrtrs lower [[2,0],[1,1]] x = [2,3] -> x=[1,2] exact
  t1 <- unwrap "dtrtrs" =<< dtrtrs be Lower NoTrans NonUnit 2 1
          (VS.fromList [2, 0, 1, 1]) (VS.fromList [2, 3])
  expect (VS.toList t1 == [1, 2]) ("dtrtrs: " <> show (VS.toList t1))

  -- dgels overdetermined 3x2, consistent system -> x=[1,2]
  g1 <- unwrap "dgels over" =<< dgels be 3 2 1
          (VS.fromList [1, 0, 0, 1, 0, 0]) (VS.fromList [1, 2, 0])
  expect (approxEq 1e-14 (VS.toList g1) [1, 2]) ("dgels over: " <> show (VS.toList g1))

  -- dgels underdetermined 1x2 minimum norm: [[1,1]] x = [4] -> x=[2,2]
  g2 <- unwrap "dgels under" =<< dgels be 1 2 1 (VS.fromList [1, 1]) (VS.fromList [4])
  expect (approxEq 1e-14 (VS.toList g2) [2, 2]) ("dgels under: " <> show (VS.toList g2))

  -- dgetrf + dgetri: inverse of diag(2,4) = diag(0.5,0.25) exact
  (lu, piv) <- unwrap "dgetrf" =<< dgetrf be 2 2 (VS.fromList [2, 0, 0, 4])
  inv <- unwrap "dgetri" =<< dgetri be 2 lu piv
  expect (VS.toList inv == [0.5, 0, 0, 0.25]) ("dgetri: " <> show (VS.toList inv))

  -- dgetrf reports exact singularity
  f2 <- dgetrf be 2 2 (VS.fromList [1, 2, 2, 4])
  expect (either (const True) (const False) f2) "dgetrf singularity not reported"

  -- dpotrf lower of diag(4,9): factor diag(2,3), zeros preserved
  ch <- unwrap "dpotrf" =<< dpotrf be Lower 2 (VS.fromList [4, 0, 0, 9])
  expect (VS.toList ch == [2, 0, 0, 3]) ("dpotrf: " <> show (VS.toList ch))

  -- dpotri from that factor: inverse diagonal [0.25, 1/9]
  pin <- unwrap "dpotri" =<< dpotri be Lower 2 ch
  expect (VS.head pin == 0.25 && abs (VS.last pin - 1 / 9) < 1e-15)
    ("dpotri: " <> show (VS.toList pin))

  -- dsyevd diag(3,1): w=[1,3] ascending; eigenvectors +/- unit basis
  (w2, v2) <- unwrap "dsyevd" =<< dsyevd be Lower 2 (VS.fromList [3, 0, 0, 1])
  expect (VS.toList w2 == [1, 3]) ("dsyevd w: " <> show (VS.toList w2))
  expect (map abs (VS.toList v2) == [0, 1, 1, 0]) ("dsyevd v: " <> show (VS.toList v2))

  -- dgesdd of diag(3,4): s = [4,3] descending exact
  (sv, _, _) <- unwrap "dgesdd" =<< dgesdd be 2 2 (VS.fromList [3, 0, 0, 4])
  expect (VS.toList sv == [4, 3]) ("dgesdd s: " <> show (VS.toList sv))

  -- dgeev of the rotation [[0,-1],[1,0]]: eigenvalues +/- i
  (wr2, wi2, _) <- unwrap "dgeev" =<< dgeev be 2 (VS.fromList [0, -1, 1, 0])
  expect (approxEq 1e-14 (VS.toList wr2) [0, 0]) ("dgeev wr: " <> show (VS.toList wr2))
  expect (approxEq 1e-14 (map abs (VS.toList wi2)) [1, 1]) ("dgeev wi: " <> show (VS.toList wi2))

  putStrLn "keel-linalg-smoke: all checks passed against a real OpenBLAS"
  where
    unwrap :: String -> Either Int a -> IO a
    unwrap ctx = either (\i -> fail (ctx <> ": unexpected info " <> show i)) pure
    approxEq tol xs ys =
      length xs == length ys && and (zipWith (\x y -> abs (x - y) <= tol) xs ys)
