-- | Dense linear algebra over 'VS.Vector' buffers, executed by a
-- runtime-loaded OpenBLAS backend (see "Keel.Linalg.Backend").
--
-- Everything runs in 'IO' against an explicit 'Backend' handle — the
-- immutable-pin discipline: no global state, no backend swapping under
-- a pure API, results attributable to exactly one backend build.
--
-- Conventions, uniform across all drivers:
--
-- * matrices are dense, row-major, compact (leading dimension = column
--   count); inputs are copied, never overwritten;
-- * dimension mismatches throw 'DimensionMismatch' before any foreign
--   call; a negative LAPACK @info@ throws 'LapackBadArgument' (a bug in
--   these bindings, not in your data);
-- * data-dependent failure (singular \/ not positive definite \/ rank
--   deficient) is @Left info@ with LAPACK's 1-based index semantics —
--   these are results, not exceptions;
-- * every driver here requires the backend; none has a pure-Haskell
--   fallback.
module Keel.Linalg
  ( -- * Backend
    Backend
  , BackendError (..)
  , backendConfig
  , openBackend
  , openBackendWith
  , closeBackend

    -- * Errors and modes
  , LinalgError (..)
  , Transpose (..)
  , Uplo (..)
  , Diag (..)

    -- * BLAS level 1
  , ddot

    -- * BLAS level 3
  , dgemm

    -- * Linear systems
  , dgesv
  , dposv
  , dtrtrs

    -- * Least squares
  , dgels

    -- * Factor \/ invert
  , dgetrf
  , dgetri
  , dpotrf
  , dpotri

    -- * SVD
  , dgesdd
  , dgesvd

    -- * Eigendecomposition
  , dsyevd
  , dgeev

    -- * QR
  , dgeqrf
  , dorgqr
  ) where

import Control.Exception (Exception, throwIO)
import Control.Monad (unless)
import Data.Vector.Storable qualified as VS
import Data.Vector.Storable.Mutable qualified as VSM
import Foreign.C.String (castCharToCChar)
import Foreign.C.Types (CChar (..), CInt (..))
import Foreign.Ptr (FunPtr, Ptr, nullPtr)

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

-- | Which triangle of a symmetric\/triangular argument is stored\/read.
data Uplo = Upper | Lower
  deriving (Eq, Show)

-- | Whether a triangular matrix has an implicit unit diagonal.
data Diag = NonUnit | UnitDiag
  deriving (Eq, Show)

-- CBLAS enum values and LAPACKE char modes (frozen ABI: cblas.h, lapacke.h)
cblasRowMajor, lapackRowMajor :: CInt
cblasRowMajor = 101
lapackRowMajor = 101

transToC :: Transpose -> CInt
transToC NoTrans = 111
transToC Trans = 112

transChar :: Transpose -> CChar
transChar NoTrans = castCharToCChar 'N'
transChar Trans = castCharToCChar 'T'

uploChar :: Uplo -> CChar
uploChar Upper = castCharToCChar 'U'
uploChar Lower = castCharToCChar 'L'

diagChar :: Diag -> CChar
diagChar NonUnit = castCharToCChar 'N'
diagChar UnitDiag = castCharToCChar 'U'

-- Shared validation / info interpretation ------------------------------

checkDim :: String -> String -> Int -> Int -> IO ()
checkDim ctx what got want =
  unless (got == want) . throwIO . DimensionMismatch $
    ctx <> ": " <> what <> " has " <> show got <> " elements, want " <> show want

-- Positive info = Left (data condition); zero = run the continuation;
-- negative = bindings bug, thrown.
interpretInfo :: String -> CInt -> IO a -> IO (Either Int a)
interpretInfo ctx info onOk = case compare info 0 of
  EQ -> Right <$> onOk
  GT -> pure (Left (fromIntegral info))
  LT -> throwIO (LapackBadArgument ctx (negate (fromIntegral info)))

-- ---------------------------------------------------------------------
-- BLAS

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
  checkDim "ddot" "y" (VS.length y) (VS.length x)
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
  checkDim "dgemm" "A" (VS.length a) (m * k)
  checkDim "dgemm" "B" (VS.length b) (k * n)
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

-- ---------------------------------------------------------------------
-- Linear systems

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

foreign import ccall safe "dynamic"
  callDposv
    :: FunPtr
         (  CInt -> CChar -> CInt -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double -> CInt
         -> IO CInt
         )
    -> CInt -> CChar -> CInt -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double -> CInt
    -> IO CInt

