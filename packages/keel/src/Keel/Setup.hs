-- | @keel setup@: install pinned native runtimes into the per-user
-- keel directory ("Keel.Dyn.Locate"'s second search stage).
--
-- Every artifact is an /official upstream release archive/, pinned by
-- URL and SHA-256 (values computed from the downloaded archives,
-- 2026-08-18). The tools used are deliberately boring: the system's
-- @curl@ and @tar@ (Windows 10+ ships both; the System32 bsdtar also
-- unpacks zip), plus a pure-Haskell SHA-256 — keel's zero-native-deps
-- rule applies to keel itself.
--
-- Offline\/air-gapped environments skip @keel setup@ entirely: point
-- @KEEL_OPENBLAS@ \/ @KEEL_ONNXRUNTIME@ at an existing library, or drop
-- one into the keel data dir yourself.
module Keel.Setup
  ( SetupError (..)
  , setupBlas
  , setupOnnx
  ) where

import Control.Exception (Exception)
import Control.Monad (filterM, forM_, when)
import Data.ByteString.Lazy qualified as BL
import Data.Digest.Pure.SHA (sha256, showDigest)
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getTemporaryDirectory
  , listDirectory
  , removeDirectoryRecursive
  , removeFile
  )
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (dropExtension, takeFileName, (</>))
import System.Info (arch, os)
import System.Process (proc, readCreateProcessWithExitCode)

import Keel.Dyn.Locate (keelNativeDir)

-- | Why an installation could not happen.
data SetupError
  = UnsupportedPlatform String String
    -- ^ (capability, guidance) — no pinned artifact for this OS\/arch;
    -- the guidance says what to do instead.
  | DownloadFailed String String
    -- ^ (url, tool output).
  | ChecksumMismatch String String String
    -- ^ (url, expected, got) — the archive is deleted before this is
    -- thrown.
  | ExtractFailed String String
    -- ^ (archive, tool output).
  deriving (Eq, Show)

instance Exception SetupError

data Artifact = Artifact
  { artCapability :: String
    -- ^ keel data-dir name ('keelNativeDir' argument).
  , artUrl :: String
  , artSha256 :: String
    -- ^ Lowercase hex, pinned.
  , artLibSubdir :: FilePath
    -- ^ Directory inside the archive whose files become the payload.
  , artAttribution :: String
    -- ^ Upstream project + license, recorded next to the payload.
  }

-- | Install OpenBLAS (LP64) for keel-linalg. Pinned artifact exists for
-- Windows x86_64 (upstream publishes binaries only there); on other
-- platforms the package manager is the right tool and 'setupBlas'
-- returns the exact command as 'UnsupportedPlatform' guidance.
setupBlas :: IO (Either SetupError FilePath)
setupBlas = case (os, arch) of
  ("mingw32", "x86_64") ->
    install
      Artifact
        { artCapability = "openblas"
        , artUrl = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.30/OpenBLAS-0.3.30-x64.zip"
        , artSha256 = "8b04387766efc05c627e26d24797ec0d4ed4c105ec14fa7400aa84a02db22b66"
        , artLibSubdir = "bin"
        , artAttribution =
            "libopenblas.dll from OpenBLAS 0.3.30 (BSD-3-Clause), official release archive:\n\
            \https://github.com/OpenMathLib/OpenBLAS/releases/tag/v0.3.30\n"
        }
  ("linux", _) ->
    pure (Left (UnsupportedPlatform "openblas"
      "upstream publishes no Linux binaries; run: sudo apt-get install libopenblas0 (or your distro's equivalent)"))
  ("darwin", _) ->
    pure (Left (UnsupportedPlatform "openblas"
      "upstream publishes no macOS binaries; run: brew install openblas, then set KEEL_OPENBLAS=$(brew --prefix openblas)/lib/libopenblas.dylib"))
  _ ->
    pure (Left (UnsupportedPlatform "openblas" (os <> "/" <> arch <> " has no pinned artifact")))

