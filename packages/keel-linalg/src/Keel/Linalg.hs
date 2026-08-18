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
  ) where

import Control.Exception (Exception, throwIO)
import Control.Monad (unless)
import Data.Vector.Storable qualified as VS
import Data.Vector.Storable.Mutable qualified as VSM
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, Ptr)

import Keel.Dyn (capOps)
import Keel.Linalg.Backend

-- | Argument validation failures, thrown before any foreign call.
newtype LinalgError = DimensionMismatch String
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