foreign import ccall safe "dynamic"
  callDtrtrs
    :: FunPtr
         (  CInt -> CChar -> CChar -> CChar
         -> CInt -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double -> CInt
         -> IO CInt
         )
    -> CInt -> CChar -> CChar -> CChar
    -> CInt -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double -> CInt
    -> IO CInt

-- | Solve @A X = B@ for square @A@ via LU with partial pivoting
-- (@LAPACKE_dgesv@). @A@ is @n x n@, @B@ is @n x nrhs@. @Left i@:
-- exactly singular, detected at @U(i,i)@.
dgesv
  :: Backend
  -> Int -- ^ n
  -> Int -- ^ nrhs
  -> VS.Vector Double -- ^ A
  -> VS.Vector Double -- ^ B
  -> IO (Either Int (VS.Vector Double))
dgesv be n nrhs a b = do
  checkDim "dgesv" "A" (VS.length a) (n * n)
  checkDim "dgesv" "B" (VS.length b) (n * nrhs)
  aC <- VS.thaw a
  bC <- VS.thaw b
  ipiv <- VSM.new n :: IO (VSM.IOVector CInt)
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith bC $ \pb ->
        VSM.unsafeWith ipiv $ \pp ->
          callDgesv (opDgesv (capOps be))
            lapackRowMajor (fromIntegral n) (fromIntegral nrhs)
            pa (fromIntegral n) pp pb (fromIntegral nrhs)
  interpretInfo "dgesv" info (VS.unsafeFreeze bC)

-- | Solve @A X = B@ for symmetric positive-definite @A@ via Cholesky
-- (@LAPACKE_dposv@); only the 'Uplo' triangle of @A@ is read. @Left i@:
-- the leading minor of order @i@ is not positive definite.
dposv
  :: Backend
  -> Uplo
  -> Int -- ^ n
  -> Int -- ^ nrhs
  -> VS.Vector Double -- ^ A
  -> VS.Vector Double -- ^ B
  -> IO (Either Int (VS.Vector Double))
dposv be uplo n nrhs a b = do
  checkDim "dposv" "A" (VS.length a) (n * n)
  checkDim "dposv" "B" (VS.length b) (n * nrhs)
  aC <- VS.thaw a
  bC <- VS.thaw b
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith bC $ \pb ->
        callDposv (opDposv (capOps be))
          lapackRowMajor (uploChar uplo) (fromIntegral n) (fromIntegral nrhs)
          pa (fromIntegral n) pb (fromIntegral nrhs)
  interpretInfo "dposv" info (VS.unsafeFreeze bC)

-- | Solve @op(A) X = B@ for triangular @A@ (@LAPACKE_dtrtrs@); @A@ is
-- read-only, only the 'Uplo' triangle is referenced ('UnitDiag' also
-- skips the diagonal). @Left i@: @A(i,i)@ is exactly zero.
dtrtrs
  :: Backend
  -> Uplo
  -> Transpose -- ^ op(A)
  -> Diag
  -> Int -- ^ n
  -> Int -- ^ nrhs
  -> VS.Vector Double -- ^ A
  -> VS.Vector Double -- ^ B
  -> IO (Either Int (VS.Vector Double))
dtrtrs be uplo ta diag n nrhs a b = do
  checkDim "dtrtrs" "A" (VS.length a) (n * n)
  checkDim "dtrtrs" "B" (VS.length b) (n * nrhs)
  bC <- VS.thaw b
  info <-
    VS.unsafeWith a $ \pa ->
      VSM.unsafeWith bC $ \pb ->
        callDtrtrs (opDtrtrs (capOps be))
          lapackRowMajor (uploChar uplo) (transChar ta) (diagChar diag)
          (fromIntegral n) (fromIntegral nrhs)
          pa (fromIntegral n) pb (fromIntegral nrhs)
  interpretInfo "dtrtrs" info (VS.unsafeFreeze bC)

-- ---------------------------------------------------------------------
-- Least squares

foreign import ccall safe "dynamic"
  callDgels
    :: FunPtr
         (  CInt -> CChar
         -> CInt -> CInt -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double -> CInt
         -> IO CInt
         )
    -> CInt -> CChar
    -> CInt -> CInt -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double -> CInt
    -> IO CInt

