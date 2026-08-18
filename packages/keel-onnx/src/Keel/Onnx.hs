-- | ONNX Runtime inference, resolved entirely at run time.
--
-- 'loadOnnxRuntime' locates the shared library through the keel search
-- policy (@KEEL_ONNXRUNTIME@ override, the per-user keel data dir, then
-- the system search path), resolves the single exported symbol
-- @OrtGetApiBase@, requests the versioned function-pointer table, and
-- pins it in an immutable 'Ort' handle. Everything else is a call
-- through that table under 'Control.Exception.bracket' discipline:
--
-- > Right ort <- loadOnnxRuntime
-- > model <- BS.readFile "model.onnx"
-- > withOrtEnv ort $ \env ->
-- >   withSessionFromBytes env model $ \sess -> do
-- >     [inName] <- inputNames sess
-- >     [outName] <- outputNames sess
-- >     [(shape, ys)] <- runFloats sess [(inName, [n, k], xs)] [outName]
-- >     ...
--
-- Inference only: no training, no model export. Absence of the runtime
-- is an ordinary 'Left' from 'loadOnnxRuntime', never a crash.
module Keel.Onnx
  ( -- * Runtime
    Ort
  , OnnxError (..)
  , defaultOrtSpec
  , loadOnnxRuntime
  , closeOnnxRuntime
  , ortVersion

    -- * Environment and sessions
  , OrtEnv
  , withOrtEnv
  , Session
  , withSessionFromBytes
  , inputNames
  , outputNames

    -- * Inference
  , OnnxTensor (..)
  , runTensors
  , runFloats
  ) where

import Control.Exception (Exception, bracket, throwIO)
import Data.ByteString qualified as BS
import Data.ByteString.Unsafe qualified as BSU
import Data.Int (Int64)
import Data.Vector.Storable qualified as VS
import Data.Word (Word32)
import Foreign.C.String (CString, peekCString, withCString)
import Foreign.C.Types (CInt (..), CSize (..))
import Foreign.Concurrent qualified as FC
import Foreign.ForeignPtr (castForeignPtr)
import Foreign.Marshal.Alloc (alloca)
import Foreign.Marshal.Array (allocaArray, peekArray, pokeArray, withArray)
import Foreign.Ptr (FunPtr, Ptr, castPtr, nullPtr)
import Foreign.Storable (peek, poke)
import System.Info (os)

import Keel.Dyn
import Keel.Dyn.Locate
import Keel.Onnx.Raw

-- ---------------------------------------------------------------------
-- Errors

-- | Everything that can go wrong between locating the runtime and
-- reading back a tensor.
data OnnxError
  = OnnxRuntimeNotFound DynError
    -- ^ No ONNX Runtime library was found by the search policy, or it
    -- exports no @OrtGetApiBase@.
  | OnnxApiUnsupported Word32
    -- ^ The runtime is older than the pinned 'ortApiVersion' and
    -- refused to serve the table.
  | OrtError String Int String
    -- ^ An ORT call failed: context, @OrtErrorCode@, and the runtime's
    -- own message.
  | OnnxTypeMismatch String Int
    -- ^ A tensor's element type differs from what the operation
    -- expects (context, @ONNXTensorElementDataType@ code found).
  deriving (Eq, Show)

instance Exception OnnxError

-- ---------------------------------------------------------------------
-- Dynamic callers, grouped by C signature shape. Status-returning calls
-- end in the status pointer; 'checkStatus' interprets it.

foreign import ccall safe "dynamic"
  callP_V :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()

foreign import ccall safe "dynamic"
  callP_I :: FunPtr (Ptr a -> IO CInt) -> Ptr a -> IO CInt

foreign import ccall safe "dynamic"
  callP_P :: FunPtr (Ptr a -> IO (Ptr b)) -> Ptr a -> IO (Ptr b)

