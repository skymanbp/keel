-- | Layout gate: compare every offset\/size in the Haskell layout tables
-- against a real C compiler's @offsetof@\/@sizeof@ (computed in
-- @cbits\/layout_gate.c@, which also carries compile-time
-- @_Static_assert@s for the same numbers).
module Main (main) where

import Control.Monad (forM, unless)
import Foreign.C.Types (CSize (..))
import Foreign.Marshal.Array (allocaArray, peekArray)
import Foreign.Ptr (Ptr)
import System.Exit (exitFailure)

import Keel.Abi.Arrow.Raw
import Keel.Abi.DLPack.Raw

foreign import ccall unsafe "keel_layout_ArrowSchema"
  c_layout_ArrowSchema :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_layout_ArrowArray"
  c_layout_ArrowArray :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_layout_ArrowArrayStream"
  c_layout_ArrowArrayStream :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_layout_DLPackVersion"
  c_layout_DLPackVersion :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_layout_DLDevice"
  c_layout_DLDevice :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_layout_DLDataType"
  c_layout_DLDataType :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_layout_DLTensor"
  c_layout_DLTensor :: Ptr CSize -> IO CSize

foreign import ccall unsafe "keel_layout_DLManagedTensorVersioned"
  c_layout_DLManagedTensorVersioned :: Ptr CSize -> IO CSize

-- | Returns the list of mismatch descriptions (empty = pass).
checkStruct
  :: String
  -> (Int, [(String, Int)])
  -> (Ptr CSize -> IO CSize)
  -> IO [String]
checkStruct structName (hsSize, fields) probe =
  allocaArray (length fields) $ \out -> do
    cSize <- probe out
    cOffs <- peekArray (length fields) out
    let sizeErrs =
          [ structName <> ": sizeof C=" <> show cSize <> " hs=" <> show hsSize
          | fromIntegral cSize /= hsSize
          ]
        fieldErrs =
          [ structName <> "." <> fname
              <> ": offsetof C=" <> show cOff <> " hs=" <> show hsOff
          | ((fname, hsOff), cOff) <- zip fields cOffs
          , fromIntegral cOff /= hsOff
          ]
    pure (sizeErrs <> fieldErrs)

main :: IO ()
main = do
  errs <- fmap concat . forM checks $ \(nm, layout, probe) ->
    checkStruct nm layout probe
  unless (null errs) $ do
    mapM_ putStrLn errs
    exitFailure
  putStrLn ("keel-abi: layout gate passed (" <> show (length checks) <> " structs)")
  where
    checks =
      [ ("ArrowSchema", arrowSchemaLayout, c_layout_ArrowSchema)
      , ("ArrowArray", arrowArrayLayout, c_layout_ArrowArray)
      , ("ArrowArrayStream", arrowArrayStreamLayout, c_layout_ArrowArrayStream)
      , ("DLPackVersion", dlPackVersionLayout, c_layout_DLPackVersion)
      , ("DLDevice", dlDeviceLayout, c_layout_DLDevice)
      , ("DLDataType", dlDataTypeLayout, c_layout_DLDataType)
      , ("DLTensor", dlTensorLayout, c_layout_DLTensor)
      , ("DLManagedTensorVersioned", dlManagedTensorVersionedLayout, c_layout_DLManagedTensorVersioned)
      ]
