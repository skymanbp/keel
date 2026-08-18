-- | Smoke tests: real dlopen/resolve/call round-trip on each OS, plus the
-- negative paths (missing library, missing symbol).
module Main (main) where

import Control.Monad (unless)
import Data.Word (Word64)
import Foreign.Ptr (FunPtr)
import System.Info (os)

import Keel.Dyn

foreign import ccall "dynamic" mkTick :: FunPtr (IO Word64) -> IO Word64
foreign import ccall "dynamic" mkCos :: FunPtr (Double -> Double) -> Double -> Double

orDie :: Show e => String -> Either e a -> IO a
orDie ctx = either (\e -> fail (ctx <> ": " <> show e)) pure

main :: IO ()
main = do
  let (libName, symName) = case os of
        "mingw32" -> ("kernel32.dll", "GetTickCount64")
        "darwin" -> ("/usr/lib/libSystem.B.dylib", "cos")
        _ -> ("libm.so.6", "cos")

  -- positive path: load, resolve, call through the FunPtr. The resolve
  -- happens inside each branch because the FunPtr type differs per OS.
  lib <- orDie ("load " <> libName) =<< loadLibrary libName
  case os of
    "mingw32" -> do
      fp <- orDie ("resolve " <> symName) =<< resolveSym lib symName
      t <- mkTick fp
      unless (t > 0) (fail "GetTickCount64 returned 0")
    _ -> do
      fp <- orDie ("resolve " <> symName) =<< resolveSym lib symName
      unless (abs (mkCos fp 0 - 1) < 1e-12) (fail "cos 0 /= 1")

  -- negative path: a library that cannot exist
  neg <- loadLibrary "keel-definitely-missing-library-zzz"
  case neg of
    Right _ -> fail "bogus library loaded"
    Left _ -> pure ()

  -- negative path: a symbol that cannot exist
  msym <- resolveOptional lib "keel_definitely_missing_symbol_zzz"
        :: IO (Maybe (FunPtr ()))
  case msym of
    Just _ -> fail "bogus symbol resolved"
    Nothing -> pure ()

  closeLibrary lib
  putStrLn "keel-dyn: all smoke tests passed"
