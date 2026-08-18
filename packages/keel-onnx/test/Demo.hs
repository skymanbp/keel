-- | The end-to-end deliverable: train in scikit-learn, export with
-- skl2onnx, run the model in Haskell through keel-onnx, and assert
-- prediction agreement with python's own onnxruntime to 1e-6.
--
-- The model is a LinearRegression on deterministic data (fits exactly),
-- exported to float32. Input and output names are NOT hard-coded — they
-- are read back through session introspection.
--
-- Needs python with sklearn+skl2onnx+onnxruntime, and an ONNX Runtime
-- shared library (found by the keel policy, or via the python wheel's
-- own copy as a fallback). Anything missing => SKIP unless
-- @KEEL_ONNX_REQUIRE@ is set (publish-stage CI sets it).
module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Vector.Storable qualified as VS
import System.Environment (lookupEnv, setEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)

import Keel.Onnx

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

runPy :: [String] -> IO (Maybe String)
runPy args = do
  r <- try (readProcessWithExitCode "python" args "")
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, out, _) -> Just out
    _ -> Nothing

-- The wheel's own shared library is a legitimate runtime for local
-- development; library file names differ per platform (and carry
-- version suffixes on Linux/macOS), so glob rather than guess.
findWheelOrt :: IO (Maybe FilePath)
findWheelOrt = do
  out <- runPy
    [ "-c"
    , "import onnxruntime, os, glob\n\
      \d = os.path.join(os.path.dirname(onnxruntime.__file__), 'capi')\n\
      \for pat in ('onnxruntime.dll', 'libonnxruntime.so*', 'libonnxruntime*.dylib'):\n\
      \    g = sorted(glob.glob(os.path.join(d, pat)))\n\
      \    if g:\n\
      \        print(g[0])\n\
      \        break\n"
    ]
  pure $ case fmap (filter (`notElem` "\r\n")) out of
    Just p | not (null p) -> Just p
    _ -> Nothing

trainScript :: String
trainScript =
  "import sys\n\
  \import numpy as np\n\
  \from sklearn.linear_model import LinearRegression\n\
  \from skl2onnx import to_onnx\n\
  \import onnxruntime as rt\n\
  \X = np.array([[0,0],[1,0],[0,1],[1,1],[2,1],[1,2],[3,2],[2,3]], dtype=np.float64)\n\
  \y = 3*X[:,0] - 2*X[:,1] + 1\n\
  \model = LinearRegression().fit(X, y)\n\
  \onx = to_onnx(model, X.astype(np.float32))\n\
  \with open(sys.argv[1], 'wb') as f:\n\
  \    f.write(onx.SerializeToString())\n\
  \xt = np.array([[0.5,1.5],[2,0],[1,3],[4,1]], dtype=np.float32)\n\
  \sess = rt.InferenceSession(sys.argv[1], providers=['CPUExecutionProvider'])\n\
  \iname = sess.get_inputs()[0].name\n\
  \ref = sess.run(None, {iname: xt})[0]\n\
  \print('\\n'.join('%.9g' % v for v in ref.ravel()))\n"

-- Binary LogisticRegression, zipmap disabled so the second output is a
-- plain float tensor: outputs = label (int64 [n]), probabilities
-- (float32 [n,2]). Prints labels then flattened probabilities.
classifierScript :: String
classifierScript =
  "import sys\n\
  \import numpy as np\n\
  \from sklearn.linear_model import LogisticRegression\n\
  \from skl2onnx import to_onnx\n\
  \import onnxruntime as rt\n\
  \X = np.array([[0,0],[1,0],[0,1],[1,1],[2,1],[1,2],[3,2],[2,3]], dtype=np.float64)\n\
  \y = (X[:,0] + X[:,1] > 2).astype(np.int64)\n\
  \clf = LogisticRegression().fit(X, y)\n\
  \onx = to_onnx(clf, X.astype(np.float32), options={id(clf): {'zipmap': False}})\n\
  \with open(sys.argv[1], 'wb') as f:\n\
  \    f.write(onx.SerializeToString())\n\
  \xt = np.array([[0.5,1.5],[2,0],[1,3],[4,1]], dtype=np.float32)\n\
  \sess = rt.InferenceSession(sys.argv[1], providers=['CPUExecutionProvider'])\n\
  \iname = sess.get_inputs()[0].name\n\
  \labels, probs = sess.run(None, {iname: xt})\n\
  \print(' '.join(str(int(v)) for v in labels.ravel()))\n\
  \print('\\n'.join('%.9g' % v for v in probs.ravel()))\n"

-- Same test points as the python side, row-major float32.
xTest :: VS.Vector Float
xTest = VS.fromList [0.5, 1.5, 2, 0, 1, 3, 4, 1]

main :: IO ()
main = do
  pyOk <- runPy ["-c", "import sklearn, skl2onnx, onnxruntime"]
  ortFirst <- loadOnnxRuntime
  ort <- case ortFirst of
    Right o -> pure (Just o)
    Left _ -> do
      wheel <- findWheelOrt
      case wheel of
        Nothing -> pure Nothing
        Just dll -> do
          setEnv "KEEL_ONNXRUNTIME" dll
          either (const Nothing) Just <$> loadOnnxRuntime
  required <- lookupEnv "KEEL_ONNX_REQUIRE"
  case (pyOk, ort) of
    (Just _, Just o) -> run o
    _ -> case required of
      Just v | v /= "" && v /= "0" ->
        fail "KEEL_ONNX_REQUIRE set but python stack or ONNX Runtime unavailable"
      _ ->
        putStrLn "keel-onnx-demo: SKIP - needs python(sklearn+skl2onnx+onnxruntime) and an ONNX Runtime library"

