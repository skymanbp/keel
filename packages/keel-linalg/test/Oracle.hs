-- | Numerical oracle: cross-check keel-linalg results against numpy
-- (LAPACK\/BLAS via a different build) out of process, on deterministic
-- fixed-seed inputs.
--
-- Well-conditioned cases gate at 1e-10 relative error; the Hilbert 8x8
-- system (cond ~1e10) gates on backward error instead — forward error
-- is condition-limited across libraries, backward error is what a
-- correct LU solve guarantees regardless of conditioning.
--
-- Needs python+numpy (reference values) and an OpenBLAS backend; either
-- missing => SKIP unless @KEEL_LINALG_REQUIRE_ORACLE@ is set (CI does).
module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless)
import Data.Bits (shiftR)
import Data.Vector.Storable qualified as VS
import Data.Word (Word64)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

import Keel.Linalg
import TestBackend (withTestBackend)

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

-- ---------------------------------------------------------------------
-- Deterministic input generation

lcg :: Word64 -> Word64
lcg x = 6364136223846793005 * x + 1442695040888963407

-- | @n@ doubles in [-1, 1).
randDoubles :: Word64 -> Int -> [Double]
randDoubles seed n = take n (map toD (drop 1 (iterate lcg seed)))
  where
    toD w = fromIntegral (w `shiftR` 11) / 4503599627370496 - 1 -- 2^52

-- | Add @n@ to the diagonal of a row-major @n x n@ matrix.
diagBoost :: Int -> VS.Vector Double -> VS.Vector Double
diagBoost n =
  VS.imap (\i v -> if i `div` n == i `mod` n then v + fromIntegral n else v)

-- ---------------------------------------------------------------------
-- numpy as reference implementation

runNumpy :: String -> [Double] -> IO [Double]
runNumpy script input = do
  r <- try (readProcessWithExitCode "python" ["-c", script] (unwords (map show input)))
        :: IO (Either IOException (ExitCode, String, String))
  case r of
    Right (ExitSuccess, out, _) -> pure (map read (words out))
    _ -> fail "numpy reference run failed"

numpyAvailable :: IO Bool
numpyAvailable = do
  r <- try (readProcessWithExitCode "python" ["-c", "import numpy"] "")
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, _, _) -> True
    _ -> False

-- Script builders: stdin carries the flattened operands, sizes are
-- baked into the source, output is one '%.17g' per line.
pyHeader :: String
pyHeader =
  "import sys, numpy as np\n\
  \d = np.array([float(t) for t in sys.stdin.read().split()])\n"

pyEmit :: String -> String
pyEmit expr = "print('\\n'.join('%.17g' % v for v in (" <> expr <> ").ravel()))\n"

matmulScript :: Int -> Int -> Int -> String
matmulScript m k n =
  pyHeader
    <> "m, k, n = " <> show m <> ", " <> show k <> ", " <> show n <> "\n"
    <> "A = d[:m*k].reshape(m, k); B = d[m*k:].reshape(k, n)\n"
    <> pyEmit "A @ B"

solveScript :: Int -> Int -> String
solveScript n nrhs =
  pyHeader
    <> "n, nrhs = " <> show n <> ", " <> show nrhs <> "\n"
    <> "A = d[:n*n].reshape(n, n); B = d[n*n:].reshape(n, nrhs)\n"
    <> pyEmit "np.linalg.solve(A, B)"

triSolveScript :: Int -> Int -> String
triSolveScript n nrhs =
  pyHeader
    <> "n, nrhs = " <> show n <> ", " <> show nrhs <> "\n"
    <> "A = np.tril(d[:n*n].reshape(n, n)); B = d[n*n:].reshape(n, nrhs)\n"
    <> pyEmit "np.linalg.solve(A, B)"

