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

-- The wheel's own onnxruntime.dll is a legitimate runtime for local
-- development; publish-stage CI installs the official archive instead.
findWheelOrt :: IO (Maybe FilePath)
findWheelOrt = do
  out <- runPy
    [ "-c"
    , "import onnxruntime, os\n\
      \print(os.path.join(os.path.dirname(onnxruntime.__file__), 'capi', 'onnxruntime.dll' if os.name == 'nt' else 'libonnxruntime.so'))\n"
    ]
  pure (fmap (filter (`notElem` "\r\n")) out)

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

      [(shape, ys)] <- runFloats sess [(inName, [4, 2], xTest)] [outName]
      expect (shape == [4, 1]) ("output shape: " <> show shape)
      expect (VS.length ys == 4) ("output count: " <> show (VS.length ys))
      let diffs =
            [ abs (realToFrac got - realToFrac ref :: Double)
            | (got, ref) <- zip (VS.toList ys) refs
            ]
      expect (all (<= 1e-6) diffs)
        ("prediction disagreement vs python onnxruntime: " <> show diffs)
      putStrLn ("max |haskell - python| = " <> show (maximum diffs) <> " <= 1e-6")

  -- The Ort handle is deliberately NOT closed: onnxruntime owns thread
  -- pools and unloading the DLL at process end is the safe path.
  putStrLn "keel-onnx-demo: sklearn -> skl2onnx -> Haskell agreed to 1e-6"
