# keel-dyn

Load native shared libraries at run time, cross-platform:
`LoadLibraryExW`/`GetProcAddress` on Windows, `dlopen`/`dlsym` elsewhere.

This package is the keystone of the [keel](https://github.com/skymanbp/keel)
project: every native capability (OpenBLAS, ONNX Runtime, ...) is resolved
at run time through it, so no keel package carries a build-time C
dependency and `cabal install` can never fail on a missing native library.

```haskell
import Keel.Dyn

main :: IO ()
main = do
  r <- withLibrary "libcrypto.so.3" $ \lib -> do
    Right fp <- resolveSym lib "OpenSSL_version_num"
    callVersionNum fp   -- your own "dynamic" wrapper for the C signature
  print r
```

`Keel.Dyn.Locate` adds the keel search policy on top: an env-var
override, the per-user keel data directory, then the system search
path. On Windows the loader never consults the current directory
(DLL-planting hazard); `PATH` is walked explicitly instead.

Failure is data, not an exception: loading and symbol resolution return
`Either DynError`.

Part of the keel workspace — see the
[project repository](https://github.com/skymanbp/keel) for the other
packages (keel-abi, keel-linalg, keel-onnx, and the keel umbrella).
