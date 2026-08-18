-- | Shared test harness: find a standard-symbol OpenBLAS and pin it.
--
-- Discovery order: 'openBackend' (env \/ data dir \/ system search); if
-- that misses, a python site-packages sweep for a wheel-bundled stock
-- OpenBLAS (faiss ships one on Windows; numpy\/scipy wheels are
-- symbol-renamed and useless here) is tried through the @KEEL_OPENBLAS@
-- override. No backend found => SKIP (exit 0) with the original
-- failure printed, unless the given require-env-var is set —
-- publish-stage CI sets it with a stock OpenBLAS installed.
module TestBackend (withTestBackend) where

import Control.Exception (IOException, finally, try)
import System.Environment (lookupEnv, setEnv)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

import Keel.Linalg

findWheelOpenblas :: IO (Maybe FilePath)
findWheelOpenblas = do
  r <- try (readProcessWithExitCode "python" ["-c", script] "")
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, out, _) | not (null cleaned) -> Just cleaned
      where cleaned = filter (`notElem` "\r\n") out
    _ -> Nothing
  where
    script =
      "import glob, os, sysconfig\n\
      \sp = sysconfig.get_paths()['purelib']\n\
      \g = glob.glob(os.path.join(sp, 'faiss_cpu.libs', 'libopenblas*.dll'))\n\
      \print(g[0] if g else '')\n"

withTestBackend :: String -> (Backend -> IO ()) -> IO ()
withTestBackend requireVar action = do
  first <- openBackend
  case first of
    Right be -> action be `finally` closeBackend be
    Left firstErr -> do
      wheel <- findWheelOpenblas
      second <- case wheel of
        Nothing -> pure Nothing
        Just dll -> do
          setEnv "KEEL_OPENBLAS" dll
          either (const Nothing) Just <$> openBackend
      required <- lookupEnv requireVar
      case second of
        Just be -> action be `finally` closeBackend be
        Nothing -> case required of
          Just v | v /= "" && v /= "0" ->
            fail (requireVar <> " set but no usable OpenBLAS found: " <> show firstErr)
          _ ->
            putStrLn ("SKIP - no standard-symbol OpenBLAS on this machine ("
              <> show firstErr <> ")")
