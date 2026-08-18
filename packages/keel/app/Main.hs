-- | The @keel@ executable: @keel doctor@ (and, later, @keel setup@).
module Main (main) where

import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Keel.Doctor

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> runDoctor
    ["doctor"] -> runDoctor
    ("setup" : _) -> do
      hPutStrLn stderr
        "keel setup is not implemented yet. Meanwhile: install the native\n\
        \library yourself and point KEEL_OPENBLAS / KEEL_ONNXRUNTIME at it,\n\
        \or drop it into the per-user keel data dir (see keel-dyn's\n\
        \Keel.Dyn.Locate documentation for the exact directory)."
      exitFailure
    _ -> do
      hPutStrLn stderr "usage: keel [doctor]"
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
