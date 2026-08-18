-- | Cross-platform runtime loading of native shared libraries.
--
-- This module is the keystone of keel: every native capability (OpenBLAS,
-- ONNX Runtime, ...) is resolved at run time through it, so no keel package
-- carries a build-time C dependency and @cabal install@ can never fail on a
-- missing native library.
--
-- Search-path behaviour:
--
-- * Windows: 'loadLibrary' first tries @LoadLibraryExW@ with
--   @LOAD_LIBRARY_SEARCH_DEFAULT_DIRS@ (application dir, System32, and any
--   directory registered via 'addSearchDir'; for absolute paths also the
--   library's own directory, so multi-DLL packages find their siblings),
--   then falls back to the legacy @LoadLibraryW@ search (PATH, CWD) so
--   bare names on PATH keep working.
-- * POSIX: @dlopen@ semantics (rpath, @LD_LIBRARY_PATH@\/@DYLD_*@, system
--   default dirs). 'addSearchDir' is a documented no-op returning 'False' —
--   POSIX search paths must be set before process start.
--
-- For the full env-var → data-dir → system policy that capability packages
-- use, see "Keel.Dyn.Locate".
--
-- == Building a capability record
--
-- Resolve each function once at load time into a record of 'FunPtr's,
-- invoked through @foreign import ccall \"dynamic\"@ wrappers. Required
-- symbols use 'requireSym' (throws 'DynError'); symbols that may be absent
-- in older library builds use 'resolveOptional', so a missing symbol
-- degrades that one operation instead of failing the whole library:
--
-- > data BlasOps = BlasOps
-- >   { ddot   :: FunPtr CblasDdotT           -- required
-- >   , dgemm  :: FunPtr CblasDgemmT          -- required
-- >   , sbgemm :: Maybe (FunPtr CblasSbgemmT) -- bfloat16: newer builds only
-- >   }
-- >
-- > openBlas :: Library -> IO (Capability BlasOps)
-- > openBlas lib = do
-- >   ops <- BlasOps
-- >     <$> requireSym lib "cblas_ddot"
-- >     <*> requireSym lib "cblas_dgemm"
-- >     <*> resolveOptional lib "cblas_sbgemm"
-- >   version <- queryVersion lib   -- e.g. via openblas_get_config
-- >   pure (Capability lib version ops)
module Keel.Dyn
  ( -- * Libraries
    Library
  , libraryPath
  , loadLibrary
  , loadLibraryGlobal
  , closeLibrary
  , withLibrary

    -- * Symbols
  , resolveSym
  , resolveOptional
  , requireSym

    -- * Capability records
  , Capability (..)

    -- * Search path
  , addSearchDir

    -- * Errors
  , DynError (..)
  ) where

import Control.Exception (throwIO)
import Foreign.Ptr (FunPtr)

import Keel.Dyn.Platform

-- | Like 'resolveSym' but throws the 'DynError' as an exception. Intended
-- for assembling capability records applicatively (see the module header).
requireSym :: Library -> String -> IO (FunPtr a)
requireSym lib name = resolveSym lib name >>= either throwIO pure

-- | A loaded native capability: the library it came from, a version tag
-- queried from the library itself (shown by @keel doctor@), and a
-- caller-defined record of resolved 'FunPtr's.
data Capability ops = Capability
  { capLibrary :: Library
  , capVersion :: String
  , capOps :: ops
  }
