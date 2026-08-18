-- | POSIX implementation over @dlopen@\/@dlsym@\/@dlclose@ (via the unix
-- package). Search paths follow the platform loader: rpath,
-- @LD_LIBRARY_PATH@ \/ @DYLD_LIBRARY_PATH@, then system defaults.
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

import Control.Exception (Exception, IOException, finally, try)
import Foreign.Ptr (FunPtr, castFunPtr)
import qualified System.Posix.DynamicLinker as DL

-- | A loaded shared library. Constructor deliberately not exported.
data Library = Library
  { libDL :: !DL.DL
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

-- | Load a shared library by bare name or path. Search order is documented
-- in "Keel.Dyn". Symbols stay private to the handle (@RTLD_LOCAL@).
loadLibrary :: FilePath -> IO (Either DynError Library)
loadLibrary = loadWith [DL.RTLD_NOW, DL.RTLD_LOCAL]

-- | Like 'loadLibrary' but with @RTLD_GLOBAL@: the library's symbols
-- become visible to everything loaded afterwards. Needed when later
-- loads expect this library's symbols to already be in the process —
-- the canonical case is @libpython@, whose extension modules
-- deliberately leave Python's symbols undefined (manylinux policy).
loadLibraryGlobal :: FilePath -> IO (Either DynError Library)
loadLibraryGlobal = loadWith [DL.RTLD_NOW, DL.RTLD_GLOBAL]

loadWith :: [DL.RTLDFlags] -> FilePath -> IO (Either DynError Library)
loadWith flags path = do
  r <- try (DL.dlopen path flags)
  pure $ case r of
    Left (e :: IOException) -> Left (LibraryNotFound path (show e))
    Right dl -> Right (Library dl path)

-- | Release the OS handle. 'FunPtr's resolved from this 'Library' must not
-- be called afterwards.
closeLibrary :: Library -> IO ()
closeLibrary = DL.dlclose . libDL

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
resolveSym lib name = do
  r <- try (DL.dlsym (libDL lib) name)
  pure $ case r of
    Left (e :: IOException) ->
      Left (SymbolNotFound (libraryPath lib) (name <> ": " <> show e))
    Right fp -> Right (castFunPtr fp)

-- | 'resolveSym' flattened to 'Maybe', for symbols whose absence is an
-- expected, degradable condition rather than an error.
resolveOptional :: Library -> String -> IO (Maybe (FunPtr a))
resolveOptional lib name = either (const Nothing) Just <$> resolveSym lib name

-- | POSIX loaders take their search path from the environment
-- (@LD_LIBRARY_PATH@\/rpath) before process start; there is no runtime
-- registration equivalent to Windows' AddDllDirectory. Documented no-op.
addSearchDir :: FilePath -> IO Bool
addSearchDir _ = pure False
