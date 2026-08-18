-- | Locating, probing and pinning the BLAS\/LAPACK backend.
--
-- keel-linalg 0.1 targets OpenBLAS specifically: the library is loaded
-- at run time (never linked), identified via @openblas_get_config@, and
-- rejected loudly when the build is ILP64 (@USE64BITINT@) — a silently
-- mis-matched integer width corrupts results above @2^31@ elements
-- instead of failing. Symbol-renamed builds (e.g. the @scipy_@-prefixed
-- or @64_@-suffixed wheels that numpy\/scipy bundle) do not resolve the
-- standard names and are therefore rejected as 'BackendMissingSymbol' —
-- point 'defaultBlasSpec' at a stock OpenBLAS instead.
--
-- All symbols are resolved eagerly at open time, so an OpenBLAS built
-- without LAPACKE surfaces as one clear 'BackendMissingSymbol' up front
-- instead of a crash mid-computation (the symbol-drift hazard).
--
-- The returned 'Backend' is an immutable pin: every operation runs
-- against the handle you pass it, there is no global backend state and
-- no swapping. Thread policy: unless the user has set
-- @OPENBLAS_NUM_THREADS@ themselves, the backend is pinned to a single
-- BLAS thread at open time — OpenBLAS's own pool fights the GHC RTS
-- scheduler, and parallelism belongs to the caller.
module Keel.Linalg.Backend
  ( Backend
  , Ops (..)
  , BackendError (..)
  , backendConfig
  , defaultBlasSpec
  , openBackend
  , openBackendWith
  , closeBackend

    -- * Probes (exposed for tests and doctor)
  , isILP64Config
  ) where

import Control.Exception (Exception)
import Data.List (isInfixOf)
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CChar, CInt (..))
import Foreign.Ptr (FunPtr, Ptr)
import System.Environment (lookupEnv)
import System.Info (os)

import Keel.Dyn
import Keel.Dyn.Locate

-- | C signatures of the resolved operations (CBLAS\/LAPACKE calling
-- conventions, LP64 integers, @char@ mode arguments). Callers go
-- through "Keel.Linalg"; the record is exposed so that layer can live
-- in a separate module.
data Ops = Ops
  { opDdot :: FunPtr (CInt -> Ptr Double -> CInt -> Ptr Double -> CInt -> IO Double)
  , opDgemm
      :: FunPtr
           (  CInt -> CInt -> CInt          -- order, transA, transB
           -> CInt -> CInt -> CInt          -- m, n, k
           -> Double -> Ptr Double -> CInt  -- alpha, A, lda
           -> Ptr Double -> CInt            -- B, ldb
           -> Double -> Ptr Double -> CInt  -- beta, C, ldc
           -> IO ()
           )
  , opDgesv
      :: FunPtr
           (  CInt -> CInt -> CInt          -- layout, n, nrhs
           -> Ptr Double -> CInt            -- A (overwritten with LU), lda
           -> Ptr CInt                      -- ipiv
           -> Ptr Double -> CInt            -- B (overwritten with X), ldb
           -> IO CInt                       -- info
           )
  , opDposv
      :: FunPtr
           (  CInt -> CChar -> CInt -> CInt -- layout, uplo, n, nrhs
           -> Ptr Double -> CInt            -- A (overwritten with factor), lda
           -> Ptr Double -> CInt            -- B (overwritten with X), ldb
           -> IO CInt
           )
  , opDgels
      :: FunPtr
           (  CInt -> CChar                 -- layout, trans
           -> CInt -> CInt -> CInt          -- m, n, nrhs
           -> Ptr Double -> CInt            -- A (overwritten with QR/LQ), lda
           -> Ptr Double -> CInt            -- B (overwritten with X), ldb
           -> IO CInt
           )
  , opDtrtrs
      :: FunPtr
           (  CInt -> CChar -> CChar -> CChar -- layout, uplo, trans, diag
           -> CInt -> CInt                    -- n, nrhs
           -> Ptr Double -> CInt              -- A (read-only), lda
           -> Ptr Double -> CInt              -- B (overwritten with X), ldb
           -> IO CInt
           )
  , opDgetrf
      :: FunPtr
           (  CInt -> CInt -> CInt          -- layout, m, n
           -> Ptr Double -> CInt            -- A (overwritten with LU), lda
           -> Ptr CInt                      -- ipiv
           -> IO CInt
           )
  , opDgetri
      :: FunPtr
           (  CInt -> CInt                  -- layout, n
           -> Ptr Double -> CInt            -- A (LU in, inverse out), lda
           -> Ptr CInt                      -- ipiv from dgetrf
           -> IO CInt
           )
  , opDpotrf
      :: FunPtr
           (  CInt -> CChar -> CInt         -- layout, uplo, n
           -> Ptr Double -> CInt            -- A (overwritten with factor), lda
           -> IO CInt
           )
  , opDpotri
      :: FunPtr
           (  CInt -> CChar -> CInt         -- layout, uplo, n
           -> Ptr Double -> CInt            -- A (factor in, inverse out), lda
           -> IO CInt
           )
  , opSetNumThreads :: Maybe (FunPtr (CInt -> IO ()))
    -- ^ @openblas_set_num_threads@ — optional so its absence degrades
    -- only thread control, not the backend.
  }