lstsqScript :: Int -> Int -> Int -> String
lstsqScript m n nrhs =
  pyHeader
    <> "m, n, nrhs = " <> show m <> ", " <> show n <> ", " <> show nrhs <> "\n"
    <> "A = d[:m*n].reshape(m, n); B = d[m*n:].reshape(m, nrhs)\n"
    <> pyEmit "np.linalg.lstsq(A, B, rcond=None)[0]"

invScript :: Int -> String
invScript n =
  pyHeader
    <> "n = " <> show n <> "\n"
    <> pyEmit "np.linalg.inv(d.reshape(n, n))"

cholScript :: Int -> String
cholScript n =
  pyHeader
    <> "n = " <> show n <> "\n"
    <> pyEmit "np.linalg.cholesky(d.reshape(n, n))"

relErr :: Double -> Double -> Double
relErr got ref = abs (got - ref) / max 1 (abs ref)

checkAgainst :: String -> Double -> [Double] -> [Double] -> IO ()
checkAgainst label tol got ref = do
  expect (length got == length ref)
    (label <> ": length " <> show (length got) <> " /= " <> show (length ref))
  forM_ (zip3 [0 :: Int ..] got ref) $ \(i, g, r) ->
    expect (relErr g r <= tol)
      (label <> "[" <> show i <> "]: got " <> show g <> ", numpy " <> show r
        <> ", rel " <> show (relErr g r))

unwrap :: String -> Either Int a -> IO a
unwrap ctx = either (\i -> fail (ctx <> ": unexpected info " <> show i)) pure

-- ---------------------------------------------------------------------

main :: IO ()
main = do
  np <- numpyAvailable
  required <- lookupEnv "KEEL_LINALG_REQUIRE_ORACLE"
  if not np
    then case required of
      Just v | v /= "" && v /= "0" ->
        fail "KEEL_LINALG_REQUIRE_ORACLE set but python+numpy unavailable"
      _ -> putStrLn "keel-linalg-oracle: SKIP - no python+numpy on this machine"
    else withTestBackend "KEEL_LINALG_REQUIRE_ORACLE" run

