-- | Doctor sanity: the diagnosis runs to completion on any machine,
-- the two pure capabilities always report Available, and the renderer
-- produces a line (plus fix line where applicable) per capability.
-- Whether BLAS/ONNX are Available depends on the machine, so those
-- statuses are only checked for consistency, not for a fixed value.
module Main (main) where

import Control.Monad (forM_, unless)

import Keel.Doctor

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

main :: IO ()
main = do
  reports <- diagnose
  expect (length reports == 4) ("expected 4 capability reports, got " <> show (length reports))

  let byName n = filter ((== n) . capName) reports
  expect (map capStatus (byName "keel-dyn") == [Available]) "keel-dyn not Available"
  expect (map capStatus (byName "keel-abi") == [Available]) "keel-abi not Available"

  forM_ reports $ \r -> do
    expect (not (null (capDetail r))) (capName r <> ": empty detail")
    case capStatus r of
      Available -> pure ()
      _ -> expect (capFix r /= Nothing) (capName r <> ": non-available without a fix")

  let rendered = renderReports reports
  expect (length (lines rendered) >= 4) "renderer lost capability lines"
  putStrLn rendered
  putStrLn ("keel-doctor-test: diagnosis completed ("
    <> show (length (filter ((== Available) . capStatus) reports))
    <> "/4 available on this machine)")