foreign import ccall safe "dynamic"
  callP_S :: FunPtr (Ptr a -> IO (Ptr OrtStatusT)) -> Ptr a -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callPP_S
    :: FunPtr (Ptr a -> Ptr b -> IO (Ptr OrtStatusT))
    -> Ptr a -> Ptr b -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callIPP_S
    :: FunPtr (CInt -> Ptr a -> Ptr b -> IO (Ptr OrtStatusT))
    -> CInt -> Ptr a -> Ptr b -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callIIP_S
    :: FunPtr (CInt -> CInt -> Ptr a -> IO (Ptr OrtStatusT))
    -> CInt -> CInt -> Ptr a -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callPZPP_S
    :: FunPtr (Ptr a -> CSize -> Ptr b -> Ptr c -> IO (Ptr OrtStatusT))
    -> Ptr a -> CSize -> Ptr b -> Ptr c -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callPPZPP_S
    :: FunPtr (Ptr a -> Ptr b -> CSize -> Ptr c -> Ptr d -> IO (Ptr OrtStatusT))
    -> Ptr a -> Ptr b -> CSize -> Ptr c -> Ptr d -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callPPZ_S
    :: FunPtr (Ptr a -> Ptr b -> CSize -> IO (Ptr OrtStatusT))
    -> Ptr a -> Ptr b -> CSize -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callTensor_S
    :: FunPtr (Ptr a -> Ptr b -> CSize -> Ptr c -> CSize -> CInt -> Ptr d -> IO (Ptr OrtStatusT))
    -> Ptr a -> Ptr b -> CSize -> Ptr c -> CSize -> CInt -> Ptr d -> IO (Ptr OrtStatusT)

foreign import ccall safe "dynamic"
  callRun_S
    :: FunPtr
         (  Ptr a -> Ptr b -> Ptr c -> Ptr d -> CSize
         -> Ptr e -> CSize -> Ptr f -> IO (Ptr OrtStatusT)
         )
    -> Ptr a -> Ptr b -> Ptr c -> Ptr d -> CSize
    -> Ptr e -> CSize -> Ptr f -> IO (Ptr OrtStatusT)

-- ---------------------------------------------------------------------
-- The pinned runtime

-- | The typed view of the OrtApi table slots keel-onnx uses.
data OrtOps = OrtOps
  { oGetErrorCode :: FunPtr (Ptr OrtStatusT -> IO CInt)
  , oGetErrorMessage :: FunPtr (Ptr OrtStatusT -> IO CString)
  , oCreateEnv :: FunPtr (CInt -> Ptr () -> Ptr (Ptr OrtEnvT) -> IO (Ptr OrtStatusT))
  , oCreateSessionFromArray
      :: FunPtr (Ptr OrtEnvT -> Ptr () -> CSize -> Ptr OrtSessionOptionsT -> Ptr (Ptr OrtSessionT) -> IO (Ptr OrtStatusT))
  , oRun
      :: FunPtr
           (  Ptr OrtSessionT -> Ptr () -> Ptr CString -> Ptr (Ptr OrtValueT) -> CSize
           -> Ptr CString -> CSize -> Ptr (Ptr OrtValueT) -> IO (Ptr OrtStatusT)
           )
  , oCreateSessionOptions :: FunPtr (Ptr (Ptr OrtSessionOptionsT) -> IO (Ptr OrtStatusT))
  , oSessionGetInputCount :: FunPtr (Ptr OrtSessionT -> Ptr CSize -> IO (Ptr OrtStatusT))
  , oSessionGetOutputCount :: FunPtr (Ptr OrtSessionT -> Ptr CSize -> IO (Ptr OrtStatusT))
  , oSessionGetInputName
      :: FunPtr (Ptr OrtSessionT -> CSize -> Ptr OrtAllocatorT -> Ptr CString -> IO (Ptr OrtStatusT))
  , oSessionGetOutputName
      :: FunPtr (Ptr OrtSessionT -> CSize -> Ptr OrtAllocatorT -> Ptr CString -> IO (Ptr OrtStatusT))
  , oCreateTensorWithData
      :: FunPtr (Ptr OrtMemoryInfoT -> Ptr () -> CSize -> Ptr Int64 -> CSize -> CInt -> Ptr (Ptr OrtValueT) -> IO (Ptr OrtStatusT))
  , oGetTensorMutableData :: FunPtr (Ptr OrtValueT -> Ptr (Ptr ()) -> IO (Ptr OrtStatusT))
  , oGetTensorElementType
      :: FunPtr (Ptr OrtTensorTypeAndShapeInfoT -> Ptr CInt -> IO (Ptr OrtStatusT))
  , oGetDimensionsCount
      :: FunPtr (Ptr OrtTensorTypeAndShapeInfoT -> Ptr CSize -> IO (Ptr OrtStatusT))
  , oGetDimensions
      :: FunPtr (Ptr OrtTensorTypeAndShapeInfoT -> Ptr Int64 -> CSize -> IO (Ptr OrtStatusT))
  , oGetTensorShapeElementCount
      :: FunPtr (Ptr OrtTensorTypeAndShapeInfoT -> Ptr CSize -> IO (Ptr OrtStatusT))
  , oGetTensorTypeAndShape
      :: FunPtr (Ptr OrtValueT -> Ptr (Ptr OrtTensorTypeAndShapeInfoT) -> IO (Ptr OrtStatusT))
  , oCreateCpuMemoryInfo :: FunPtr (CInt -> CInt -> Ptr (Ptr OrtMemoryInfoT) -> IO (Ptr OrtStatusT))
  , oAllocatorFree :: FunPtr (Ptr OrtAllocatorT -> Ptr () -> IO (Ptr OrtStatusT))
  , oGetAllocatorWithDefaultOptions :: FunPtr (Ptr (Ptr OrtAllocatorT) -> IO (Ptr OrtStatusT))
  , oReleaseEnv :: FunPtr (Ptr OrtEnvT -> IO ())
  , oReleaseStatus :: FunPtr (Ptr OrtStatusT -> IO ())
  , oReleaseMemoryInfo :: FunPtr (Ptr OrtMemoryInfoT -> IO ())
  , oReleaseSession :: FunPtr (Ptr OrtSessionT -> IO ())
  , oReleaseValue :: FunPtr (Ptr OrtValueT -> IO ())
  , oReleaseShapeInfo :: FunPtr (Ptr OrtTensorTypeAndShapeInfoT -> IO ())
  , oReleaseSessionOptions :: FunPtr (Ptr OrtSessionOptionsT -> IO ())
  }

