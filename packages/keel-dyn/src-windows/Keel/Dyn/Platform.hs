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
  , closeLibrary
  , withLibrary
  , resolveSym
  , resolveOptional
  , addSearchDir
  ) where

import Control.Exception (Exception, finally)
import Control.Monad (void)
import Data.Bits ((.|.))
import Data.Word (Word32)
import Foreign.C.String (CString, CWString, withCString, withCWString)
import Foreign.Ptr (FunPtr, Ptr, castFunPtr, nullFunPtr, nullPtr)
import System.FilePath (isAbsolute)

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

foreign import ccall unsafe "LoadLibraryExW"
  c_LoadLibraryExW :: CWString -> Ptr () -> Word32 -> IO HMODULE

foreign import ccall unsafe "LoadLibraryW"
  c_LoadLibraryW :: CWString -> IO HMODULE

foreign import ccall unsafe "GetProcAddress"
  c_GetProcAddress :: HMODULE -> CString -> IO (FunPtr ())

foreign import ccall unsafe "FreeLibrary"
  c_FreeLibrary :: HMODULE -> IO Int

foreign import ccall unsafe "GetLastError"
  c_GetLastError :: IO Word32

foreign import ccall unsafe "AddDllDirectory"
  c_AddDllDirectory :: CWString -> IO (Ptr ())

-- LOAD_LIBRARY_SEARCH_DEFAULT_DIRS: application dir + System32 + directories
-- registered through AddDllDirectory. Deliberately excludes CWD (a classic
-- DLL-planting hazard); PATH/CWD are only reached via the explicit legacy
-- fallback below.
searchDefaultDirs :: Word32
searchDefaultDirs = 0x00001000

-- LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR: also resolve the loaded DLL's own
-- dependencies from the directory the DLL itself lives in. Only legal when
-- the requested path is fully qualified; essential for multi-DLL packages
-- (onnxruntime.dll finds its provider DLLs next to itself).
searchDllLoadDir :: Word32
searchDllLoadDir = 0x00000100

-- | Load a shared library by bare name or path. Search order is documented
-- in "Keel.Dyn".
loadLibrary :: FilePath -> IO (Either DynError Library)
loadLibrary path = withCWString path $ \wpath -> do
  let flags
        | isAbsolute path = searchDllLoadDir .|. searchDefaultDirs
        | otherwise = searchDefaultDirs
  hEx <- c_LoadLibraryExW wpath nullPtr flags
  h <- if hEx /= nullPtr then pure hEx else c_LoadLibraryW wpath
  if h == nullPtr
    then do
      code <- c_GetLastError
      pure (Left (LibraryNotFound path ("Win32 error " <> show code)))
    else pure (Right (Library h path))

-- | Release the OS handle. 'FunPtr's resolved from this 'Library' must not
-- be called afterwards.
closeLibrary :: Library -> IO ()
closeLibrary = void . c_FreeLibrary . libHandle

-- | 'loadLibrary' \/ 'closeLibrary' bracket.
withLibrary :: FilePath -> (Library -> IO a) -> IO (Either DynError a)
withLibrary path act = do
  r <- loadLibrary path
  case r of
    Left e -> pure (Left e)
    Right lib -> (Right <$> act lib) `finally` closeLibrary lib

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