run :: Backend -> IO ()
run be = do
  -- 1. dgemm, random rectangular
  let (m, k, n) = (40, 30, 20)
      a = VS.fromList (randDoubles 42 (m * k))
      b = VS.fromList (randDoubles 1337 (k * n))
  ours <- dgemm be NoTrans NoTrans m n k 1 a b
  ref <- runNumpy (matmulScript m k n) (VS.toList a <> VS.toList b)
  checkAgainst "dgemm" 1e-10 (VS.toList ours) ref
  putStrLn "oracle: dgemm 40x30.30x20 within 1e-10 of numpy"

  -- 2. dgesv, well-conditioned random (diagonal boost)
  let nn = 50
      nrhs = 3
      aSq = diagBoost nn (VS.fromList (randDoubles 7 (nn * nn)))
      rhs = VS.fromList (randDoubles 99 (nn * nrhs))
  solved <- unwrap "dgesv" =<< dgesv be nn nrhs aSq rhs
  refX <- runNumpy (solveScript nn nrhs) (VS.toList aSq <> VS.toList rhs)
  checkAgainst "dgesv" 1e-10 (VS.toList solved) refX
  putStrLn "oracle: dgesv 50x50 within 1e-10 of numpy"

  -- 3. Hilbert 8x8 (ill-conditioned): backward-error gate
  let h = 8
      hilbert = VS.fromList
        [ 1 / fromIntegral (i + j + 1)
        | i <- [0 .. h - 1], j <- [0 :: Int .. h - 1]
        ]
      bvec = VS.fromList
        [ sum [1 / fromIntegral (i + j + 1) | j <- [0 :: Int .. h - 1]]
        | i <- [0 .. h - 1]
        ]
  hx <- unwrap "dgesv(hilbert)" =<< dgesv be h 1 hilbert bvec
  ax <- dgemm be NoTrans NoTrans h 1 h 1 hilbert hx
  let residual = VS.maximum (VS.map abs (VS.zipWith (-) ax bvec))
      backward = residual
        / (VS.maximum (VS.map abs hilbert) * VS.maximum (VS.map abs hx)
            + VS.maximum (VS.map abs bvec))
  expect (backward <= 1e-12)
    ("Hilbert backward error " <> show backward <> " > 1e-12")
  putStrLn ("oracle: Hilbert 8x8 backward error " <> show backward <> " <= 1e-12")

  -- 4. dposv on a real SPD matrix (M M^T + n I), vs numpy solve
  let sn = 30
      mMat = VS.fromList (randDoubles 11 (sn * sn))
      srhs = VS.fromList (randDoubles 13 (sn * 2))
  mmT <- dgemm be NoTrans Trans sn sn sn 1 mMat mMat
  let spd = diagBoost sn mmT
  psol <- unwrap "dposv" =<< dposv be Lower sn 2 spd srhs
  pref <- runNumpy (solveScript sn 2) (VS.toList spd <> VS.toList srhs)
  checkAgainst "dposv" 1e-10 (VS.toList psol) pref
  putStrLn "oracle: dposv 30x30 SPD within 1e-10 of numpy"

  -- 5. dgels, overdetermined 60x10, vs numpy lstsq
  let (gm, gn, gr) = (60, 10, 2)
      ga = VS.fromList (randDoubles 17 (gm * gn))
      gb = VS.fromList (randDoubles 19 (gm * gr))
  gsol <- unwrap "dgels" =<< dgels be gm gn gr ga gb
  gref <- runNumpy (lstsqScript gm gn gr) (VS.toList ga <> VS.toList gb)
  checkAgainst "dgels" 1e-10 (VS.toList gsol) gref
  putStrLn "oracle: dgels 60x10 within 1e-10 of numpy lstsq"

  -- 6. dgetrf + dgetri vs numpy inv, diag-boosted 40x40
  let inn = 40
      ia = diagBoost inn (VS.fromList (randDoubles 21 (inn * inn)))
  (lu, piv) <- unwrap "dgetrf" =<< dgetrf be inn inn ia
  inv <- unwrap "dgetri" =<< dgetri be inn lu piv
  iref <- runNumpy (invScript inn) (VS.toList ia)
  checkAgainst "dgetri" 1e-10 (VS.toList inv) iref
  putStrLn "oracle: dgetrf+dgetri 40x40 within 1e-10 of numpy inv"

  -- 7. dpotrf (lower) vs numpy cholesky — lower triangle only (the
  -- upper triangle of our output keeps the input's bytes by contract)
  chol <- unwrap "dpotrf" =<< dpotrf be Lower sn spd
  cref <- runNumpy (cholScript sn) (VS.toList spd)
  forM_ [(i, j) | i <- [0 .. sn - 1], j <- [0 .. i]] $ \(i, j) -> do
    let g = chol VS.! (i * sn + j)
        r = cref !! (i * sn + j)
    expect (relErr g r <= 1e-10)
      ("dpotrf[" <> show (i, j) <> "]: got " <> show g <> ", numpy " <> show r)
  putStrLn "oracle: dpotrf 30x30 lower triangle within 1e-10 of numpy cholesky"

  -- 8. dtrtrs on that Cholesky factor vs numpy solve over np.tril
  let trhs = VS.fromList (randDoubles 23 sn)
  tsol <- unwrap "dtrtrs" =<< dtrtrs be Lower NoTrans NonUnit sn 1 chol trhs
  tref <- runNumpy (triSolveScript sn 1) (VS.toList chol <> VS.toList trhs)
  checkAgainst "dtrtrs" 1e-10 (VS.toList tsol) tref
  putStrLn "oracle: dtrtrs 30x30 within 1e-10 of numpy"

  putStrLn "keel-linalg-oracle: all oracle checks passed"
