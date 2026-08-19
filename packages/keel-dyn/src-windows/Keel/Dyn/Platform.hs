-- | Windows implementation: LoadLibraryExW \/ GetProcAddress \/ FreeLibrary.
--
-- All imports come from kernel32, which GHC's mingw toolchain links by
-- default, so this module needs no headers, no import libraries and no
-- build-time configuration.
module Keel.Dyn.Platform
  ( Library
  , libraryPath
  , DynError (..)
  , loadLibrary
  , loadLibraryGlobal
  , closeLibrary
  , withLibrary
  , resolveSym
  , resolveOptional
  , addSearchDir
  ) where

import Control.Concurrent (rtsSupportsBoundThreads, runInBoundThread)
import Control.Exception (Exception, finally, mask)
import Control.Monad (void)
import Data.Bits ((.|.))
import Data.Word (Word32)
import Foreign.C.String (CString, CWString, withCString, withCWString)
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, Ptr, castFunPtr, nullFunPtr, nullPtr)
import System.Environment (lookupEnv)
import System.FilePath (isAbsolute, splitSearchPath, (</>))

type HMODULE = Ptr ()

-- | A loaded shared library. Constructor deliberately not exported.
data Library = Library
  { libHandle :: !HMODULE
  , libraryPath :: !FilePath
    -- ^ The path\/name the library was requested as.
  }

-- | Failure modes of loading and symbol resolution.
data DynError
  = LibraryNotFound FilePath String
    -- ^ Library could not be loaded; the 'String' carries OS detail.
  | SymbolNotFound FilePath String
    -- ^ The named symbol is absent from the named library.
  deriving (Eq, Show)

instance Exception DynError

-- LoadLibrary runs the target's DllMain and pages the image in from
-- disk, and FreeLibrary runs DllMain again — both can block for a long
-- time, so they are imported safe: a slow load stalls only its own
-- thread, not every Haskell thread on the capability (the unix package
-- marks dlopen/dlclose safe for the same reason). GetProcAddress,
-- GetLastError and AddDllDirectory are cheap lookups and stay unsafe.
foreign import ccall safe "LoadLibraryExW"
  c_LoadLibraryExW :: CWString -> Ptr () -> Word32 -> IO HMODULE

foreign import ccall unsafe "GetProcAddress"
  c_GetProcAddress :: HMODULE -> CString -> IO (FunPtr ())

foreign import ccall safe "FreeLibrary"
  c_FreeLibrary :: HMODULE -> IO CInt

foreign import ccall unsafe "GetLastError"
  c_GetLastError :: IO Word32

foreign import ccall unsafe "AddDllDirectory"
  c_AddDllDirectory :: CWString -> IO (Ptr ())

-- LOAD_LIBRARY_SEARCH_DEFAULT_DIRS: application dir + System32 + directories
-- registered through AddDllDirectory. Deliberately excludes CWD (a classic
-- DLL-planting hazard); PATH is only reached via the explicit walk below,
-- which never consults CWD either.
searchDefaultDirs :: Word32
searchDefaultDirs = 0x00001000

-- LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR: also resolve the loaded DLL's own
-- dependencies from the directory the DLL itself lives in. Only legal when
-- the requested path is fully qualified; essential for multi-DLL packages
-- (onnxruntime.dll finds its provider DLLs next to itself).
searchDllLoadDir :: Word32
searchDllLoadDir = 0x00000100

-- | Load a shared library by bare name or path. Search order is documented
-- in "Keel.Dyn". The current directory is never searched: the primary
-- lookup uses the safe default-directories set, and the @PATH@ fallback
-- for bare names walks the @PATH@ entries explicitly instead of handing
-- the name to the legacy loader search (whose order includes CWD).
loadLibrary :: FilePath -> IO (Either DynError Library)
loadLibrary path = inBound $ withCWString path $ \wpath -> do
  let flags
        | isAbsolute path = searchDllLoadDir .|. searchDefaultDirs
        | otherwise = searchDefaultDirs
  hEx <- c_LoadLibraryExW wpath nullPtr flags
  if hEx /= nullPtr
    then pure (Right (Library hEx path))
    else do
      -- read the primary attempt's error before any further calls
      code <- c_GetLastError
      h <- if isAbsolute path then pure nullPtr else tryPath path
      pure $
        if h == nullPtr
          then Left (LibraryNotFound path ("Win32 error " <> show code))
          else Right (Library h path)

