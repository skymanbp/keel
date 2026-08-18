-- | @keel doctor@: probe every keel capability on this machine and say
-- exactly what resolved, what did not, and the one command that fixes
-- each gap. Pure diagnosis — nothing is downloaded or modified.
module Keel.Doctor
  ( CapStatus (..)
  , CapabilityReport (..)
  , diagnose
  , renderReports
  , allAvailable
  ) where

import Keel.Dyn (capLibrary, libraryPath)
import Keel.Linalg
  ( BackendError (..)
  , backendConfig
  , closeBackend
  , openBackend
  )
import Keel.Onnx (OnnxError (..), loadOnnxRuntime, ortVersion)

-- | Outcome of probing one capability.
data CapStatus
  = Available
    -- ^ Resolved and answered a version probe.
  | Missing
    -- ^ Nothing found by the search policy; installable.
  | Broken
    -- ^ Something was found but is unusable (wrong build, too old,
    -- symbols absent).
  deriving (Eq, Show)

-- | One line of the doctor's report.
data CapabilityReport = CapabilityReport
  { capName :: String
  , capStatus :: CapStatus
  , capDetail :: String
    -- ^ Version\/config\/path on success; the reason otherwise.
  , capFix :: Maybe String
    -- ^ The one command that fixes it, when there is one.
  }
  deriving (Eq, Show)

-- | Probe everything. Never throws; each probe folds its failure into
-- the report.
diagnose :: IO [CapabilityReport]
diagnose =
  sequence
    [ pure dynReport
    , pure abiReport
    , blasReport
    , onnxReport
    ]

dynReport :: CapabilityReport
dynReport =
  CapabilityReport
    "keel-dyn"
    Available
    "pure Haskell over the OS loader; no native dependency"
    Nothing

abiReport :: CapabilityReport
abiReport =
  CapabilityReport
    "keel-abi"
    Available
    "frozen C ABI structs, hand-laid-out; no native dependency"
    Nothing

blasFix :: Maybe String
blasFix = Just "keel setup blas   (or point KEEL_OPENBLAS at a stock LP64 libopenblas)"

blasReport :: IO CapabilityReport
blasReport = do
  r <- openBackend
  case r of
    Right be -> do
      let detail = backendConfig be <> "  @ " <> libraryPath (capLibrary be)
      closeBackend be
      pure (CapabilityReport "keel-linalg (OpenBLAS)" Available detail Nothing)
    Left err ->
      pure $ case err of
        BackendNotFound _ ->
          CapabilityReport "keel-linalg (OpenBLAS)" Missing
            "no OpenBLAS found via KEEL_OPENBLAS, the keel data dir, or the system search path"
            blasFix
        BackendNotOpenBLAS p ->
          CapabilityReport "keel-linalg (OpenBLAS)" Broken
            ("library at " <> p <> " exports no openblas_get_config; only OpenBLAS is supported")
            blasFix
        BackendILP64 cfg ->
          CapabilityReport "keel-linalg (OpenBLAS)" Broken
            ("ILP64 build refused (would corrupt silently): " <> cfg)
            blasFix
        BackendMissingSymbol e ->
          CapabilityReport "keel-linalg (OpenBLAS)" Broken
            ("required symbol absent (symbol-renamed or LAPACKE-less build): " <> show e)
            blasFix

onnxFix :: Maybe String
onnxFix = Just "keel setup onnx   (or point KEEL_ONNXRUNTIME at the official onnxruntime library)"

onnxReport :: IO CapabilityReport
onnxReport = do
  r <- loadOnnxRuntime
  case r of
    -- deliberately not closed: onnxruntime owns thread pools and
    -- unloading at process end is the safe path
    Right ort ->
      pure
        ( CapabilityReport "keel-onnx (ONNX Runtime)" Available
            ("ONNX Runtime " <> ortVersion ort <> "  @ " <> libraryPath (capLibrary ort))
            Nothing
        )
    Left err ->
      pure $ case err of
        OnnxRuntimeNotFound _ ->
          CapabilityReport "keel-onnx (ONNX Runtime)" Missing
            "no ONNX Runtime found via KEEL_ONNXRUNTIME, the keel data dir, or the system search path"
            onnxFix
        OnnxApiUnsupported v ->
          CapabilityReport "keel-onnx (ONNX Runtime)" Broken
            ("a runtime was found but is older than C API version " <> show v
              <> " (a stray old onnxruntime on PATH shadows the good one)")
            onnxFix
        other ->
          CapabilityReport "keel-onnx (ONNX Runtime)" Broken (show other) onnxFix

-- | @True@ when every probed capability is 'Available'.
allAvailable :: [CapabilityReport] -> Bool
allAvailable = all ((== Available) . capStatus)

-- | Plain-text rendering, one capability per block.
renderReports :: [CapabilityReport] -> String
renderReports reports = unlines (concatMap block reports)
  where
    block r =
      (tag (capStatus r) <> "  " <> pad (capName r) <> "  " <> capDetail r)
        : case (capStatus r, capFix r) of
            (Available, _) -> []
            (_, Just fix) -> ["          fix: " <> fix]
            _ -> []
    tag Available = "[ok]     "
    tag Missing = "[MISSING]"
    tag Broken = "[BROKEN] "
    width = maximum (map (length . capName) reports)
    pad s = s <> replicate (width - length s) ' '
