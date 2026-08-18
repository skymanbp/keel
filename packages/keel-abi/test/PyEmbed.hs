-- | Shared harness for conformance tests that embed CPython in-process
-- through keel-dyn: discovery (out of process), load, init, script
-- runner, finalize, and the SKIP-vs-required policy.
module PyEmbed
  ( RunScript
  , withEmbeddedPython
  , expect
  , addr
  ) where

import Control.Exception (IOException, try)
import Control.Monad (unless, when)
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, Ptr, ptrToIntPtr)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

import Keel.Dyn

-- | @runScript label script@ — run python source, fail the test with
-- @label@ if it raises (the traceback goes to stderr).
type RunScript = String -> String -> IO ()

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

-- | A pointer, rendered for splicing into python source as an integer.
addr :: Ptr a -> String
addr = show . ptrToIntPtr

foreign import ccall safe "dynamic"
  mkPyInitEx :: FunPtr (CInt -> IO ()) -> CInt -> IO ()

foreign import ccall safe "dynamic"
  mkPyRun :: FunPtr (CString -> IO CInt) -> CString -> IO CInt

foreign import ccall safe "dynamic"
  mkPyFinalize :: FunPtr (IO CInt) -> IO CInt

runPy :: String -> [String] -> IO (Maybe String)
runPy exe args = do
  r <- try (readProcessWithExitCode exe args "")
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, out, _) -> Just (filter (`notElem` "\r\n") out)
    _ -> Nothing

-- Find an interpreter that can import the given module, and the shared
-- library behind it. Out of process, so a broken python cannot kill us.
-- POSIX candidates cover plain builds (LIBDIR + INSTSONAME/LDLIBRARY)
-- and macOS framework builds, where INSTSONAME is framework-relative
-- and must be joined to PYTHONFRAMEWORKPREFIX instead.
findPython :: String -> IO (Maybe FilePath)
findPython pymodule = go ["python", "python3"]
  where
    dllScript =
      "import sys, sysconfig, os\n\
      \if os.name == 'nt':\n\
      \    print(os.path.join(sys.base_prefix, 'python%d%d.dll' % sys.version_info[:2]))\n\
      \else:\n\
      \    g = sysconfig.get_config_var\n\
      \    libdir = g('LIBDIR') or ''\n\
      \    cands = [os.path.join(libdir, n) for n in (g('INSTSONAME') or '', g('LDLIBRARY') or '') if n]\n\
      \    fw = g('PYTHONFRAMEWORKPREFIX') or ''\n\
      \    if fw:\n\
      \        cands += [os.path.join(fw, n) for n in (g('INSTSONAME') or '', g('LDLIBRARY') or '') if n]\n\
      \    print(next((c for c in cands if os.path.exists(c)), ''))\n"
    go [] = pure Nothing
    go (exe : rest) = do
      ok <- runPy exe ["-c", "import " <> pymodule]
      case ok of
        Nothing -> go rest
        Just _ -> do
          p <- runPy exe ["-c", dllScript]
          pure $ case p of
            Just path | not (null path) -> Just path
            _ -> Nothing

-- | Load CPython through keel-dyn and hand a 'RunScript' to the action;
-- initialize before, finalize after. When no interpreter that imports
-- @pymodule@ exists, SKIP (print why, exit 0) — unless the named env
-- var is set non-empty\/non-zero, which turns absence into failure
-- (publish-stage CI sets it).
withEmbeddedPython
  :: String -- ^ python module the test needs, e.g. @\"pyarrow\"@
  -> String -- ^ require-env-var, e.g. @\"KEEL_ABI_REQUIRE_PYARROW\"@
  -> (RunScript -> IO ())
  -> IO ()
withEmbeddedPython pymodule requireVar action = do
  found <- findPython pymodule
  required <- lookupEnv requireVar
  case found of
    Nothing -> case required of
      Just v | v /= "" && v /= "0" ->
        fail (requireVar <> " set but no usable python+" <> pymodule <> " found")
      _ -> putStrLn ("SKIP - no usable python+" <> pymodule <> " on this machine")
    Just dll -> do
      -- RTLD_GLOBAL: C extension modules (manylinux policy) leave
      -- Python's own symbols undefined and need them process-visible
      lib <- either (\e -> fail ("load python: " <> show e)) pure =<< loadLibraryGlobal dll
      pyInitEx <- requireSym lib "Py_InitializeEx"
      pyRun <- requireSym lib "PyRun_SimpleString"
      pyFin <- requireSym lib "Py_FinalizeEx"
      mkPyInitEx pyInitEx 0
      let runScript label script = do
            rc <- withCString script (mkPyRun pyRun)
            expect (rc == 0) (label <> ": python script failed (traceback above)")
      action runScript
      fin <- mkPyFinalize pyFin
      when (fin /= 0) (putStrLn "note: Py_FinalizeEx reported errors (ignored)")
      closeLibrary lib