-- Walk PATH ourselves: each candidate is loaded by absolute path (with
-- own-directory dependency resolution), relative PATH entries are
-- skipped, and CWD is never consulted.
tryPath :: FilePath -> IO HMODULE
tryPath name = do
  dirs <- maybe [] splitSearchPath <$> lookupEnv "PATH"
  go (filter isAbsolute dirs)
  where
    go [] = pure nullPtr
    go (d : ds) = do
      h <- withCWString (d </> name) $ \w ->
        c_LoadLibraryExW w nullPtr (searchDllLoadDir .|. searchDefaultDirs)
      if h /= nullPtr then pure h else go ds

-- GetLastError is only meaningful on the OS thread that made the failing
-- call, and an unbound Haskell thread may migrate between two foreign
-- calls; a bound thread pins the whole load-and-diagnose sequence to one
-- OS thread. A non-threaded RTS has a single OS thread already.
inBound :: IO a -> IO a
inBound = if rtsSupportsBoundThreads then runInBoundThread else id

-- | On Windows this is identical to 'loadLibrary': PE imports are
-- resolved per-module from the DLL's import table, so there is no
-- POSIX-style global symbol namespace to opt into.
loadLibraryGlobal :: FilePath -> IO (Either DynError Library)
loadLibraryGlobal = loadLibrary

-- | Release the OS handle, best-effort: a failed FreeLibrary is ignored —
-- there is no recovery, and 'withLibrary' must not let a cleanup failure
-- replace the action's own exception. 'FunPtr's resolved from this
-- 'Library' must not be called afterwards.
closeLibrary :: Library -> IO ()
closeLibrary = void . c_FreeLibrary . libHandle

-- | 'loadLibrary' \/ 'closeLibrary' bracket, async-exception-safe: the
-- window between a successful load and the cleanup registration is
-- masked, so a timeout cannot leak the handle.
withLibrary :: FilePath -> (Library -> IO a) -> IO (Either DynError a)
withLibrary path act = mask $ \restore -> do
  r <- loadLibrary path
  case r of
    Left e -> pure (Left e)
    Right lib -> restore (Right <$> act lib) `finally` closeLibrary lib

-- | Resolve an exported symbol to a 'FunPtr', to be invoked through a
-- @foreign import ccall \"dynamic\"@ wrapper. The result type is the
-- caller's unchecked claim about the C signature.
resolveSym :: Library -> String -> IO (Either DynError (FunPtr a))
resolveSym lib name = withCString name $ \cname -> do
  fp <- c_GetProcAddress (libHandle lib) cname
  if fp == nullFunPtr
    then pure (Left (SymbolNotFound (libraryPath lib) name))
    else pure (Right (castFunPtr fp))

-- | 'resolveSym' flattened to 'Maybe', for symbols whose absence is an
-- expected, degradable condition rather than an error.
resolveOptional :: Library -> String -> IO (Maybe (FunPtr a))
resolveOptional lib name = either (const Nothing) Just <$> resolveSym lib name

-- | Register an extra DLL search directory for subsequent 'loadLibrary'
-- calls. The directory must be an absolute path (AddDllDirectory refuses
-- relative ones). Returns 'False' if the OS refused it.
addSearchDir :: FilePath -> IO Bool
addSearchDir dir = withCWString dir $ \wdir -> do
  cookie <- c_AddDllDirectory wdir
  pure (cookie /= nullPtr)
