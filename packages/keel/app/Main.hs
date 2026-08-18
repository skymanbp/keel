-- | The @keel@ executable: @keel doctor@ and @keel setup {blas,onnx}@.
module Main (main) where

import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Keel.Doctor
import Keel.Setup

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> runDoctor
    ["doctor"] -> runDoctor
    ["setup", "blas"] -> runSetup "OpenBLAS" setupBlas
    ["setup", "onnx"] -> runSetup "ONNX Runtime" setupOnnx
    _ -> do
      hPutStrLn stderr "usage: keel [doctor | setup blas | setup onnx]"
      exitFailure

runDoctor :: IO ()
runDoctor = do
  reports <- diagnose
  putStrLn "keel doctor\n"
  putStr (renderReports reports)
  if allAvailable reports
    then putStrLn "\nall capabilities available"
    else do
      putStrLn "\nsome capabilities need attention (see fixes above)"
      exitFailure

runSetup :: String -> IO (Either SetupError FilePath) -> IO ()
runSetup what act = do
  putStrLn ("installing " <> what <> " (official archive, SHA-256 pinned) ...")
  r <- act
  case r of
    Right dir -> do
      putStrLn ("installed to " <> dir)
      putStrLn "run 'keel doctor' to verify"
    Left (UnsupportedPlatform _ guidance) -> do
      hPutStrLn stderr ("not available for this platform: " <> guidance)
      exitFailure
    Left err -> do
      hPutStrLn stderr ("setup failed: " <> show err)
      exitFailure
