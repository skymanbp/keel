-- | POSIX implementation over @dlopen@\/@dlsym@\/@dlclose@ (via the unix
-- package). Search paths follow the platform loader: rpath,
-- @LD_LIBRARY_PATH@ \/ @DYLD_LIBRARY_PATH@, then system defaults.
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

import Control.Exception (IOException, finally, try)
import Foreign.Ptr (FunPtr, castFunPtr)
import qualified System.Posix.DynamicLinker as DL

-- | A loaded shared library. Constructor deliberately not exported.
data Library = Library
  { libDL :: !DL.DL
  , libraryPath :: !FilePath
    -- ^ The path\/name the library was requested as.
  }

data DynError
  = LibraryNotFound FilePath String
    -- ^ Library could not be loaded; the 'String' carries OS detail.
  | SymbolNotFound FilePath String
    -- ^ The named symbol is absent from the named library.
  deriving (Eq, Show)

loadLibrary :: FilePath -> IO (Either DynError Library)
loadLibrary path = do
  r <- try (DL.dlopen path [DL.RTLD_NOW, DL.RTLD_LOCAL])
  pure $ case r of
    Left (e :: IOException) -> Left (LibraryNotFound path (show e))
    Right dl -> Right (Library dl path)

closeLibrary :: Library -> IO ()
closeLibrary = DL.dlclose . libDL

withLibrary :: FilePath -> (Library -> IO a) -> IO (Either DynError a)
withLibrary path act = do
  r <- loadLibrary path
  case r of
    Left e -> pure (Left e)
    Right lib -> (Right <$> act lib) `finally` closeLibrary lib

resolveSym :: Library -> String -> IO (Either DynError (FunPtr a))
resolveSym lib name = do
  r <- try (DL.dlsym (libDL lib) name)
  pure $ case r of
    Left (e :: IOException) ->
      Left (SymbolNotFound (libraryPath lib) (name <> ": " <> show e))
    Right fp -> Right (castFunPtr fp)

resolveOptional :: Library -> String -> IO (Maybe (FunPtr a))
resolveOptional lib name = either (const Nothing) Just <$> resolveSym lib name

-- | POSIX loaders take their search path from the environment
-- (@LD_LIBRARY_PATH@\/rpath) before process start; there is no runtime
-- registration equivalent to Windows' AddDllDirectory. Documented no-op.
addSearchDir :: FilePath -> IO Bool
addSearchDir _ = pure False