-- | Least squares \/ minimum norm via QR\/LQ (@LAPACKE_dgels@, no
-- transpose): minimizes @||A X - B||@ when @m >= n@, finds the minimum
-- norm solution when @m < n@. @A@ is @m x n@ full rank, @B@ is
-- @m x nrhs@; the result is @n x nrhs@. @Left i@: @A@ is rank
-- deficient (zero at diagonal element @i@ of the triangular factor).
dgels
  :: Backend
  -> Int -- ^ m
  -> Int -- ^ n
  -> Int -- ^ nrhs
  -> VS.Vector Double -- ^ A
  -> VS.Vector Double -- ^ B
  -> IO (Either Int (VS.Vector Double))
dgels be m n nrhs a b = do
  checkDim "dgels" "A" (VS.length a) (m * n)
  checkDim "dgels" "B" (VS.length b) (m * nrhs)
  let rows = max m n
  aC <- VS.thaw a
  -- LAPACKE wants B sized max(m,n) x nrhs: input in the first m rows,
  -- solution comes back in the first n rows (row-major, ldb = nrhs,
  -- so rows are contiguous and padding is a plain suffix)
  bPad <- VSM.new (rows * nrhs)
  VS.copy (VSM.slice 0 (m * nrhs) bPad) b
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith bPad $ \pb ->
        callDgels (opDgels (capOps be))
          lapackRowMajor (transChar NoTrans)
          (fromIntegral m) (fromIntegral n) (fromIntegral nrhs)
          pa (fromIntegral n) pb (fromIntegral nrhs)
  interpretInfo "dgels" info (VS.take (n * nrhs) <$> VS.unsafeFreeze bPad)

-- ---------------------------------------------------------------------
-- Factor / invert

foreign import ccall safe "dynamic"
  callDgetrf
    :: FunPtr (CInt -> CInt -> CInt -> Ptr Double -> CInt -> Ptr CInt -> IO CInt)
    -> CInt -> CInt -> CInt -> Ptr Double -> CInt -> Ptr CInt -> IO CInt

foreign import ccall safe "dynamic"
  callDgetri
    :: FunPtr (CInt -> CInt -> Ptr Double -> CInt -> Ptr CInt -> IO CInt)
    -> CInt -> CInt -> Ptr Double -> CInt -> Ptr CInt -> IO CInt

foreign import ccall safe "dynamic"
  callDpotrf
    :: FunPtr (CInt -> CChar -> CInt -> Ptr Double -> CInt -> IO CInt)
    -> CInt -> CChar -> CInt -> Ptr Double -> CInt -> IO CInt

foreign import ccall safe "dynamic"
  callDpotri
    :: FunPtr (CInt -> CChar -> CInt -> Ptr Double -> CInt -> IO CInt)
    -> CInt -> CChar -> CInt -> Ptr Double -> CInt -> IO CInt

-- | LU factorization with partial pivoting (@LAPACKE_dgetrf@) of an
-- @m x n@ matrix: returns @(LU, ipiv)@ where @LU@ packs both factors
-- and @ipiv@ (1-based) feeds 'dgetri'. @Left i@: @U(i,i)@ is exactly
-- zero (the factor is dropped — downstream use would be invalid).
dgetrf
  :: Backend
  -> Int -- ^ m
  -> Int -- ^ n
  -> VS.Vector Double -- ^ A
  -> IO (Either Int (VS.Vector Double, VS.Vector CInt))
dgetrf be m n a = do
  checkDim "dgetrf" "A" (VS.length a) (m * n)
  aC <- VS.thaw a
  ipiv <- VSM.new (min m n) :: IO (VSM.IOVector CInt)
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith ipiv $ \pp ->
        callDgetrf (opDgetrf (capOps be))
          lapackRowMajor (fromIntegral m) (fromIntegral n)
          pa (fromIntegral n) pp
  interpretInfo "dgetrf" info
    ((,) <$> VS.unsafeFreeze aC <*> VS.unsafeFreeze ipiv)

-- | Matrix inverse from a 'dgetrf' factorization (@LAPACKE_dgetri@):
-- pass the @n x n@ @LU@ and its @ipiv@. @Left i@: singular at
-- @U(i,i)@.
dgetri
  :: Backend
  -> Int -- ^ n
  -> VS.Vector Double -- ^ LU from 'dgetrf'
  -> VS.Vector CInt -- ^ ipiv from 'dgetrf'
  -> IO (Either Int (VS.Vector Double))