-- | An immutably pinned OpenBLAS backend: the library handle, the
-- @openblas_get_config@ string as the version tag, and the resolved
-- operations.
type Backend = Capability Ops

-- | The backend's @openblas_get_config@ string, e.g.
-- @\"OpenBLAS 0.3.30 DYNAMIC_ARCH NO_AFFINITY Cooperlake MAX_THREADS=64\"@.
backendConfig :: Backend -> String
backendConfig = capVersion

-- | Why a backend could not be opened.
data BackendError
  = BackendNotFound DynError
    -- ^ No library was found by the search policy.
  | BackendNotOpenBLAS FilePath
    -- ^ The library loaded but exports no @openblas_get_config@ —
    -- keel-linalg 0.1 refuses to run un-probeable backends.
  | BackendILP64 String
    -- ^ The build is ILP64 (@USE64BITINT@ in the config string); these
    -- bindings use 32-bit integers and would corrupt silently.
  | BackendMissingSymbol DynError
    -- ^ A required CBLAS\/LAPACKE symbol is absent (symbol-renamed or
    -- LAPACKE-less builds land here).
  deriving (Eq, Show)

instance Exception BackendError

-- | Where 'openBackend' looks: @KEEL_OPENBLAS@ override, the per-user
-- keel data dir under the name @openblas@, then the system search path
-- with the platform's stock library names.
defaultBlasSpec :: LibrarySpec
defaultBlasSpec =
  LibrarySpec
    { specName = "openblas"
    , specEnvVar = "KEEL_OPENBLAS"
    , specCandidates = case os of
        "mingw32" -> ["libopenblas.dll", "openblas.dll"]
        "darwin" -> ["libopenblas.dylib", "libopenblas.0.dylib"]
        _ -> ["libopenblas.so.0", "libopenblas.so"]
    }

-- | @True@ when the config string names an ILP64 build.
isILP64Config :: String -> Bool
isILP64Config = ("USE64BITINT" `isInfixOf`)

foreign import ccall unsafe "dynamic"
  callGetConfig :: FunPtr (IO CString) -> IO CString

foreign import ccall unsafe "dynamic"
  callSetNumThreads :: FunPtr (CInt -> IO ()) -> CInt -> IO ()

-- | 'openBackendWith' 'defaultBlasSpec'.
openBackend :: IO (Either BackendError Backend)
openBackend = openBackendWith defaultBlasSpec

-- | Locate, probe and pin an OpenBLAS backend. See the module header
-- for the probe and thread policy.
openBackendWith :: LibrarySpec -> IO (Either BackendError Backend)
openBackendWith spec = do
  located <- locateLibrary spec
  case located of
    Left e -> pure (Left (BackendNotFound e))
    Right loc -> do
      let lib = locLibrary loc
      cfgSym <- resolveSym lib "openblas_get_config"
      case cfgSym of
        Left _ -> do
          closeLibrary lib
          pure (Left (BackendNotOpenBLAS (libraryPath lib)))
        Right cfgFp -> do
          cfg <- peekCString =<< callGetConfig cfgFp
          if isILP64Config cfg
            then do
              closeLibrary lib
              pure (Left (BackendILP64 cfg))
            else assemble lib cfg

assemble :: Library -> String -> IO (Either BackendError Backend)
assemble lib cfg = do
  ops <-
    Ops
      <$$> "cblas_ddot"
      <**> "cblas_dgemm"
      <**> "LAPACKE_dgesv"
      <**> "LAPACKE_dposv"
      <**> "LAPACKE_dgels"
      <**> "LAPACKE_dtrtrs"
      <**> "LAPACKE_dgetrf"
      <**> "LAPACKE_dgetri"
      <**> "LAPACKE_dpotrf"
      <**> "LAPACKE_dpotri"
  threadsM <- resolveOptional lib "openblas_set_num_threads"
  case ($ threadsM) <$> ops of
    Left e -> do
      closeLibrary lib
      pure (Left (BackendMissingSymbol e))
    Right ops' -> do
      userSet <- lookupEnv "OPENBLAS_NUM_THREADS"
      case (userSet, opSetNumThreads ops') of
        (Nothing, Just fp) -> callSetNumThreads fp 1
        _ -> pure ()
      pure (Right (Capability lib cfg ops'))
  where
    -- applicative resolution over Either DynError, keeping the first
    -- missing symbol's name in the error (explicit signatures: GHC2021's
    -- MonoLocalBinds would otherwise monomorphise the FunPtr type)
    (<$$>) :: (FunPtr a -> b) -> String -> IO (Either DynError b)
    f <$$> name = fmap (fmap f) (resolveSym lib name)
    (<**>) :: IO (Either DynError (FunPtr a -> b)) -> String -> IO (Either DynError b)
    mf <**> name = do
      f <- mf
      x <- resolveSym lib name
      pure (f <*> x)
    infixl 4 <$$>, <**>

-- | Drop the pin. All operations on this 'Backend' become invalid.
closeBackend :: Backend -> IO ()
closeBackend = closeLibrary . capLibrary
