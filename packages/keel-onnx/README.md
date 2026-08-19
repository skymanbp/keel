# keel-onnx

Inference-only bindings to ONNX Runtime's C API, resolved entirely at
run time: [keel-dyn](https://hackage.haskell.org/package/keel-dyn)
loads the official shared library, `OrtGetApiBase()` hands back the
versioned function-pointer table, and every call goes through it. No
build-time native dependency, no cbits in the shipped library.

```haskell
import Keel.Onnx
import Data.ByteString qualified as BS

main :: IO ()
main = do
  Right ort <- loadOnnxRuntime
  model <- BS.readFile "model.onnx"
  withOrtEnv ort $ \env ->
    withSessionFromBytes env model $ \sess -> do
      [inName] <- inputNames sess
      [outName] <- outputNames sess
      out <- runFloats sess [(inName, [1, 4], xs)] [outName]
      print out
```

The runtime is located by the keel search policy (`KEEL_ONNXRUNTIME`
env override, the per-user keel data dir — populated by
`keel setup onnx` from the umbrella package — then the system search
path). Absence of the runtime is an ordinary `Left`, never a crash.

The OrtApi slot indices are pinned against the vendored
`onnxruntime_c_api.h` and verified by a test-suite-only C gate; the
requested API version is the oldest whose frozen table prefix contains
every slot used, so any ONNX Runtime release serves it. Inference
results agree with Python onnxruntime to 1e-6 in the test suite, with
a leak gate over 500 inference calls.

The vendored headers are Microsoft's, MIT-licensed — see
`LICENSE.onnxruntime`.

Part of the keel workspace — see the
[project repository](https://github.com/skymanbp/keel).
