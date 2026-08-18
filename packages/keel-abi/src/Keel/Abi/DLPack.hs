-- | Managed ownership over DLPack's versioned exchange tensor.
--
-- The DLPack contract: the producer hands over a
-- 'DLManagedTensorVersioned' (usually inside a @dltensor_versioned@
-- PyCapsule); the consumer checks the major version, uses the data, and
-- calls the deleter exactly once. This module packages both sides the
-- same way "Keel.Abi.Arrow" does for Arrow structs: consumption under
-- 'Control.Exception.finally', production through a process-wide deleter
-- trampoline plus a 'Foreign.StablePtr.StablePtr'-carried cleanup.
module Keel.Abi.DLPack
  ( AbiError (..)

    -- * Consumer side
  , consumeManagedTensor

    -- * Producer side
  , newManagedTensor
  ) where

import Control.Exception (Exception, finally, throwIO)
import Control.Monad (join)
import Data.Int (Int64)
import Data.Word (Word32, Word64)
import Foreign.Marshal.Alloc (free, mallocBytes)
import Foreign.Ptr (FunPtr, Ptr, nullPtr, plusPtr)
import Foreign.StablePtr
  ( StablePtr
  , castPtrToStablePtr
  , castStablePtrToPtr
  , deRefStablePtr
  , freeStablePtr
  , newStablePtr
  )
import Foreign.Storable (peek, poke, pokeElemOff, sizeOf)
import System.IO.Unsafe (unsafePerformIO)

import Keel.Abi.DLPack.Raw

-- | Failure modes of the exchange protocol itself.
newtype AbiError = DLPackMajorUnsupported Word32
    -- ^ The producer filled the struct under a DLPack major version
    -- newer than these bindings ('dlpackMajorVersion') understand.
  deriving (Eq, Show)

instance Exception AbiError

-- | Take ownership of a produced tensor: run the action on the peeked
-- struct, then invoke the deleter — also when the action throws. If the
-- producer's major version is newer than 'dlpackMajorVersion', the
-- tensor is deleted unused (the version\/deleter prologue is stable
-- across majors by design) and 'DLPackMajorUnsupported' is thrown.
consumeManagedTensor
  :: Ptr DLManagedTensorVersioned
  -> (DLManagedTensorVersioned -> IO a)
  -> IO a
consumeManagedTensor p act = do
  m <- peek p
  let major = dlverMajor (mtvVersion m)
  if major > dlpackMajorVersion
    then do
      callTensorDeleter p
      throwIO (DLPackMajorUnsupported major)
    else act m `finally` callTensorDeleter p

foreign import ccall "wrapper"
  wrapDeleter
    :: (Ptr DLManagedTensorVersioned -> IO ())
    -> IO (FunPtr (Ptr DLManagedTensorVersioned -> IO ()))

-- One process-wide deleter, never freed: runs the cleanup carried in
-- manager_ctx, then frees the struct block itself (the deleter deletes
-- @self@ per spec).
{-# NOINLINE deleterTrampoline #-}
deleterTrampoline :: FunPtr (Ptr DLManagedTensorVersioned -> IO ())
deleterTrampoline = unsafePerformIO . wrapDeleter $ \p -> do
  m <- peek p
  let sp = castPtrToStablePtr (mtvManagerCtx m) :: StablePtr (IO ())
  join (deRefStablePtr sp)
  freeStablePtr sp
  free p

-- | Allocate and fill a 'DLManagedTensorVersioned' for handoff to a
-- consumer. The shape array lives in the same allocation as the struct;
-- the tensor is CPU-device, compact row-major (null strides), zero byte
-- offset, version 'dlpackMajorVersion'.'dlpackMinorVersion'. The cleanup
-- runs exactly once — from the consumer's deleter call, on whatever
-- thread that happens — and must free\/unpin the data buffer; the
-- struct block frees itself afterwards.
newManagedTensor
  :: DLDataType
  -> [Int64] -- ^ shape (row-major, compact)
  -> Ptr () -- ^ data
  -> Word64 -- ^ flags ('dlpackFlagReadOnly' \/ 'dlpackFlagIsCopied' \/ 0)
  -> IO () -- ^ cleanup, owns the data buffer
  -> IO (Ptr DLManagedTensorVersioned)
newManagedTensor dt shape dat flags cleanup = do
  let ndim = length shape
      structSz = sizeOf (undefined :: DLManagedTensorVersioned)
  p <- mallocBytes (structSz + ndim * 8)
  let shapeP = p `plusPtr` structSz
  mapM_ (uncurry (pokeElemOff shapeP)) (zip [0 ..] shape)
  sp <- newStablePtr cleanup
  poke p
    DLManagedTensorVersioned
      { mtvVersion = DLPackVersion dlpackMajorVersion dlpackMinorVersion
      , mtvManagerCtx = castStablePtrToPtr sp
      , mtvDeleter = deleterTrampoline
      , mtvFlags = flags
      , mtvTensor =
          DLTensor
            { dltData = dat
            , dltDevice = DLDevice kDLCPU 0
            , dltNDim = fromIntegral ndim
            , dltDType = dt
            , dltShape = shapeP
            , dltStrides = nullPtr
            , dltByteOffset = 0
            }
      }
  pure p