-- | A pinned ONNX Runtime: library handle, version string (from
-- @GetVersionString@), and the typed slot table.
type Ort = Capability OrtOps

-- | The runtime's own version string, e.g. @\"1.24.4\"@.
ortVersion :: Ort -> String
ortVersion = capVersion

-- | Where 'loadOnnxRuntime' looks: @KEEL_ONNXRUNTIME@ override, the
-- per-user keel data dir under the name @onnxruntime@, then the system
-- search path.
defaultOrtSpec :: LibrarySpec
defaultOrtSpec =
  LibrarySpec
    { specName = "onnxruntime"
    , specEnvVar = "KEEL_ONNXRUNTIME"
    , specCandidates = case os of
        "mingw32" -> ["onnxruntime.dll"]
        "darwin" -> ["libonnxruntime.dylib"]
        _ -> ["libonnxruntime.so.1", "libonnxruntime.so"]
    }

-- | Locate and pin the runtime; see the module header.
loadOnnxRuntime :: IO (Either OnnxError Ort)
loadOnnxRuntime = do
  located <- locateLibrary defaultOrtSpec
  case located of
    Left e -> pure (Left (OnnxRuntimeNotFound e))
    Right loc -> do
      let lib = locLibrary loc
      baseSym <- resolveSym lib "OrtGetApiBase"
      case baseSym of
        Left e -> do
          closeLibrary lib
          pure (Left (OnnxRuntimeNotFound e))
        Right baseFp -> do
          base <- callGetBase baseFp
          getApiFp <- apiSlot base 0
          getVerFp <- apiSlot base 1
          api <- callGetApi getApiFp ortApiVersion
          if api == nullPtr
            then do
              closeLibrary lib
              pure (Left (OnnxApiUnsupported ortApiVersion))
            else do
              ver <- peekCString =<< callGetVersionString getVerFp
              ops <- mkOps api
              pure (Right (Capability lib ver ops))

foreign import ccall safe "dynamic"
  callGetBase :: FunPtr (IO (Ptr OrtApiBase)) -> IO (Ptr OrtApiBase)

