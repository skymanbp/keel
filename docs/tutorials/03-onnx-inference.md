# Tutorial 3 — Train in scikit-learn, run in Haskell with keel-onnx

The headline workflow: models are trained wherever training is good
(Python), exported to ONNX, and executed in Haskell — on Windows, with
no C toolchain, through the MIT-licensed official ONNX Runtime.

## One-time setup

```
$ keel setup onnx     # SHA-256-pinned official archive -> per-user dir
$ keel doctor
[ok] keel-onnx (ONNX Runtime)  ONNX Runtime 1.24.4  @ .../keel/native/onnxruntime/...
```

(Or point `KEEL_ONNXRUNTIME` at an existing installation.)

## Python side: train and export

```python
import numpy as np
from sklearn.linear_model import LogisticRegression
from skl2onnx import to_onnx

X, y = ...                                  # your training data
clf = LogisticRegression().fit(X, y)
onx = to_onnx(clf, X.astype(np.float32),
              options={id(clf): {'zipmap': False}})  # plain tensors out
open("model.onnx", "wb").write(onx.SerializeToString())
```

## Haskell side: load and predict

```haskell
import Data.ByteString qualified as BS
import Data.Vector.Storable qualified as VS
import Keel.Onnx

main :: IO ()
main = do
  Right ort <- loadOnnxRuntime
  model <- BS.readFile "model.onnx"
  withOrtEnv ort $ \env ->
    withSessionFromBytes env model $ \sess -> do
      -- never hard-code names: ask the model
      [inName]            <- inputNames sess
      [labels, probs]     <- outputNames sess
      [Just info]         <- inputInfos sess
      print (tiShape info)              -- e.g. [-1, 4]: dynamic batch of 4 features

      let xs = VS.fromList [5.1, 3.5, 1.4, 0.2] :: VS.Vector Float
      [labelT, probT] <- runTensors sess [(inName, [1, 4], xs)] [labels, probs]
      case (labelT, probT) of
        (Int64Tensor _ ls, FloatTensor _ ps) ->
          putStrLn ("class " <> show (VS.head ls) <> ", probs " <> show (VS.toList ps))
        other -> error ("unexpected output types: " <> show other)
```

Everything is bracket-managed; inputs are borrowed zero-copy into ORT,
outputs are copied out and their `OrtValue`s released before `runTensors`
returns — results are plain Haskell data with no tie to the runtime's
lifetime.

## What the CI demo proves

On all three OSes, every run: a LinearRegression and a
LogisticRegression are trained in scikit-learn, exported with skl2onnx,
executed through keel-onnx, and the predictions are compared against
Python's own onnxruntime — **agreement is bit-for-bit 0.0** (the gate is
1e-6), labels match exactly, and a 500-inference leak gate keeps the
buffer handling honest.

*Working code:*
[`packages/keel-onnx/test/Demo.hs`](../../packages/keel-onnx/test/Demo.hs).