-- | Install ONNX Runtime for keel-onnx from the official (MIT) release
-- archives: win-x64, linux-x64 and osx-arm64 are pinned.
setupOnnx :: IO (Either SetupError FilePath)
setupOnnx = case (os, arch) of
  ("mingw32", "x86_64") ->
    install (onnxArtifact "onnxruntime-win-x64-1.24.4.zip"
      "d2319fddfb6ea4db99ccc4b60c85c517bcd855721f5daa6a06d40d7cb2ee2357")
  ("linux", "x86_64") ->
    install (onnxArtifact "onnxruntime-linux-x64-1.24.4.tgz"
      "3a211fbea252c1e66290658f1b735b772056149f28321e71c308942cdb54b747")
  ("darwin", "aarch64") ->
    install (onnxArtifact "onnxruntime-osx-arm64-1.24.4.tgz"
      "93787795f47e1eee369182e43ed51b9e5da0878ab0346aecf4258979b8bba989")
  _ ->
    pure (Left (UnsupportedPlatform "onnxruntime"
      (os <> "/" <> arch <> " has no pinned artifact; official archives cover win-x64, linux-x64, osx-arm64")))
  where
    onnxArtifact file sha =
      Artifact
        { artCapability = "onnxruntime"
        , artUrl = "https://github.com/microsoft/onnxruntime/releases/download/v1.24.4/" <> file
        , artSha256 = sha
        , -- archives unpack as <basename minus .zip/.tgz>/lib/...
          artLibSubdir = dropExtension file </> "lib"
        , artAttribution =
            "ONNX Runtime 1.24.4 (MIT), official release archive:\n\
            \https://github.com/microsoft/onnxruntime/releases/tag/v1.24.4\n"
        }

-- ---------------------------------------------------------------------

install :: Artifact -> IO (Either SetupError FilePath)
install art = do
  destDir <- keelNativeDir (artCapability art)
  createDirectoryIfMissing True destDir
  tmp <- getTemporaryDirectory
  let archPath = tmp </> takeFileName (artUrl art)
      exDir = tmp </> (artCapability art <> "-keel-extract")

  (dlCode, _, dlErr) <-
    readCreateProcessWithExitCode (proc "curl" ["-fsSL", "-o", archPath, artUrl art]) ""
  case dlCode of
    ExitFailure _ -> pure (Left (DownloadFailed (artUrl art) dlErr))
    ExitSuccess -> do
      got <- showDigest . sha256 <$> BL.readFile archPath
      if got /= artSha256 art
        then do
          removeFile archPath
          pure (Left (ChecksumMismatch (artUrl art) (artSha256 art) got))
        else do
          exExists <- doesDirectoryExist exDir
          when exExists (removeDirectoryRecursive exDir)
          createDirectoryIfMissing True exDir
          t <- tarExe
          (exCode, _, exErr) <-
            readCreateProcessWithExitCode (proc t ["-xf", archPath, "-C", exDir]) ""
          case exCode of
            ExitFailure _ -> do
              removeFile archPath
              pure (Left (ExtractFailed archPath exErr))
            ExitSuccess -> do
              let srcLib = exDir </> artLibSubdir art
              entries <- listDirectory srcLib
              files <- filterM (doesFileExist . (srcLib </>)) entries
              if null files
                then do
                  removeFile archPath
                  removeDirectoryRecursive exDir
                  pure (Left (ExtractFailed archPath ("no payload files under " <> artLibSubdir art)))
                else do
                  forM_ files $ \f -> copyFile (srcLib </> f) (destDir </> f)
                  writeFile (destDir </> "ATTRIBUTION.txt") (artAttribution art)
                  removeFile archPath
                  removeDirectoryRecursive exDir
                  pure (Right destDir)

-- On Windows, PATH often puts GNU tar (MSYS/Git) first, which cannot
-- unpack zip; the System32 bsdtar can, so use it by absolute path.
tarExe :: IO FilePath
tarExe = case os of
  "mingw32" -> do
    root <- lookupEnv "SystemRoot"
    pure (maybe "tar" (\r -> r </> "System32" </> "tar.exe") root)
  _ -> pure "tar"