mkOps :: Ptr OrtApiTable -> IO OrtOps
mkOps api =
  OrtOps
    <$> apiSlot api slotGetErrorCode
    <*> apiSlot api slotGetErrorMessage
    <*> apiSlot api slotCreateEnv
    <*> apiSlot api slotCreateSessionFromArray
    <*> apiSlot api slotRun
    <*> apiSlot api slotCreateSessionOptions
    <*> apiSlot api slotSessionGetInputCount
    <*> apiSlot api slotSessionGetOutputCount
    <*> apiSlot api slotSessionGetInputName
    <*> apiSlot api slotSessionGetOutputName
    <*> apiSlot api slotCreateTensorWithDataAsOrtValue
    <*> apiSlot api slotGetTensorMutableData
    <*> apiSlot api slotGetTensorElementType
    <*> apiSlot api slotGetDimensionsCount
    <*> apiSlot api slotGetDimensions
    <*> apiSlot api slotGetTensorShapeElementCount
    <*> apiSlot api slotGetTensorTypeAndShape
    <*> apiSlot api slotCreateCpuMemoryInfo
    <*> apiSlot api slotAllocatorFree
    <*> apiSlot api slotGetAllocatorWithDefaultOptions
    <*> apiSlot api slotReleaseEnv
    <*> apiSlot api slotReleaseStatus
    <*> apiSlot api slotReleaseMemoryInfo
    <*> apiSlot api slotReleaseSession
    <*> apiSlot api slotReleaseValue
    <*> apiSlot api slotReleaseTensorTypeAndShapeInfo
    <*> apiSlot api slotReleaseSessionOptions

-- | Drop the pin. All handles derived from this 'Ort' become invalid.
closeOnnxRuntime :: Ort -> IO ()
closeOnnxRuntime = closeLibrary . capLibrary

-- | Interpret an ORT status: null is success; anything else raises
-- 'OrtError' (after releasing the status object).
checkStatus :: OrtOps -> String -> Ptr OrtStatusT -> IO ()
checkStatus ops ctx st
  | st == nullPtr = pure ()
  | otherwise = do
      code <- callP_I (oGetErrorCode ops) st
      msg <- peekCString =<< callP_P (oGetErrorMessage ops) st
      callP_V (oReleaseStatus ops) st
      throwIO (OrtError ctx (fromIntegral code) msg)

-- Run a status-returning creator with a single out-pointer.
creating :: OrtOps -> String -> (Ptr (Ptr h) -> IO (Ptr OrtStatusT)) -> IO (Ptr h)
creating ops ctx make = alloca $ \out -> do
  poke out nullPtr
  checkStatus ops ctx =<< make out
  peek out

-- ---------------------------------------------------------------------
-- Environment and sessions

-- | An ORT environment (logging scope); create one per process.
data OrtEnv = OrtEnv Ort (Ptr OrtEnvT)

