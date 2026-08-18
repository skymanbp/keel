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

import Control.Exception (finally)
import Control.Monad (void)
import Data.Word (Word32)
import Foreign.C.String (CString, CWString, withCString, withCWString)
import Foreign.Ptr (FunPtr, Ptr, castFunPtr, nullFunPtr, nullPtr)

type HMODULE = Ptr ()

-- | A loaded shared library. Constructor deliberately not exported.
data Library = Library
  { libHandle :: !HMODULE
  , libraryPath :: !FilePath
    -- ^ The path\/name the library was requested as.
  }

data DynError
  = LibraryNotFound FilePath String
    -- ^ Library could not be loaded; the 'String' carries OS detail.
  | SymbolNotFound FilePath String
    -- ^ The named symbol is absent from the named library.
  deriving (Eq, Show)

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

loadLibrary :: FilePath -> IO (Either DynError Library)
loadLibrary path = withCWString path $ \wpath -> do
  hEx <- c_LoadLibraryExW wpath nullPtr searchDefaultDirs
  h <- if hEx /= nullPtr then pure hEx else c_LoadLibraryW wpath
  if h == nullPtr
    then do
      code <- c_GetLastError
      pure (Left (LibraryNotFound path ("Win32 error " <> show code)))
    else pure (Right (Library h path))

closeLibrary :: Library -> IO ()
closeLibrary = void . c_FreeLibrary . libHandle

withLibrary :: FilePath -> (Library -> IO a) -> IO (Either DynError a)
withLibrary path act = do
  r <- loadLibrary path
  case r of
    Left e -> pure (Left e)
    Right lib -> (Right <$> act lib) `finally` closeLibrary lib

resolveSym :: Library -> String -> IO (Either DynError (FunPtr a))
resolveSym lib name = withCString name $ \cname -> do
  fp <- c_GetProcAddress (libHandle lib) cname
  if fp == nullFunPtr
    then pure (Left (SymbolNotFound (libraryPath lib) name))
    else pure (Right (castFunPtr fp))

resolveOptional :: Library -> String -> IO (Maybe (FunPtr a))
resolveOptional lib name = either (const Nothing) Just <$> resolveSym lib name

-- | Register an extra DLL search directory for subsequent 'loadLibrary'
-- calls. The directory must be an absolute path (AddDllDirectory refuses
-- relative ones). Returns 'False' if the OS refused it.
addSearchDir :: FilePath -> IO Bool
addSearchDir dir = withCWString dir $ \wdir -> do
  cookie <- c_AddDllDirectory wdir
  pure (cookie /= nullPtr)
