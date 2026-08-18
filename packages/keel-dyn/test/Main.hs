-- | Smoke tests: real dlopen/resolve/call round-trip on each OS, the
-- negative paths (missing library, missing symbol), and the
-- "Keel.Dyn.Locate" search-order contract.
module Main (main) where

import Control.Exception (try)
import Control.Monad (unless)
import Data.Word (Word64)
import Foreign.Ptr (FunPtr)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.Info (os)

import Keel.Dyn
import Keel.Dyn.Locate

foreign import ccall "dynamic" mkTick :: FunPtr (IO Word64) -> IO Word64
foreign import ccall "dynamic" mkCos :: FunPtr (Double -> Double) -> Double -> Double

orDie :: Show e => String -> Either e a -> IO a
orDie ctx = either (\e -> fail (ctx <> ": " <> show e)) pure

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

testEnvVar :: String
testEnvVar = "KEEL_DYN_TEST_LIB"

-- The spec name is chosen so its per-user data dir cannot exist, keeping
-- the data-dir stage of locateLibrary an empty pass-through in this test.
mkSpec :: [FilePath] -> LibrarySpec
mkSpec cands = LibrarySpec
  { specName = "keel-dyn-smoke-zzz"
  , specEnvVar = testEnvVar
  , specCandidates = cands
  }

main :: IO ()
main = do
  let (libName, symName) = case os of
        "mingw32" -> ("kernel32.dll", "GetTickCount64")
        "darwin" -> ("/usr/lib/libSystem.B.dylib", "cos")
        _ -> ("libm.so.6", "cos")

  -- 1. positive path: load, resolve (via requireSym), call through the
  -- FunPtr. The resolve happens inside each branch because the FunPtr
  -- type differs per OS.
  lib <- orDie ("load " <> libName) =<< loadLibrary libName
  case os of
    "mingw32" -> do
      fp <- requireSym lib symName
      t <- mkTick fp
      expect (t > 0) "GetTickCount64 returned 0"
    _ -> do
      fp <- requireSym lib symName
      expect (abs (mkCos fp 0 - 1) < 1e-12) "cos 0 /= 1"

  -- 2. negative path: a library that cannot exist
  neg <- loadLibrary "keel-definitely-missing-library-zzz"
  expect (either (const True) (const False) neg) "bogus library loaded"

  -- 3. negative path: a symbol that cannot exist, through both interfaces
  msym <- resolveOptional lib "keel_definitely_missing_symbol_zzz"
        :: IO (Maybe (FunPtr ()))
  expect (maybe True (const False) msym) "bogus symbol resolved"
  thrown <- try (requireSym lib "keel_definitely_missing_symbol_zzz")
        :: IO (Either DynError (FunPtr ()))
  case thrown of
    Left (SymbolNotFound _ _) -> pure ()
    Left e -> fail ("requireSym threw the wrong error: " <> show e)
    Right _ -> fail "requireSym resolved a bogus symbol"

  -- 4. locate: with no override and no data dir, the system-search stage
  -- must find the library under its bare name (absolute on darwin).
  unsetEnv testEnvVar
  l1 <- orDie "locate via system search" =<< locateLibrary (mkSpec [libName])
  expect (locOrigin l1 == FromSystem libName)
    ("wrong origin: " <> show (locOrigin l1))
  closeLibrary (locLibrary l1)

  -- 5. locate: a broken explicit override must FAIL, never fall through
  -- to the system search (where the candidate would have resolved).
  setEnv testEnvVar ("keel-no-such-dir-zzz" </> "keel-no-such-lib-zzz")
  l2 <- locateLibrary (mkSpec [libName])
  expect (either (const True) (const False) l2)
    "broken override fell through to system search"
  unsetEnv testEnvVar

  -- 6. locate: env-file and env-dir overrides. Windows-only because only
  -- there is the system library's absolute location derivable portably
  -- (%SystemRoot%\System32); POSIX paths vary per distro and are covered
  -- by the publish-stage CI matrix instead.
  case os of
    "mingw32" -> do
      mroot <- lookupEnv "SystemRoot"
      case mroot of
        Nothing -> fail "SystemRoot unset; cannot exercise env override"
        Just root -> do
          let sys32 = root </> "System32"
              k32 = sys32 </> "kernel32.dll"
          setEnv testEnvVar k32
          l3 <- orDie "locate via env file" =<< locateLibrary (mkSpec ["kernel32.dll"])
          expect (locOrigin l3 == FromEnvFile k32)
            ("wrong origin: " <> show (locOrigin l3))
          closeLibrary (locLibrary l3)

          setEnv testEnvVar sys32
          l4 <- orDie "locate via env dir" =<< locateLibrary (mkSpec ["kernel32.dll"])
          expect (locOrigin l4 == FromEnvDir k32)
            ("wrong origin: " <> show (locOrigin l4))
          closeLibrary (locLibrary l4)
          unsetEnv testEnvVar
    _ -> pure ()

  closeLibrary lib
  putStrLn "keel-dyn: all smoke tests passed"
