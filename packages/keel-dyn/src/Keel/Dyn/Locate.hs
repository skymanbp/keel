-- | Locate-and-load policy for native capabilities.
--
-- 'locateLibrary' documents and implements keel's search order:
--
-- 1. __Environment override__ ('specEnvVar'). If the variable is set and
--    non-empty it is authoritative: a file path is loaded exactly as
--    given, a directory is searched for 'specCandidates'. Failure of an
--    explicit override is an error — it deliberately does /not/ fall
--    through to the later stages, because silent fallback past a value
--    the user set by hand is undiagnosable.
-- 2. __Per-user data directory__ ('keelNativeDir'):
--    @~\/.local\/share\/keel\/native\/\<name\>@ per the XDG spec, or
--    @%APPDATA%\\keel\\native\\\<name\>@ on Windows. This is where
--    @keel setup@ installs checksum-pinned libraries. On Windows the
--    directory is also registered via 'addSearchDir' before loading, so
--    the library's transitive DLL dependencies resolve from it. A
--    candidate that exists here but fails to load is an error, not a
--    fallthrough, for the same reason as above.
-- 3. __System search__: each candidate is tried as a bare name through
--    the operating system's default lookup (PATH \/ @ld.so@ cache \/
--    @DYLD_*@ \/ System32).
module Keel.Dyn.Locate
  ( LibrarySpec (..)
  , Located (..)
  , Origin (..)
  , locateLibrary
  , keelNativeDir
  ) where

import Control.Monad (filterM)
import System.Directory
  ( XdgDirectory (XdgData)
  , doesDirectoryExist
  , doesFileExist
  , getXdgDirectory
  )
import System.Environment (lookupEnv)
import System.FilePath ((</>))

import Keel.Dyn.Platform

-- | What to look for and where the user may override it.
data LibrarySpec = LibrarySpec
  { specName :: String
    -- ^ Capability name, e.g. @\"openblas\"@. Names the subdirectory of
    -- the keel data dir and appears in error messages.
  , specEnvVar :: String
    -- ^ Override variable, e.g. @\"KEEL_OPENBLAS\"@. May point at a
    -- library file or at a directory containing one of the candidates.
  , specCandidates :: [FilePath]
    -- ^ Platform-appropriate file names tried in order, e.g.
    -- @[\"libopenblas.dll\"]@ \/ @[\"libopenblas.so.0\", \"libopenblas.so\"]@.
    -- The caller chooses per platform ('System.Info.os').
  }
  deriving (Eq, Show)

-- | Where a successfully located library came from — 'Keel.Doctor' level
-- diagnostics report this verbatim.
data Origin
  = FromEnvFile FilePath
    -- ^ The override variable pointed directly at this file.
  | FromEnvDir FilePath
    -- ^ Loaded from the directory the override variable pointed at.
  | FromDataDir FilePath
    -- ^ Loaded from the per-user keel data directory.
  | FromSystem FilePath
    -- ^ Resolved by the OS default search under this bare name.
  deriving (Eq, Show)

-- | A successfully located and loaded library, tagged with where the
-- search found it.
data Located = Located
  { locLibrary :: Library
  , locOrigin :: Origin
  }

-- | The per-user directory for one capability's native libraries:
-- XDG data dir (Windows: @%APPDATA%@) @\/keel\/native\/\<name\>@.
-- Derived at run time; never assumed to exist.
keelNativeDir :: String -> IO FilePath
keelNativeDir name = getXdgDirectory XdgData ("keel" </> "native" </> name)

-- | Locate and load a native library following the search order in the
-- module header. On success the 'Origin' says which stage matched.
locateLibrary :: LibrarySpec -> IO (Either DynError Located)
locateLibrary spec = do
  mOverride <- lookupEnv (specEnvVar spec)
  case mOverride of
    Just v | not (null v) -> fromEnv spec v
    _ -> do
      dir <- keelNativeDir (specName spec)
      fromDataDir spec dir

-- The override is authoritative: no fallthrough on failure.
fromEnv :: LibrarySpec -> FilePath -> IO (Either DynError Located)
fromEnv spec v = do
  isDir <- doesDirectoryExist v
  if isDir
    then do
      found <- firstExistingIn v (specCandidates spec)
      case found of
        Nothing ->
          pure . Left . LibraryNotFound v $
            specEnvVar spec
              <> " is a directory containing none of "
              <> show (specCandidates spec)
        Just path -> do
          _ <- addSearchDir v
          fmap (\lib -> Located lib (FromEnvDir path)) <$> loadLibrary path
    else fmap (\lib -> Located lib (FromEnvFile v)) <$> loadLibrary v

-- A candidate present in the data dir must load; only absence falls
-- through to the system search.
fromDataDir :: LibrarySpec -> FilePath -> IO (Either DynError Located)
fromDataDir spec dir = do
  found <- firstExistingIn dir (specCandidates spec)
  case found of
    Just path -> do
      _ <- addSearchDir dir
      fmap (\lib -> Located lib (FromDataDir path)) <$> loadLibrary path
    Nothing -> fromSystem spec (specCandidates spec)

fromSystem :: LibrarySpec -> [FilePath] -> IO (Either DynError Located)
fromSystem spec [] =
  pure . Left . LibraryNotFound (specName spec) $
    "none of "
      <> show (specCandidates spec)
      <> " found via "
      <> specEnvVar spec
      <> ", the keel data dir, or the system search path"
fromSystem spec (c : cs) = do
  r <- loadLibrary c
  case r of
    Right lib -> pure (Right (Located lib (FromSystem c)))
    Left _ -> fromSystem spec cs

firstExistingIn :: FilePath -> [FilePath] -> IO (Maybe FilePath)
firstExistingIn dir names = do
  hits <- filterM doesFileExist (map (dir </>) names)
  pure $ case hits of
    (h : _) -> Just h
    [] -> Nothing
