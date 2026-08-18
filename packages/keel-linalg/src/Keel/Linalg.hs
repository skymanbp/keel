-- | Dense linear algebra over 'VS.Vector' buffers, executed by a
-- runtime-loaded OpenBLAS backend (see "Keel.Linalg.Backend").
--
-- Everything runs in 'IO' against an explicit 'Backend' handle — the
-- immutable-pin discipline: no global state, no backend swapping under
-- a pure API, results attributable to exactly one backend build.
--
-- Matrices are dense, row-major, compact (leading dimension = column
-- count). Dimensions are validated eagerly; a mismatch throws
-- 'DimensionMismatch' before any foreign call.
module Keel.Linalg
  ( -- * Backend
    Backend
  , BackendError (..)
  , backendConfig
  , openBackend
  , openBackendWith
  , closeBackend

    -- * Errors
  , LinalgError (..)

    -- * Level 1
  , ddot

    -- * Level 3
  , Transpose (..)
  , dgemm

    -- * LAPACK drivers
  , dgesv
  ) where

import Control.Exception (Exception, throwIO)
import Control.Monad (unless)
import Data.Vector.Storable qualified as VS
import Data.Vector.Storable.Mutable qualified as VSM
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, Ptr)

import Keel.Dyn (capOps)
import Keel.Linalg.Backend

-- | Programming errors — thrown, never returned. Data-dependent
-- conditions (like a singular matrix) come back as @Either@ instead.
data LinalgError
  = DimensionMismatch String
    -- ^ Operand sizes disagree; raised before any foreign call.
  | LapackBadArgument String Int
    -- ^ LAPACKE rejected argument /i/ (negative @info@) despite our
    -- validation — indicates a bug in these bindings, please report.
  deriving (Eq, Show)

instance Exception LinalgError

-- | Whether an operand is used as itself or its transpose.
data Transpose = NoTrans | Trans
  deriving (Eq, Show)

-- CBLAS enum values (frozen ABI, cblas.h)
cblasRowMajor :: CInt
cblasRowMajor = 101

transToC :: Transpose -> CInt
transToC NoTrans = 111
transToC Trans = 112

foreign import ccall safe "dynamic"
  callDdot
    :: FunPtr (CInt -> Ptr Double -> CInt -> Ptr Double -> CInt -> IO Double)
    -> CInt -> Ptr Double -> CInt -> Ptr Double -> CInt -> IO Double

foreign import ccall safe "dynamic"
  callDgemm
    :: FunPtr
         (  CInt -> CInt -> CInt
         -> CInt -> CInt -> CInt
         -> Double -> Ptr Double -> CInt
         -> Ptr Double -> CInt
         -> Double -> Ptr Double -> CInt
         -> IO ()
         )
    -> CInt -> CInt -> CInt
    -> CInt -> CInt -> CInt
    -> Double -> Ptr Double -> CInt
    -> Ptr Double -> CInt
    -> Double -> Ptr Double -> CInt
    -> IO ()

-- | Dot product @x . y@ (@cblas_ddot@, unit strides).
ddot :: Backend -> VS.Vector Double -> VS.Vector Double -> IO Double
ddot be x y = do
  unless (VS.length x == VS.length y) . throwIO . DimensionMismatch $
    "ddot: lengths " <> show (VS.length x) <> " /= " <> show (VS.length y)
  VS.unsafeWith x $ \px ->
    VS.unsafeWith y $ \py ->
      callDdot (opDdot (capOps be)) (fromIntegral (VS.length x)) px 1 py 1

-- | @alpha * op(A) * op(B)@ (@cblas_dgemm@ with @beta = 0@ over compact
-- row-major buffers): @op(A)@ is @m x k@, @op(B)@ is @k x n@, the
-- result is @m x n@. @A@ itself is stored @m x k@ under 'NoTrans' and
-- @k x m@ under 'Trans' (likewise @B@).
dgemm
  :: Backend
  -> Transpose -- ^ op(A)
  -> Transpose -- ^ op(B)
  -> Int -- ^ m
  -> Int -- ^ n
  -> Int -- ^ k
  -> Double -- ^ alpha
  -> VS.Vector Double -- ^ A
  -> VS.Vector Double -- ^ B
  -> IO (VS.Vector Double)
dgemm be ta tb m n k alpha a b = do
  unless (VS.length a == m * k) . throwIO . DimensionMismatch $
    "dgemm: A has " <> show (VS.length a) <> " elements, want m*k = " <> show (m * k)
  unless (VS.length b == k * n) . throwIO . DimensionMismatch $
    "dgemm: B has " <> show (VS.length b) <> " elements, want k*n = " <> show (k * n)
  let lda = fromIntegral (if ta == NoTrans then k else m)
      ldb = fromIntegral (if tb == NoTrans then n else k)
      ldc = fromIntegral n
  c <- VSM.new (m * n)
  VS.unsafeWith a $ \pa ->
    VS.unsafeWith b $ \pb ->
      VSM.unsafeWith c $ \pc ->
        callDgemm (opDgemm (capOps be))
          cblasRowMajor (transToC ta) (transToC tb)
          (fromIntegral m) (fromIntegral n) (fromIntegral k)
          alpha pa lda pb ldb 0 pc ldc
  VS.unsafeFreeze c

foreign import ccall safe "dynamic"
  callDgesv
    :: FunPtr
         (  CInt -> CInt -> CInt
         -> Ptr Double -> CInt
         -> Ptr CInt
         -> Ptr Double -> CInt
         -> IO CInt
         )
    -> CInt -> CInt -> CInt
    -> Ptr Double -> CInt
    -> Ptr CInt
    -> Ptr Double -> CInt
    -> IO CInt

-- | Solve @A X = B@ for square @A@ via LU with partial pivoting
-- (@LAPACKE_dgesv@). @A@ is @n x n@, @B@ is @n x nrhs@, both row-major
-- compact; inputs are copied, not overwritten. @Left i@ reports exact
-- singularity detected at @U(i,i)@ (1-based) — a data condition, not an
-- exception. This driver requires the backend; there is no pure-Haskell
-- fallback.
dgesv
  :: Backend
  -> Int -- ^ n
  -> Int -- ^ nrhs
  -> VS.Vector Double -- ^ A
  -> VS.Vector Double -- ^ B
  -> IO (Either Int (VS.Vector Double))
dgesv be n nrhs a b = do
  unless (VS.length a == n * n) . throwIO . DimensionMismatch $
    "dgesv: A has " <> show (VS.length a) <> " elements, want n*n = " <> show (n * n)
  unless (VS.length b == n * nrhs) . throwIO . DimensionMismatch $
    "dgesv: B has " <> show (VS.length b) <> " elements, want n*nrhs = " <> show (n * nrhs)
  aCopy <- VS.thaw a
  bCopy <- VS.thaw b
  ipiv <- VSM.new n :: IO (VSM.IOVector CInt)
  info <-
    VSM.unsafeWith aCopy $ \pa ->
      VSM.unsafeWith bCopy $ \pb ->
        VSM.unsafeWith ipiv $ \pp ->
          callDgesv (opDgesv (capOps be))
            lapackRowMajor (fromIntegral n) (fromIntegral nrhs)
            pa (fromIntegral n) pp pb (fromIntegral nrhs)
  case compare info 0 of
    EQ -> Right <$> VS.unsafeFreeze bCopy
    GT -> pure (Left (fromIntegral info))
    LT -> throwIO (LapackBadArgument "dgesv" (negate (fromIntegral info)))

-- LAPACK_ROW_MAJOR (lapacke.h, frozen ABI)
lapackRowMajor :: CInt
lapackRowMajor = 101
