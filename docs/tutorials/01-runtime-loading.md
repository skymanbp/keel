# Tutorial 1 — Loading native libraries at run time with keel-dyn

keel's founding rule is **zero build-time native dependencies**: no keel
package links against a C library, so `cabal install` can never fail on a
missing one. Everything native is loaded at run time through `keel-dyn`.

## Loading and calling a function

```haskell
import Foreign.Ptr (FunPtr)
import Data.Word (Word64)
import Keel.Dyn

-- Wrap a resolved pointer as a callable Haskell function
foreign import ccall "dynamic" mkTick :: FunPtr (IO Word64) -> IO Word64

main :: IO ()
main = do
  Right lib <- loadLibrary "kernel32.dll"   -- dlopen("libm.so.6") on Linux
  fp <- requireSym lib "GetTickCount64"
  t  <- mkTick fp
  print t
  closeLibrary lib
```

`loadLibrary` returns `Either DynError Library` — a missing library is an
ordinary value, not a crash. `requireSym` throws `SymbolNotFound` for
symbols that must exist; use `resolveOptional` for symbols whose absence
you want to degrade gracefully.

## The search policy

`Keel.Dyn.Locate.locateLibrary` implements the search order every keel
capability uses:

1. an **environment override** (e.g. `KEEL_OPENBLAS`) — authoritative,
   never falls through silently;
2. the **per-user keel data dir** (`~/.local/share/keel/native/<name>` /
   `%APPDATA%\keel\native\<name>`), where `keel setup` installs things;
3. the **system search path** (PATH / `ld.so` cache / System32).

```haskell
import Keel.Dyn.Locate

spec :: LibrarySpec
spec = LibrarySpec
  { specName = "openblas"
  , specEnvVar = "KEEL_OPENBLAS"
  , specCandidates = ["libopenblas.dll"]  -- pick per System.Info.os
  }

main = do
  r <- locateLibrary spec
  case r of
    Right located -> print (locOrigin located)  -- FromEnvFile / FromDataDir / FromSystem
    Left err      -> print err
```

The `Origin` tag is what `keel doctor` prints — you always know *which*
library answered.

## Capability records

Resolve every function once at load time into a record of `FunPtr`s;
optional symbols become `Maybe` fields so a missing symbol degrades one
operation, not the library:

```haskell
data BlasOps = BlasOps
  { ddot   :: FunPtr CblasDdotT           -- required
  , sbgemm :: Maybe (FunPtr CblasSbgemmT) -- newer builds only
  }

openBlas :: Library -> IO (Capability BlasOps)
openBlas lib = do
  ops <- BlasOps <$> requireSym lib "cblas_ddot"
                 <*> resolveOptional lib "cblas_sbgemm"
  pure (Capability lib "version-string-here" ops)
```

This is exactly how `keel-linalg` and `keel-onnx` are built.

## Sharp edges handled for you

- Windows loads use `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS` (CWD excluded — a
  classic DLL-planting hazard), with the DLL's own directory added for
  absolute paths so multi-DLL packages find their siblings.
- `loadLibraryGlobal` exposes a library's symbols to later loads
  (`RTLD_GLOBAL`) — needed e.g. when embedding CPython, whose extension
  modules expect Python's symbols to be process-visible.

*Working code these snippets come from:*
[`packages/keel-dyn/test/Main.hs`](../../packages/keel-dyn/test/Main.hs)
(runs in CI on all three OSes).