dgetri be n lu ipiv = do
  checkDim "dgetri" "LU" (VS.length lu) (n * n)
  checkDim "dgetri" "ipiv" (VS.length ipiv) n
  luC <- VS.thaw lu
  ipivC <- VS.thaw ipiv
  info <-
    VSM.unsafeWith luC $ \pa ->
      VSM.unsafeWith ipivC $ \pp ->
        callDgetri (opDgetri (capOps be))
          lapackRowMajor (fromIntegral n) pa (fromIntegral n) pp
  interpretInfo "dgetri" info (VS.unsafeFreeze luC)

-- | Cholesky factorization (@LAPACKE_dpotrf@) of a symmetric
-- positive-definite @n x n@ matrix; only the 'Uplo' triangle is read
-- and only that triangle of the result is the factor (the other
-- triangle keeps the input's bytes). @Left i@: leading minor of order
-- @i@ not positive definite.
dpotrf
  :: Backend
  -> Uplo
  -> Int -- ^ n
  -> VS.Vector Double -- ^ A
  -> IO (Either Int (VS.Vector Double))
dpotrf be uplo n a = do
  checkDim "dpotrf" "A" (VS.length a) (n * n)
  aC <- VS.thaw a
  info <-
    VSM.unsafeWith aC $ \pa ->
      callDpotrf (opDpotrf (capOps be))
        lapackRowMajor (uploChar uplo) (fromIntegral n) pa (fromIntegral n)
  interpretInfo "dpotrf" info (VS.unsafeFreeze aC)

-- | Inverse of a symmetric positive-definite matrix from its 'dpotrf'
-- factor (@LAPACKE_dpotri@); only the 'Uplo' triangle of the result is
-- the inverse. @Left i@: @factor(i,i)@ is exactly zero.
dpotri
  :: Backend
  -> Uplo
  -> Int -- ^ n
  -> VS.Vector Double -- ^ Cholesky factor from 'dpotrf'
  -> IO (Either Int (VS.Vector Double))
dpotri be uplo n f = do
  checkDim "dpotri" "factor" (VS.length f) (n * n)
  fC <- VS.thaw f
  info <-
    VSM.unsafeWith fC $ \pa ->
      callDpotri (opDpotri (capOps be))
        lapackRowMajor (uploChar uplo) (fromIntegral n) pa (fromIntegral n)
  interpretInfo "dpotri" info (VS.unsafeFreeze fC)

-- ---------------------------------------------------------------------
-- SVD

foreign import ccall safe "dynamic"
  callDgesdd
    :: FunPtr
         (  CInt -> CChar -> CInt -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double
         -> Ptr Double -> CInt
         -> Ptr Double -> CInt
         -> IO CInt
         )
    -> CInt -> CChar -> CInt -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double
    -> Ptr Double -> CInt
    -> Ptr Double -> CInt
    -> IO CInt

foreign import ccall safe "dynamic"
  callDgesvd
    :: FunPtr
         (  CInt -> CChar -> CChar -> CInt -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double
         -> Ptr Double -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double
         -> IO CInt
         )
    -> CInt -> CChar -> CChar -> CInt -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double
    -> Ptr Double -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double
    -> IO CInt

-- Shared economy-size SVD wrapper: allocate s/U/VT, run the driver's
-- foreign call, package the triple.
svdWith
  :: String
  -> Int
  -> Int
  -> VS.Vector Double
  -> (Ptr Double -> Ptr Double -> Ptr Double -> Ptr Double -> IO CInt)
  -> IO (Either Int (VS.Vector Double, VS.Vector Double, VS.Vector Double))
svdWith ctx m n a call = do
  checkDim ctx "A" (VS.length a) (m * n)
  let minmn = min m n
  aC <- VS.thaw a
  s <- VSM.new minmn
  u <- VSM.new (m * minmn)
  vt <- VSM.new (minmn * n)
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith s $ \ps ->
        VSM.unsafeWith u $ \pu ->
          VSM.unsafeWith vt $ \pvt ->
            call pa ps pu pvt
  interpretInfo ctx info
    ((,,) <$> VS.unsafeFreeze s <*> VS.unsafeFreeze u <*> VS.unsafeFreeze vt)

-- | Economy-size SVD by divide and conquer (@LAPACKE_dgesdd@,
-- @jobz = \'S\'@): returns @(s, U, VT)@ with @s@ descending of length
-- @min m n@, @U@ of @m x min m n@, @VT@ of @min m n x n@. @Left i@:
-- the algorithm failed to converge.
dgesdd
  :: Backend
  -> Int -- ^ m
  -> Int -- ^ n
  -> VS.Vector Double -- ^ A
  -> IO (Either Int (VS.Vector Double, VS.Vector Double, VS.Vector Double))
dgesdd be m n a =
  svdWith "dgesdd" m n a $ \pa ps pu pvt ->
    callDgesdd (opDgesdd (capOps be))
      lapackRowMajor (castCharToCChar 'S')
      (fromIntegral m) (fromIntegral n)
      pa (fromIntegral n) ps
      pu (fromIntegral (min m n))
      pvt (fromIntegral n)

-- | Economy-size SVD by QR iteration (@LAPACKE_dgesvd@,
-- @jobu = jobvt = \'S\'@) — slower than 'dgesdd' but a different
-- algorithm, useful as a cross-check. Same result shape as 'dgesdd'.
-- @Left i@: @i@ superdiagonals failed to converge.
dgesvd
  :: Backend
  -> Int -- ^ m
  -> Int -- ^ n
  -> VS.Vector Double -- ^ A
  -> IO (Either Int (VS.Vector Double, VS.Vector Double, VS.Vector Double))
dgesvd be m n a = do
  superb <- VSM.new (max 1 (min m n - 1)) :: IO (VSM.IOVector Double)
  svdWith "dgesvd" m n a $ \pa ps pu pvt ->
    VSM.unsafeWith superb $ \psb ->
      callDgesvd (opDgesvd (capOps be))
        lapackRowMajor (castCharToCChar 'S') (castCharToCChar 'S')
        (fromIntegral m) (fromIntegral n)
        pa (fromIntegral n) ps
        pu (fromIntegral (min m n))
        pvt (fromIntegral n)
        psb

-- ---------------------------------------------------------------------
-- Eigendecomposition

foreign import ccall safe "dynamic"
  callDsyevd
    :: FunPtr
         (  CInt -> CChar -> CChar -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double
         -> IO CInt
         )
    -> CInt -> CChar -> CChar -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double
    -> IO CInt

foreign import ccall safe "dynamic"
  callDgeev
    :: FunPtr
         (  CInt -> CChar -> CChar -> CInt
         -> Ptr Double -> CInt
         -> Ptr Double -> Ptr Double
         -> Ptr Double -> CInt
         -> Ptr Double -> CInt
         -> IO CInt
         )
    -> CInt -> CChar -> CChar -> CInt
    -> Ptr Double -> CInt
    -> Ptr Double -> Ptr Double
    -> Ptr Double -> CInt
    -> Ptr Double -> CInt
    -> IO CInt

-- | Eigendecomposition of a symmetric matrix by divide and conquer
-- (@LAPACKE_dsyevd@, @jobz = \'V\'@); only the 'Uplo' triangle is
-- read. Returns @(w, V)@: eigenvalues ascending, and the eigenvector
-- for @w[i]@ in /column/ @i@ of the row-major @n x n@ @V@ (i.e.
-- @V[j*n + i]@), matching @numpy.linalg.eigh@. @Left i@: failed to
-- converge.
dsyevd
  :: Backend
  -> Uplo
  -> Int -- ^ n
  -> VS.Vector Double -- ^ A (symmetric)
  -> IO (Either Int (VS.Vector Double, VS.Vector Double))
dsyevd be uplo n a = do
  checkDim "dsyevd" "A" (VS.length a) (n * n)
  aC <- VS.thaw a
  w <- VSM.new n
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith w $ \pw ->
        callDsyevd (opDsyevd (capOps be))
          lapackRowMajor (castCharToCChar 'V') (uploChar uplo)
          (fromIntegral n) pa (fromIntegral n) pw
  interpretInfo "dsyevd" info
    ((,) <$> VS.unsafeFreeze w <*> VS.unsafeFreeze aC)

-- | Eigendecomposition of a general matrix (@LAPACKE_dgeev@, right
-- eigenvectors only). Returns @(wr, wi, VR)@ in LAPACK's packed real
-- convention: eigenvalue @j@ is @wr[j] :+ wi[j]@; for a real
-- eigenvalue, column @j@ of @VR@ is its eigenvector; a complex
-- conjugate pair occupies columns @j@ (real part) and @j+1@ (imaginary
-- part). @Left i@: the QR algorithm failed to converge.
dgeev
  :: Backend
  -> Int -- ^ n
  -> VS.Vector Double -- ^ A
  -> IO (Either Int (VS.Vector Double, VS.Vector Double, VS.Vector Double))
dgeev be n a = do
  checkDim "dgeev" "A" (VS.length a) (n * n)
  aC <- VS.thaw a
  wr <- VSM.new n
  wi <- VSM.new n
  vr <- VSM.new (n * n)
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith wr $ \pwr ->
        VSM.unsafeWith wi $ \pwi ->
          VSM.unsafeWith vr $ \pvr ->
            callDgeev (opDgeev (capOps be))
              lapackRowMajor (castCharToCChar 'N') (castCharToCChar 'V')
              (fromIntegral n) pa (fromIntegral n)
              pwr pwi
              nullPtr (fromIntegral n)
              pvr (fromIntegral n)
  interpretInfo "dgeev" info
    ((,,) <$> VS.unsafeFreeze wr <*> VS.unsafeFreeze wi <*> VS.unsafeFreeze vr)

-- ---------------------------------------------------------------------
-- QR

foreign import ccall safe "dynamic"
  callDgeqrf
    :: FunPtr (CInt -> CInt -> CInt -> Ptr Double -> CInt -> Ptr Double -> IO CInt)
    -> CInt -> CInt -> CInt -> Ptr Double -> CInt -> Ptr Double -> IO CInt

foreign import ccall safe "dynamic"
  callDorgqr
    :: FunPtr (CInt -> CInt -> CInt -> CInt -> Ptr Double -> CInt -> Ptr Double -> IO CInt)
    -> CInt -> CInt -> CInt -> CInt -> Ptr Double -> CInt -> Ptr Double -> IO CInt

-- These two drivers define no positive info values, so success is the
-- only non-throwing outcome.
expectClean :: String -> CInt -> IO a -> IO a
expectClean ctx info onOk
  | info == 0 = onOk
  | otherwise = throwIO (LapackBadArgument ctx (fromIntegral (abs info)))

-- | QR factorization (@LAPACKE_dgeqrf@) of an @m x n@ matrix: returns
-- @(QR, tau)@ where @QR@ packs @R@ in the upper triangle and the
-- Householder reflectors below, and @tau@ has @min m n@ scalar
-- factors. Feed both to 'dorgqr' to materialize @Q@.
dgeqrf
  :: Backend
  -> Int -- ^ m
  -> Int -- ^ n
  -> VS.Vector Double -- ^ A
  -> IO (VS.Vector Double, VS.Vector Double)
dgeqrf be m n a = do
  checkDim "dgeqrf" "A" (VS.length a) (m * n)
  aC <- VS.thaw a
  tau <- VSM.new (min m n)
  info <-
    VSM.unsafeWith aC $ \pa ->
      VSM.unsafeWith tau $ \pt ->
        callDgeqrf (opDgeqrf (capOps be))
          lapackRowMajor (fromIntegral m) (fromIntegral n)
          pa (fromIntegral n) pt
  expectClean "dgeqrf" info
    ((,) <$> VS.unsafeFreeze aC <*> VS.unsafeFreeze tau)

-- | Materialize the first @n@ columns of @Q@ from a 'dgeqrf'
-- factorization (@LAPACKE_dorgqr@): pass the packed @QR@ (@m x n@) and
-- @tau@ (@k@ reflectors, @k = min m n@ from 'dgeqrf'); the result is
-- @m x n@ with orthonormal columns.
dorgqr
  :: Backend
  -> Int -- ^ m
  -> Int -- ^ n
  -> Int -- ^ k
  -> VS.Vector Double -- ^ packed QR from 'dgeqrf'
  -> VS.Vector Double -- ^ tau from 'dgeqrf'
  -> IO (VS.Vector Double)
dorgqr be m n k qr tau = do
  checkDim "dorgqr" "QR" (VS.length qr) (m * n)
  checkDim "dorgqr" "tau" (VS.length tau) k
  qrC <- VS.thaw qr
  tauC <- VS.thaw tau
  info <-
    VSM.unsafeWith qrC $ \pa ->
      VSM.unsafeWith tauC $ \pt ->
        callDorgqr (opDorgqr (capOps be))
          lapackRowMajor (fromIntegral m) (fromIntegral n) (fromIntegral k)
          pa (fromIntegral n) pt
  expectClean "dorgqr" info (VS.unsafeFreeze qrC)
