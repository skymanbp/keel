-- | Slot gate: compare every OrtApi slot index and enum value pinned in
-- "Keel.Onnx.Raw" against what a real C compiler derives from the
-- vendored @onnxruntime_c_api.h@ (v1.24.4). Needs no ONNX Runtime
-- library — this is a pure layout check.
module Main (main) where

import Control.Monad (forM_, unless)
import Foreign.C.Types (CInt (..), CLLong (..), CSize (..))
import Foreign.Marshal.Array (allocaArray, peekArray)
import Foreign.Ptr (Ptr)

import Keel.Onnx.Raw

foreign import ccall unsafe "keel_ort_api_version"
  c_apiVersion :: IO CInt

foreign import ccall unsafe "keel_ort_slot_gate"
  c_slotGate :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_ort_enum_gate"
  c_enumGate :: Ptr CLLong -> IO CSize

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

main :: IO ()
main = do
  -- ortApiVersion is deliberately the OLDEST version GetApi serves (see
  -- its haddock), so the gate checks range, not identity: it must be a
  -- version the vendored header's runtime actually accepts.
  ver <- c_apiVersion
  expect (ortApiVersion >= 1 && ortApiVersion <= fromIntegral ver)
    ("ortApiVersion " <> show ortApiVersion
       <> " outside the served range [1, " <> show ver <> "]")

  let hsSlots = ortSlotTable
  cSlots <- allocaArray (length hsSlots) $ \out -> do
    n <- c_slotGate out
    expect (fromIntegral n == length hsSlots)
      ("slot count: C " <> show n <> " /= hs " <> show (length hsSlots))
    peekArray (length hsSlots) out
  forM_ (zip hsSlots cSlots) $ \((name, hs), c) ->
    expect (fromIntegral c == hs)
      ("OrtApi." <> name <> ": C slot " <> show c <> " /= hs " <> show hs)

  let hsEnums =
        [ ("ORT_LOGGING_LEVEL_WARNING", fromIntegral ortLoggingLevelWarning)
        , ("ONNX_..._FLOAT", fromIntegral onnxElementFloat)
        , ("ONNX_..._INT64", fromIntegral onnxElementInt64)
        , ("ONNX_..._DOUBLE", fromIntegral onnxElementDouble)
        , ("OrtArenaAllocator", fromIntegral ortArenaAllocator)
        , ("OrtMemTypeDefault", fromIntegral ortMemTypeDefault)
        ] :: [(String, Integer)]
  cEnums <- allocaArray (length hsEnums) $ \out -> do
    n <- c_enumGate out
    expect (fromIntegral n == length hsEnums)
      ("enum count: C " <> show n <> " /= hs " <> show (length hsEnums))
    peekArray (length hsEnums) out
  forM_ (zip hsEnums cEnums) $ \((name, hs), c) ->
    expect (fromIntegral c == hs)
      (name <> ": C " <> show c <> " /= hs " <> show hs)

  putStrLn
    ( "keel-onnx: slot gate passed ("
        <> show (length hsSlots)
        <> " slots, "
        <> show (length hsEnums)
        <> " enums, API version "
        <> show ortApiVersion
        <> ")"
    )