run :: Ort -> IO ()
run ort = do
  putStrLn ("ONNX Runtime version: " <> ortVersion ort)

  tmpOut <- runPy ["-c", "import tempfile; print(tempfile.gettempdir())"]
  tmp <- maybe (fail "cannot determine temp dir") (pure . filter (`notElem` "\r\n")) tmpOut
  let modelPath = tmp </> "keel-onnx-demo.onnx"

  refOut <- runPy ["-c", trainScript, modelPath]
  refs <- case refOut of
    Nothing -> fail "python train/export/reference script failed"
    Just out -> pure (map read (words out) :: [Float])
  expect (length refs == 4) ("expected 4 reference predictions, got " <> show (length refs))

  model <- BS.readFile modelPath
  withOrtEnv ort $ \env ->
    withSessionFromBytes env model $ \sess -> do
      ins <- inputNames sess
      outs <- outputNames sess
      inName <- case ins of
        [n] -> pure n
        _ -> fail ("expected 1 input, got " <> show ins)
      outName <- case outs of
        [n] -> pure n
        _ -> fail ("expected 1 output, got " <> show outs)
      putStrLn ("model interface: " <> inName <> " -> " <> outName)

      -- declared-interface introspection: float32 input [-1, 2]
      -- (dynamic batch axis), float32 output
      iinfos <- inputInfos sess
      case iinfos of
        [Just ti] -> do
          expect (tiShape ti == [-1, 2]) ("input shape decl: " <> show (tiShape ti))
          expect (tiElementType ti == 1) ("input dtype decl: " <> show (tiElementType ti))
        other -> fail ("input infos: " <> show other)

      [(shape, ys)] <- runFloats sess [(inName, [4, 2], xTest)] [outName]
      expect (shape == [4, 1]) ("output shape: " <> show shape)
      expect (VS.length ys == 4) ("output count: " <> show (VS.length ys))
      let diffs =
            [ abs (realToFrac got - realToFrac ref :: Double)
            | (got, ref) <- zip (VS.toList ys) refs
            ]
      expect (all (<= 1e-6) diffs)
        ("prediction disagreement vs python onnxruntime: " <> show diffs)
      putStrLn ("regression: max |haskell - python| = " <> show (maximum diffs) <> " <= 1e-6")

  -- Part 2: classifier with two outputs — int64 labels (exact match)
  -- and float32 probabilities (1e-6), through runTensors' typed path.
  let clfPath = tmp </> "keel-onnx-demo-clf.onnx"
  clfOut <- runPy ["-c", classifierScript, clfPath]
  (refLabels, refProbs) <- case fmap lines clfOut of
    Just (labelLine : probLines) ->
      pure
        ( map read (words labelLine) :: [Int]
        , map read (concatMap words probLines) :: [Float]
        )
    _ -> fail "python classifier script failed"
  expect (length refLabels == 4) ("expected 4 reference labels, got " <> show (length refLabels))
  expect (length refProbs == 8) ("expected 8 reference probabilities, got " <> show (length refProbs))

  clfModel <- BS.readFile clfPath
  withOrtEnv ort $ \env ->
    withSessionFromBytes env clfModel $ \sess -> do
      ins <- inputNames sess
      outs <- outputNames sess
      inName <- case ins of
        [n] -> pure n
        _ -> fail ("classifier: expected 1 input, got " <> show ins)
      (labelName, probName) <- case outs of
        [a, b] -> pure (a, b)
        _ -> fail ("classifier: expected 2 outputs, got " <> show outs)
      putStrLn ("classifier interface: " <> inName <> " -> " <> labelName <> ", " <> probName)

      [labelT, probT] <- runTensors sess [(inName, [4, 2], xTest)] [labelName, probName]
      case labelT of
        Int64Tensor lshape ls -> do
          expect (lshape == [4]) ("label shape: " <> show lshape)
          expect (map fromIntegral (VS.toList ls) == refLabels)
            ("labels: " <> show (VS.toList ls) <> " /= " <> show refLabels)
        t -> fail ("label output is not int64: " <> show t)
      case probT of
        FloatTensor pshape ps -> do
          expect (pshape == [4, 2]) ("prob shape: " <> show pshape)
          let pdiffs =
                [ abs (realToFrac got - realToFrac ref :: Double)
                | (got, ref) <- zip (VS.toList ps) refProbs
                ]
          expect (all (<= 1e-6) pdiffs)
            ("probability disagreement: " <> show pdiffs)
          putStrLn ("classifier: max |haskell - python| = " <> show (maximum pdiffs) <> " <= 1e-6")
        t -> fail ("probability output is not float32: " <> show t)

  -- The Ort handle is deliberately NOT closed: onnxruntime owns thread
  -- pools and unloading the DLL at process end is the safe path.
  putStrLn "keel-onnx-demo: regression + classifier agreed with python to 1e-6"
