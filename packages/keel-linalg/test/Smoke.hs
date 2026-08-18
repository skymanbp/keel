-- | Smoke tests against a real OpenBLAS: backend discovery + probe
-- machinery, then exact-value checks (small integer inputs stay exact
-- in double precision, so equality is legitimate here).
--
-- Discovery order: 'openBackend' (env \/ data dir \/ system search); if
-- that misses, a python site-packages sweep for a standard-symbol
-- OpenBLAS wheel DLL (faiss ships one on Windows) is tried through the
-- @KEEL_OPENBLAS@ override. No backend found => SKIP, unless
-- @KEEL_LINALG_REQUIRE_OPENBLAS@ is set (publish-stage CI sets it,
-- with a stock OpenBLAS installed).
module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Data.Vector.Storable qualified as VS
import System.Environment (lookupEnv, setEnv)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

import Keel.Linalg
import Keel.Linalg.Backend (isILP64Config)

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

-- Ask python where a wheel-bundled, standard-symbol OpenBLAS lives.
-- (numpy/scipy wheels are symbol-renamed and useless here; faiss's is a
-- stock build.)
findWheelOpenblas :: IO (Maybe FilePath)
findWheelOpenblas = do
  r <- try (readProcessWithExitCode "python" ["-c", script] "")
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, out, _) | not (null cleaned) -> Just cleaned
      where cleaned = filter (`notElem` "\r\n") out
    _ -> Nothing
  where
    script =
      "import glob, os, sysconfig\n\
      \sp = sysconfig.get_paths()['purelib']\n\
      \g = glob.glob(os.path.join(sp, 'faiss_cpu.libs', 'libopenblas*.dll'))\n\
      \print(g[0] if g else '')\n"

main :: IO ()
main = do
  -- unit-test the ILP64 classifier on both polarities first (no backend
  -- needed; the local wheel is LP64 so only strings can cover this)
  expect (isILP64Config "OpenBLAS 0.3.30 USE64BITINT DYNAMIC_ARCH NO_AFFINITY")
    "ILP64 config not detected"
  expect (not (isILP64Config "OpenBLAS 0.3.30 DYNAMIC_ARCH NO_AFFINITY Cooperlake"))
    "LP64 config misclassified as ILP64"

  first <- openBackend
  opened <- case first of
    Right be -> pure (Just be)
    Left _ -> do
      wheel <- findWheelOpenblas
      case wheel of
        Nothing -> pure Nothing
        Just dll -> do
          setEnv "KEEL_OPENBLAS" dll
          either (const Nothing) Just <$> openBackend
  required <- lookupEnv "KEEL_LINALG_REQUIRE_OPENBLAS"
  case opened of
    Nothing -> case required of
      Just v | v /= "" && v /= "0" ->
        fail "KEEL_LINALG_REQUIRE_OPENBLAS set but no usable OpenBLAS found"
      _ -> putStrLn "keel-linalg-smoke: SKIP - no standard-symbol OpenBLAS on this machine"
    Just be -> run be

run :: Backend -> IO ()
run be = do
  putStrLn ("backend: " <> backendConfig be)
  expect (take 8 (backendConfig be) == "OpenBLAS") "config string does not name OpenBLAS"

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

  closeBackend be
  putStrLn "keel-linalg-smoke: all checks passed against a real OpenBLAS"