-- | Create an environment (WARNING log level, log id @\"keel\"@) and
-- release it when the action finishes.
withOrtEnv :: Ort -> (OrtEnv -> IO a) -> IO a
withOrtEnv ort act =
  bracket
    ( withCString "keel" $ \logid ->
        creating ops "CreateEnv" $ \out ->
          callIPP_S (oCreateEnv ops) ortLoggingLevelWarning (castPtr logid) out
    )
    (callP_V (oReleaseEnv ops))
    (act . OrtEnv ort)
  where
    ops = capOps ort

-- | A loaded model.
data Session = Session Ort (Ptr OrtSessionT)

-- | Create a session from in-memory model bytes (avoiding the
-- platform-dependent @ORTCHAR_T@ path argument entirely) with default
-- options; release it when the action finishes.
withSessionFromBytes :: OrtEnv -> BS.ByteString -> (Session -> IO a) -> IO a
withSessionFromBytes (OrtEnv ort env) model act =
  bracket
    ( bracket
        (creating ops "CreateSessionOptions" (callP_S (oCreateSessionOptions ops)))
        (callP_V (oReleaseSessionOptions ops))
        $ \opts ->
          BSU.unsafeUseAsCStringLen model $ \(pModel, len) ->
            creating ops "CreateSessionFromArray" $ \out ->
              callPPZPP_S (oCreateSessionFromArray ops)
                env (castPtr pModel) (fromIntegral len) opts out
    )
    (callP_V (oReleaseSession ops))
    (act . Session ort)
  where
    ops = capOps ort

-- Names come back in ORT's default allocator; free them through it.
namesOf
  :: String
  -> (OrtOps -> FunPtr (Ptr OrtSessionT -> Ptr CSize -> IO (Ptr OrtStatusT)))
  -> (OrtOps -> FunPtr (Ptr OrtSessionT -> CSize -> Ptr OrtAllocatorT -> Ptr CString -> IO (Ptr OrtStatusT)))
  -> Session
  -> IO [String]
namesOf ctx countF nameF (Session ort sess) = do
  let ops = capOps ort
  n <- alloca $ \out -> do
    checkStatus ops (ctx <> "Count") =<< callPP_S (countF ops) sess out
    peek out
  alloc <- creating ops "GetAllocatorWithDefaultOptions"
    (callP_S (oGetAllocatorWithDefaultOptions ops))
  mapM
    ( \i -> do
        cs <- alloca $ \out -> do
          checkStatus ops ctx =<< callPZPP_S (nameF ops) sess i alloc out
          peek out
        s <- peekCString cs
        checkStatus ops "AllocatorFree"
          =<< callPP_S (oAllocatorFree ops) alloc (castPtr cs)
        pure s
    )
    [0 .. n - 1]

-- | The model's input names, in declaration order.
inputNames :: Session -> IO [String]
inputNames = namesOf "SessionGetInputName" oSessionGetInputCount oSessionGetInputName

-- | The model's output names, in declaration order.
outputNames :: Session -> IO [String]
outputNames = namesOf "SessionGetOutputName" oSessionGetOutputCount oSessionGetOutputName

-- ---------------------------------------------------------------------
-- Inference

-- | An output tensor: shape plus data. The data vectors are /zero-copy
-- views/ of ORT's own output buffers — the underlying @OrtValue@ is
-- released by the vector's finalizer, so the view stays valid for as
-- long as you hold it and costs nothing to obtain.
data OnnxTensor
  = FloatTensor [Int64] (VS.Vector Float)
  | Int64Tensor [Int64] (VS.Vector Int64)
  | DoubleTensor [Int64] (VS.Vector Double)
  deriving (Eq, Show)

-- | Run the model: named float32 inputs (shape + row-major data,
-- zero-copy into ORT) to named outputs (zero-copy out, see
-- 'OnnxTensor'). Output element types other than float32\/int64\/double
-- throw 'OnnxTypeMismatch'.
runTensors
  :: Session
  -> [(String, [Int64], VS.Vector Float)] -- ^ inputs
  -> [String] -- ^ outputs to fetch
  -> IO [OnnxTensor]
runTensors (Session ort sess) inputs outNames =
  bracket
    ( creating ops "CreateCpuMemoryInfo" $ \out ->
        callIIP_S (oCreateCpuMemoryInfo ops) ortArenaAllocator ortMemTypeDefault out
    )
    (callP_V (oReleaseMemoryInfo ops))
    $ \memInfo ->
      withInputValues ops memInfo inputs $ \inVals ->
        withCStrings (map (\(nm, _, _) -> nm) inputs) $ \inNamePs ->
          withCStrings outNames $ \outNamePs ->
            withArray inNamePs $ \inNameArr ->
              withArray outNamePs $ \outNameArr ->
                withArray inVals $ \inValArr ->
                  allocaArray nOut $ \outValArr -> do
                    pokeArray outValArr (replicate nOut nullPtr)
                    checkStatus ops "Run"
                      =<< callRun_S (oRun ops) sess nullPtr
                            inNameArr inValArr (fromIntegral (length inputs))
                            outNameArr (fromIntegral nOut) outValArr
                    outVals <- peekArray nOut outValArr
                    mapM (readValue ops) outVals
  where
    ops = capOps ort
    nOut = length outNames

-- | 'runTensors' restricted to float32 outputs (the common
-- regression\/probability case).
runFloats
  :: Session
  -> [(String, [Int64], VS.Vector Float)] -- ^ inputs
  -> [String] -- ^ outputs to fetch
  -> IO [([Int64], VS.Vector Float)]
runFloats sess inputs outNames = do
  ts <- runTensors sess inputs outNames
  mapM
    ( \t -> case t of
        FloatTensor shape v -> pure (shape, v)
        Int64Tensor _ _ -> throwIO (OnnxTypeMismatch "runFloats output" (fromIntegral onnxElementInt64))
        DoubleTensor _ _ -> throwIO (OnnxTypeMismatch "runFloats output" (fromIntegral onnxElementDouble))
    )
    ts

-- Zero-copy input tensors: each borrows the vector's buffer, which the
-- surrounding unsafeWith keeps alive for the whole Run.
withInputValues
  :: OrtOps
  -> Ptr OrtMemoryInfoT
  -> [(String, [Int64], VS.Vector Float)]
  -> ([Ptr OrtValueT] -> IO a)
  -> IO a
withInputValues ops memInfo = go []
  where
    go acc [] k = k (reverse acc)
    go acc ((name, shape, dat) : rest) k =
      VS.unsafeWith dat $ \pd ->
        withArray shape $ \pshape ->
          bracket
            ( creating ops ("CreateTensor(" <> name <> ")") $ \out ->
                callTensor_S (oCreateTensorWithData ops)
                  memInfo (castPtr pd)
                  (fromIntegral (VS.length dat * 4))
                  pshape (fromIntegral (length shape))
                  onnxElementFloat out
            )
            (callP_V (oReleaseValue ops))
            (\val -> go (val : acc) rest k)

withCStrings :: [String] -> ([CString] -> IO a) -> IO a
withCStrings = go []
  where
    go acc [] k = k (reverse acc)
    go acc (s : rest) k = withCString s $ \cs -> go (cs : acc) rest k

-- Take ownership of an output OrtValue and expose its buffer as a
-- zero-copy vector: the ForeignPtr wraps the data pointer, its
-- finalizer releases the OrtValue. On an unsupported element type the
-- value is released immediately and 'OnnxTypeMismatch' is thrown.
readValue :: OrtOps -> Ptr OrtValueT -> IO OnnxTensor
readValue ops val = do
  (ety, dims, count) <-
    bracket
      (creating ops "GetTensorTypeAndShape" (callPP_S (oGetTensorTypeAndShape ops) val))
      (callP_V (oReleaseShapeInfo ops))
      $ \info -> do
        ety <- alloca $ \out -> do
          checkStatus ops "GetTensorElementType"
            =<< callPP_S (oGetTensorElementType ops) info out
          peek out
        ndim <- alloca $ \out -> do
          checkStatus ops "GetDimensionsCount"
            =<< callPP_S (oGetDimensionsCount ops) info out
          peek out
        dims <- allocaArray (fromIntegral ndim) $ \out -> do
          checkStatus ops "GetDimensions"
            =<< callPPZ_S (oGetDimensions ops) info out ndim
          peekArray (fromIntegral ndim) out
        count <- alloca $ \out -> do
          checkStatus ops "GetTensorShapeElementCount"
            =<< callPP_S (oGetTensorShapeElementCount ops) info out
          peek out
        pure (ety, dims, fromIntegral (count :: CSize))
  dp <- alloca $ \out -> do
    checkStatus ops "GetTensorMutableData"
      =<< callPP_S (oGetTensorMutableData ops) val out
    peek out
  let view :: VS.Storable a => IO (VS.Vector a)
      view = do
        fp <- FC.newForeignPtr (castPtr dp) (callP_V (oReleaseValue ops) val)
        pure (VS.unsafeFromForeignPtr0 (castForeignPtr fp) count)
  case () of
    _ | ety == onnxElementFloat -> FloatTensor dims <$> view
      | ety == onnxElementInt64 -> Int64Tensor dims <$> view
      | ety == onnxElementDouble -> DoubleTensor dims <$> view
      | otherwise -> do
          callP_V (oReleaseValue ops) val
          throwIO (OnnxTypeMismatch "runTensors output" (fromIntegral ety))
