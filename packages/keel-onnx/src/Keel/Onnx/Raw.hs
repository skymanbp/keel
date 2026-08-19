-- | The raw shape of ONNX Runtime's C API: opaque handle tags, the
-- @OrtApiBase@ entry point, the OrtApi function-pointer slot indices,
-- and the enum values keel-onnx uses.
--
-- ONNX Runtime's C API is /designed/ for runtime loading: the only
-- symbol resolved from the library is @OrtGetApiBase@; everything else
-- is a slot in the @OrtApi@ struct it hands back — a table of function
-- pointers whose layout is append-only across versions ('ortApiVersion'
-- pins the vintage these indices come from). Every index below is
-- verified against the vendored @onnxruntime_c_api.h@ by the
-- test-suite slot gate (@test\/cbits\/slot_gate.c@); the shipped
-- library has no C sources.
module Keel.Onnx.Raw
  ( -- * Opaque handles
    OrtApiBase
  , OrtApiTable
  , OrtStatusT
  , OrtEnvT
  , OrtSessionT
  , OrtSessionOptionsT
  , OrtValueT
  , OrtMemoryInfoT
  , OrtAllocatorT
  , OrtTensorTypeAndShapeInfoT
  , OrtTypeInfoT

    -- * Entry point
  , ortApiVersion
  , callGetApi
  , callGetVersionString
  , apiSlot

    -- * OrtApi slot indices (v1.24.4, gate-verified)
  , ortSlotTable
  , slotGetErrorCode
  , slotGetErrorMessage
  , slotCreateEnv
  , slotCreateSessionFromArray
  , slotRun
  , slotCreateSessionOptions
  , slotSessionGetInputCount
  , slotSessionGetOutputCount
  , slotSessionGetInputName
  , slotSessionGetOutputName
  , slotSessionGetInputTypeInfo
  , slotSessionGetOutputTypeInfo
  , slotCastTypeInfoToTensorInfo
  , slotReleaseTypeInfo
  , slotCreateTensorWithDataAsOrtValue
  , slotGetTensorMutableData
  , slotGetTensorElementType
  , slotGetDimensionsCount
  , slotGetDimensions
  , slotGetTensorShapeElementCount
  , slotGetTensorTypeAndShape
  , slotCreateCpuMemoryInfo
  , slotAllocatorFree
  , slotGetAllocatorWithDefaultOptions
  , slotReleaseEnv
  , slotReleaseStatus
  , slotReleaseMemoryInfo
  , slotReleaseSession
  , slotReleaseValue
  , slotReleaseTensorTypeAndShapeInfo
  , slotReleaseSessionOptions

    -- * Enum values (gate-verified)
  , ortLoggingLevelWarning
  , onnxElementFloat
  , onnxElementInt64
  , onnxElementDouble
  , ortArenaAllocator
  , ortMemTypeDefault
  ) where

import Data.Word (Word32)
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, Ptr, castFunPtr, castPtr)
import Foreign.C.String (CString)
import Foreign.Storable (peekElemOff)

-- | Opaque tag for @OrtApiBase@ (the two-slot entry table).
data OrtApiBase

-- | Opaque tag for @OrtApi@ (the versioned function-pointer table).
data OrtApiTable

-- | Opaque tag for @OrtStatus@.
data OrtStatusT

-- | Opaque tag for @OrtEnv@.
data OrtEnvT

-- | Opaque tag for @OrtSession@.
data OrtSessionT

-- | Opaque tag for @OrtSessionOptions@.
data OrtSessionOptionsT

-- | Opaque tag for @OrtValue@.
data OrtValueT

-- | Opaque tag for @OrtMemoryInfo@.
data OrtMemoryInfoT

-- | Opaque tag for @OrtAllocator@.
data OrtAllocatorT

-- | Opaque tag for @OrtTensorTypeAndShapeInfo@.
data OrtTensorTypeAndShapeInfoT

-- | Opaque tag for @OrtTypeInfo@.
data OrtTypeInfoT

-- | The @OrtApi@ version requested from @GetApi@: the oldest version,
-- so that every ONNX Runtime release serves the table. Safe because
-- the table is append-only and every slot keel-onnx uses (max index
-- 100) has sat at its pinned index since the table was introduced —
-- checked against the v1.1.2, v1.4.0, v1.8.1 and v1.24.4 headers, the
-- first of which already carries 102 entries. @GetApi@ accepts the
-- range @[1, ORT_API_VERSION]@ (probed on ORT 1.16.3 and 1.24.4, which
-- reject only versions above their own).
ortApiVersion :: Word32
ortApiVersion = 1

-- OrtApiBase is itself a two-slot function-pointer table:
-- slot 0 = GetApi, slot 1 = GetVersionString.

-- | Invoke @OrtApiBase.GetApi@ (read from slot 0 of the base table).
foreign import ccall safe "dynamic"
  callGetApi :: FunPtr (Word32 -> IO (Ptr OrtApiTable)) -> Word32 -> IO (Ptr OrtApiTable)

-- | Invoke @OrtApiBase.GetVersionString@ (slot 1 of the base table).
foreign import ccall safe "dynamic"
  callGetVersionString :: FunPtr (IO CString) -> IO CString

-- | Read one function pointer out of a pointer-array-shaped table
-- ('OrtApiBase' or 'OrtApiTable'). The type you give the result is your
-- unchecked claim about the slot's C signature.
apiSlot :: Ptr t -> Int -> IO (FunPtr a)
apiSlot table i = castFunPtr <$> peekElemOff (castPtr table :: Ptr (FunPtr ())) i

