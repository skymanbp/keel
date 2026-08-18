-- | The DLPack tensor-exchange structs, 1:1 and unmanaged.
--
-- Targets DLPack v1.x: the exchanged object is 'DLManagedTensorVersioned'
-- (the pre-1.0 unversioned @DLManagedTensor@ is deliberately not bound).
-- Layouts are hand-written against @dlpack.h@
-- (<https://github.com/dmlc/dlpack>) and verified by the test-suite
-- layout gate; the shipped library has no C sources.
--
-- Ownership follows the DLPack contract: the consumer of a
-- 'DLManagedTensorVersioned' calls 'callTensorDeleter' exactly once when
-- done; the producer keeps everything the tensor points at alive until
-- then via 'mtvManagerCtx'.
module Keel.Abi.DLPack.Raw
  ( -- * Version
    DLPackVersion (..)
  , dlpackMajorVersion
  , dlpackMinorVersion

    -- * Device
  , DLDevice (..)
  , kDLCPU
  , kDLCUDA
  , kDLCUDAHost
  , kDLOpenCL
  , kDLVulkan
  , kDLMetal
  , kDLVPI
  , kDLROCM

    -- * Data type
  , DLDataType (..)
  , kDLInt
  , kDLUInt
  , kDLFloat
  , kDLOpaqueHandle
  , kDLBfloat
  , kDLComplex
  , kDLBool

    -- * Tensor
  , DLTensor (..)
  , DLManagedTensorVersioned (..)
  , dlpackFlagReadOnly
  , dlpackFlagIsCopied
  , callTensorDeleter

    -- * Layout tables (consumed by the test-suite layout gate)
  , dlPackVersionLayout
  , dlDeviceLayout
  , dlDataTypeLayout
  , dlTensorLayout
  , dlManagedTensorVersionedLayout
  ) where

import Control.Monad (unless)
import Data.Int (Int32, Int64)
import Data.Word (Word16, Word32, Word64, Word8)
import Foreign.Ptr (FunPtr, Ptr, nullFunPtr)
import Foreign.Storable (Storable (..))

-- ---------------------------------------------------------------------
-- DLPackVersion

-- | @DLPackVersion@ — the ABI version the producer filled the struct
-- with. Consumers must check 'dlverMajor' against 'dlpackMajorVersion'.
data DLPackVersion = DLPackVersion
  { dlverMajor :: Word32
  , dlverMinor :: Word32
  }
  deriving (Eq, Show)

-- | The DLPack version these bindings target (v1.1).
dlpackMajorVersion, dlpackMinorVersion :: Word32
dlpackMajorVersion = 1
dlpackMinorVersion = 1

oVerMajor, oVerMinor, szDLPackVersion :: Int
oVerMajor = 0
oVerMinor = 4
szDLPackVersion = 8

-- | @(sizeof, [(field, offset)])@ in declaration order.
dlPackVersionLayout :: (Int, [(String, Int)])
dlPackVersionLayout =
  (szDLPackVersion, [("major", oVerMajor), ("minor", oVerMinor)])

instance Storable DLPackVersion where
  sizeOf _ = szDLPackVersion
  alignment _ = 4
  peek p = DLPackVersion <$> peekByteOff p oVerMajor <*> peekByteOff p oVerMinor
  poke p v = do
    pokeByteOff p oVerMajor (dlverMajor v)
    pokeByteOff p oVerMinor (dlverMinor v)

-- ---------------------------------------------------------------------
-- DLDevice

-- | @DLDevice@. 'dldevType' is the @DLDeviceType@ enum (a C @int@).
data DLDevice = DLDevice
  { dldevType :: Int32
  , dldevId :: Int32
  }
  deriving (Eq, Show)

-- | @DLDeviceType@ values (the ones keel can ever produce or consume;
-- the full enum is larger but frozen upstream).
kDLCPU, kDLCUDA, kDLCUDAHost, kDLOpenCL, kDLVulkan, kDLMetal, kDLVPI, kDLROCM :: Int32
kDLCPU = 1
kDLCUDA = 2
kDLCUDAHost = 3
kDLOpenCL = 4
kDLVulkan = 7
kDLMetal = 8
kDLVPI = 9
kDLROCM = 10

oDevType, oDevId, szDLDevice :: Int
oDevType = 0
oDevId = 4
szDLDevice = 8

-- | @(sizeof, [(field, offset)])@ in declaration order.
dlDeviceLayout :: (Int, [(String, Int)])
dlDeviceLayout = (szDLDevice, [("device_type", oDevType), ("device_id", oDevId)])

instance Storable DLDevice where
  sizeOf _ = szDLDevice
  alignment _ = 4
  peek p = DLDevice <$> peekByteOff p oDevType <*> peekByteOff p oDevId
  poke p d = do
    pokeByteOff p oDevType (dldevType d)
    pokeByteOff p oDevId (dldevId d)

-- ---------------------------------------------------------------------
-- DLDataType

-- | @DLDataType@: type code, bit width, vector lanes (1 for scalars).
-- Example: @DLDataType kDLFloat 64 1@ is a C @double@.
data DLDataType = DLDataType
  { dldtCode :: Word8
  , dldtBits :: Word8
  , dldtLanes :: Word16
  }
  deriving (Eq, Show)

-- | @DLDataTypeCode@ values.
kDLInt, kDLUInt, kDLFloat, kDLOpaqueHandle, kDLBfloat, kDLComplex, kDLBool :: Word8
kDLInt = 0
kDLUInt = 1
kDLFloat = 2
kDLOpaqueHandle = 3
kDLBfloat = 4
kDLComplex = 5
kDLBool = 6

oDtCode, oDtBits, oDtLanes, szDLDataType :: Int
oDtCode = 0
oDtBits = 1
oDtLanes = 2
szDLDataType = 4

-- | @(sizeof, [(field, offset)])@ in declaration order.
dlDataTypeLayout :: (Int, [(String, Int)])
dlDataTypeLayout =
  (szDLDataType, [("code", oDtCode), ("bits", oDtBits), ("lanes", oDtLanes)])

instance Storable DLDataType where
  sizeOf _ = szDLDataType
  alignment _ = 2
  peek p =
    DLDataType
      <$> peekByteOff p oDtCode
      <*> peekByteOff p oDtBits
      <*> peekByteOff p oDtLanes
  poke p t = do
    pokeByteOff p oDtCode (dldtCode t)
    pokeByteOff p oDtBits (dldtBits t)
    pokeByteOff p oDtLanes (dldtLanes t)

-- ---------------------------------------------------------------------
-- DLTensor

-- | @DLTensor@ — a borrowed view; owns nothing. 'dltShape' (and
-- 'dltStrides' when non-null) point at @ndim@ @int64_t@s owned by the
-- producer. Null 'dltStrides' means compact row-major. Strides are in
-- /elements/, not bytes.
data DLTensor = DLTensor
  { dltData :: Ptr ()
  , dltDevice :: DLDevice
  , dltNDim :: Int32
  , dltDType :: DLDataType
  , dltShape :: Ptr Int64
  , dltStrides :: Ptr Int64
  , dltByteOffset :: Word64
  }

oTData, oTDevice, oTNDim, oTDType, oTShape, oTStrides, oTByteOffset,
  szDLTensor :: Int
oTData = 0
oTDevice = 8
oTNDim = 16
oTDType = 20
oTShape = 24
oTStrides = 32
oTByteOffset = 40
szDLTensor = 48

-- | @(sizeof, [(field, offset)])@ in declaration order.
dlTensorLayout :: (Int, [(String, Int)])
dlTensorLayout =
  ( szDLTensor
  , [ ("data", oTData)
    , ("device", oTDevice)
    , ("ndim", oTNDim)
    , ("dtype", oTDType)
    , ("shape", oTShape)
    , ("strides", oTStrides)
    , ("byte_offset", oTByteOffset)
    ]
  )

instance Storable DLTensor where
  sizeOf _ = szDLTensor
  alignment _ = 8
  peek p =
    DLTensor
      <$> peekByteOff p oTData
      <*> peekByteOff p oTDevice
      <*> peekByteOff p oTNDim
      <*> peekByteOff p oTDType
      <*> peekByteOff p oTShape
      <*> peekByteOff p oTStrides
      <*> peekByteOff p oTByteOffset
  poke p t = do
    pokeByteOff p oTData (dltData t)
    pokeByteOff p oTDevice (dltDevice t)
    pokeByteOff p oTNDim (dltNDim t)
    pokeByteOff p oTDType (dltDType t)
    pokeByteOff p oTShape (dltShape t)
    pokeByteOff p oTStrides (dltStrides t)
    pokeByteOff p oTByteOffset (dltByteOffset t)

-- ---------------------------------------------------------------------
-- DLManagedTensorVersioned

-- | @DLManagedTensorVersioned@ — the owned exchange object of DLPack
-- v1.x. The consumer calls 'callTensorDeleter' exactly once when done.
data DLManagedTensorVersioned = DLManagedTensorVersioned
  { mtvVersion :: DLPackVersion
  , mtvManagerCtx :: Ptr ()
  , mtvDeleter :: FunPtr (Ptr DLManagedTensorVersioned -> IO ())
  , mtvFlags :: Word64
  , mtvTensor :: DLTensor
  }

-- | @DLPACK_FLAG_BITMASK_READ_ONLY@: the consumer must not write through
-- 'dltData'.
dlpackFlagReadOnly :: Word64
dlpackFlagReadOnly = 1

-- | @DLPACK_FLAG_BITMASK_IS_COPIED@: the tensor is a copy, not a view.
dlpackFlagIsCopied :: Word64
dlpackFlagIsCopied = 2

oMtvVersion, oMtvManagerCtx, oMtvDeleter, oMtvFlags, oMtvTensor,
  szDLManagedTensorVersioned :: Int
oMtvVersion = 0
oMtvManagerCtx = 8
oMtvDeleter = 16
oMtvFlags = 24
oMtvTensor = 32
szDLManagedTensorVersioned = 80

-- | @(sizeof, [(field, offset)])@ in declaration order.
dlManagedTensorVersionedLayout :: (Int, [(String, Int)])
dlManagedTensorVersionedLayout =
  ( szDLManagedTensorVersioned
  , [ ("version", oMtvVersion)
    , ("manager_ctx", oMtvManagerCtx)
    , ("deleter", oMtvDeleter)
    , ("flags", oMtvFlags)
    , ("dl_tensor", oMtvTensor)
    ]
  )

instance Storable DLManagedTensorVersioned where
  sizeOf _ = szDLManagedTensorVersioned
  alignment _ = 8
  peek p =
    DLManagedTensorVersioned
      <$> peekByteOff p oMtvVersion
      <*> peekByteOff p oMtvManagerCtx
      <*> peekByteOff p oMtvDeleter
      <*> peekByteOff p oMtvFlags
      <*> peekByteOff p oMtvTensor
  poke p m = do
    pokeByteOff p oMtvVersion (mtvVersion m)
    pokeByteOff p oMtvManagerCtx (mtvManagerCtx m)
    pokeByteOff p oMtvDeleter (mtvDeleter m)
    pokeByteOff p oMtvFlags (mtvFlags m)
    pokeByteOff p oMtvTensor (mtvTensor m)

foreign import ccall "dynamic"
  callDeleter
    :: FunPtr (Ptr DLManagedTensorVersioned -> IO ())
    -> Ptr DLManagedTensorVersioned
    -> IO ()

-- | Invoke the tensor's deleter — the consumer-side "I am done" call.
-- A null deleter (legal per spec: the producer has nothing to free) is
-- a no-op.
callTensorDeleter :: Ptr DLManagedTensorVersioned -> IO ()
callTensorDeleter p = do
  fp <- peekByteOff p oMtvDeleter
  unless (fp == nullFunPtr) (callDeleter fp p)
