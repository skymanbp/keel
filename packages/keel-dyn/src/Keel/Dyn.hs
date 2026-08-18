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
--   directory registered via 'addSearchDir'), then falls back to the legacy
--   @LoadLibraryW@ search (PATH, CWD) so bare names on PATH keep working.
-- * POSIX: @dlopen@ semantics (rpath, @LD_LIBRARY_PATH@\/@DYLD_*@, system
--   default dirs). 'addSearchDir' is a documented no-op returning 'False' —
--   POSIX search paths must be set before process start.
module Keel.Dyn
  ( -- * Libraries
    Library
  , libraryPath
  , loadLibrary
  , closeLibrary
  , withLibrary

    -- * Symbols
  , resolveSym
  , resolveOptional

    -- * Search path
  , addSearchDir

    -- * Errors
  , DynError (..)
  ) where

import Keel.Dyn.Platform