-- | OrtApi slot indices, exactly as computed by the C compiler from
-- the vendored v1.24.4 header (@offsetof \/ sizeof(void*)@) — see the
-- test-suite slot gate.
slotGetErrorCode, slotGetErrorMessage, slotCreateEnv,
  slotCreateSessionFromArray, slotRun, slotCreateSessionOptions,
  slotSessionGetInputCount, slotSessionGetOutputCount,
  slotSessionGetInputName, slotSessionGetOutputName,
  slotSessionGetInputTypeInfo, slotSessionGetOutputTypeInfo,
  slotCastTypeInfoToTensorInfo, slotReleaseTypeInfo,
  slotCreateTensorWithDataAsOrtValue, slotGetTensorMutableData,
  slotGetTensorElementType, slotGetDimensionsCount, slotGetDimensions,
  slotGetTensorShapeElementCount, slotGetTensorTypeAndShape,
  slotCreateCpuMemoryInfo, slotAllocatorFree,
  slotGetAllocatorWithDefaultOptions, slotReleaseEnv, slotReleaseStatus,
  slotReleaseMemoryInfo, slotReleaseSession, slotReleaseValue,
  slotReleaseTensorTypeAndShapeInfo, slotReleaseSessionOptions :: Int
slotGetErrorCode = 1
slotGetErrorMessage = 2
slotCreateEnv = 3
slotCreateSessionFromArray = 8
slotRun = 9
slotCreateSessionOptions = 10
slotSessionGetInputCount = 30
slotSessionGetOutputCount = 31
slotSessionGetInputName = 36
slotSessionGetOutputName = 37
slotSessionGetInputTypeInfo = 33
slotSessionGetOutputTypeInfo = 34
slotCastTypeInfoToTensorInfo = 55
slotReleaseTypeInfo = 98
slotCreateTensorWithDataAsOrtValue = 49
slotGetTensorMutableData = 51
slotGetTensorElementType = 60
slotGetDimensionsCount = 61
slotGetDimensions = 62
slotGetTensorShapeElementCount = 64
slotGetTensorTypeAndShape = 65
slotCreateCpuMemoryInfo = 69
slotAllocatorFree = 76
slotGetAllocatorWithDefaultOptions = 78
slotReleaseEnv = 92
slotReleaseStatus = 93
slotReleaseMemoryInfo = 94
slotReleaseSession = 95
slotReleaseValue = 96
slotReleaseTensorTypeAndShapeInfo = 99
slotReleaseSessionOptions = 100

-- | @(member name, slot)@ in the order the slot gate's C probe emits
-- them — compared verbatim by the @keel-onnx-slots@ test suite.
ortSlotTable :: [(String, Int)]
ortSlotTable =
  [ ("GetErrorCode", slotGetErrorCode)
  , ("GetErrorMessage", slotGetErrorMessage)
  , ("CreateEnv", slotCreateEnv)
  , ("CreateSessionFromArray", slotCreateSessionFromArray)
  , ("Run", slotRun)
  , ("CreateSessionOptions", slotCreateSessionOptions)
  , ("SessionGetInputCount", slotSessionGetInputCount)
  , ("SessionGetOutputCount", slotSessionGetOutputCount)
  , ("SessionGetInputName", slotSessionGetInputName)
  , ("SessionGetOutputName", slotSessionGetOutputName)
  , ("CreateTensorWithDataAsOrtValue", slotCreateTensorWithDataAsOrtValue)
  , ("GetTensorMutableData", slotGetTensorMutableData)
  , ("GetTensorElementType", slotGetTensorElementType)
  , ("GetDimensionsCount", slotGetDimensionsCount)
  , ("GetDimensions", slotGetDimensions)
  , ("GetTensorShapeElementCount", slotGetTensorShapeElementCount)
  , ("GetTensorTypeAndShape", slotGetTensorTypeAndShape)
  , ("CreateCpuMemoryInfo", slotCreateCpuMemoryInfo)
  , ("AllocatorFree", slotAllocatorFree)
  , ("GetAllocatorWithDefaultOptions", slotGetAllocatorWithDefaultOptions)
  , ("ReleaseEnv", slotReleaseEnv)
  , ("ReleaseStatus", slotReleaseStatus)
  , ("ReleaseMemoryInfo", slotReleaseMemoryInfo)
  , ("ReleaseSession", slotReleaseSession)
  , ("ReleaseValue", slotReleaseValue)
  , ("ReleaseTensorTypeAndShapeInfo", slotReleaseTensorTypeAndShapeInfo)
  , ("ReleaseSessionOptions", slotReleaseSessionOptions)
  , ("SessionGetInputTypeInfo", slotSessionGetInputTypeInfo)
  , ("SessionGetOutputTypeInfo", slotSessionGetOutputTypeInfo)
  , ("CastTypeInfoToTensorInfo", slotCastTypeInfoToTensorInfo)
  , ("ReleaseTypeInfo", slotReleaseTypeInfo)
  ]

-- Enum values (onnxruntime_c_api.h, gate-verified)

-- | @ORT_LOGGING_LEVEL_WARNING@.
ortLoggingLevelWarning :: CInt
ortLoggingLevelWarning = 2

-- | @ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT@.
onnxElementFloat :: CInt
onnxElementFloat = 1

-- | @ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64@.
onnxElementInt64 :: CInt
onnxElementInt64 = 7

-- | @ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE@.
onnxElementDouble :: CInt
onnxElementDouble = 11

-- | @OrtArenaAllocator@.
ortArenaAllocator :: CInt
ortArenaAllocator = 1

-- | @OrtMemTypeDefault@.
ortMemTypeDefault :: CInt
ortMemTypeDefault = 0
