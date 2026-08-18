-- | Numerical oracle: cross-check keel-linalg results against numpy
-- (LAPACK\/BLAS via a different build) out of process.
--
-- * dgemm on deterministic pseudo-random 40x30 . 30x20: every element
--   within 1e-10 relative error of @A \@ B@;
-- * dgesv on a diagonally-boosted 50x50 with 3 right-hand sides: within
--   1e-10 relative error of @np.linalg.solve@;
-- * dgesv on the 8x8 Hilbert matrix (cond ~1e10): solutions are NOT
--   comparable at 1e-10 across libraries (forward error scales with the
--   condition number), so the gate is the backward error
--   @||Ax-b|| \/ (||A|| ||x|| + ||b||) <= 1e-12@ — what a correct LU
--   solve guarantees regardless of conditioning.
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
-- Deterministic input generation (fixed-seed LCG; identical on every
-- run and machine, so oracle failures are reproducible)

lcg :: Word64 -> Word64
lcg x = 6364136223846793005 * x + 1442695040888963407

-- | @n@ doubles in [-1, 1).
randDoubles :: Word64 -> Int -> [Double]
randDoubles seed n = take n (map toD (drop 1 (iterate lcg seed)))
  where
    toD w = fromIntegral (w `shiftR` 11) / 4503599627370496 - 1 -- 2^52

-- ---------------------------------------------------------------------
-- numpy as reference implementation

runNumpy :: String -> [Double] -> IO (Maybe [Double])
runNumpy script input = do
  r <- try (readProcessWithExitCode "python" ["-c", script] (unwords (map show input)))
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, out, _) -> Just (map read (words out))
    _ -> Nothing

numpyAvailable :: IO Bool
numpyAvailable = do
  r <- try (readProcessWithExitCode "python" ["-c", "import numpy"] "")
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, _, _) -> True
    _ -> False

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
  -- 1. dgemm vs numpy, random rectangular
  let (m, k, n) = (40, 30, 20)
      a = VS.fromList (randDoubles 42 (m * k))
      b = VS.fromList (randDoubles 1337 (k * n))
  ours <- dgemm be NoTrans NoTrans m n k 1 a b
  ref <- runNumpy
    "import sys, numpy as np\n\
    \d = np.array([float(t) for t in sys.stdin.read().split()])\n\
    \m, k, n = 40, 30, 20\n\
    \A = d[:m*k].reshape(m, k); B = d[m*k:].reshape(k, n)\n\
    \print('\\n'.join('%.17g' % v for v in (A @ B).ravel()))\n"
    (VS.toList a <> VS.toList b)
  case ref of
    Nothing -> fail "numpy dgemm reference run failed"
    Just r -> checkAgainst "dgemm" 1e-10 (VS.toList ours) r
  putStrLn ("oracle: dgemm " <> show (m, k, n) <> " within 1e-10 of numpy")

  -- 2. dgesv vs numpy, well-conditioned random (diagonal boost)
  let nn = 50
      nrhs = 3
      rawA = randDoubles 7 (nn * nn)
      aSq = VS.fromList
        [ v + (if i `div` nn == i `mod` nn then fromIntegral nn else 0)
        | (i, v) <- zip [0 :: Int ..] rawA
        ]
      rhs = VS.fromList (randDoubles 99 (nn * nrhs))
  solved <- either (\i -> fail ("random system reported singular at " <> show i)) pure
        =<< dgesv be nn nrhs aSq rhs
  refX <- runNumpy
    "import sys, numpy as np\n\
    \d = np.array([float(t) for t in sys.stdin.read().split()])\n\
    \n, nrhs = 50, 3\n\
    \A = d[:n*n].reshape(n, n); B = d[n*n:].reshape(n, nrhs)\n\
    \print('\\n'.join('%.17g' % v for v in np.linalg.solve(A, B).ravel()))\n"
    (VS.toList aSq <> VS.toList rhs)
  case refX of
    Nothing -> fail "numpy solve reference run failed"
    Just r -> checkAgainst "dgesv" 1e-10 (VS.toList solved) r
  putStrLn "oracle: dgesv 50x50 within 1e-10 of numpy"

  -- 3. Hilbert 8x8 (ill-conditioned): backward-error gate
  let h = 8
      hilbert = VS.fromList
        [ 1 / fromIntegral (i + j + 1)
        | i <- [0 .. h - 1], j <- [0 :: Int .. h - 1]
        ]
      -- b = row sums, so x_true = ones (up to conditioning)
      bvec = VS.fromList
        [ sum [1 / fromIntegral (i + j + 1) | j <- [0 :: Int .. h - 1]]
        | i <- [0 .. h - 1]
        ]
  hx <- either (\i -> fail ("Hilbert reported singular at " <> show i)) pure
        =<< dgesv be h 1 hilbert bvec
  ax <- dgemm be NoTrans NoTrans h 1 h 1 hilbert hx
  let residual = VS.maximum (VS.map abs (VS.zipWith (-) ax bvec))
      normA = VS.maximum (VS.map abs hilbert)
      normX = VS.maximum (VS.map abs hx)
      normB = VS.maximum (VS.map abs bvec)
      backward = residual / (normA * normX + normB)
  expect (backward <= 1e-12)
    ("Hilbert backward error " <> show backward <> " > 1e-12")
  putStrLn ("oracle: Hilbert 8x8 backward error " <> show backward <> " <= 1e-12")

  putStrLn "keel-linalg-oracle: all oracle checks passed"
