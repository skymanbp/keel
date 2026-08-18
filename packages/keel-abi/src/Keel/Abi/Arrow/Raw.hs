-- | The Apache Arrow C Data Interface and C Stream Interface structs,
-- 1:1 and unmanaged.
--
-- Layouts are written out by hand against the frozen ABI
-- (<https://arrow.apache.org/docs/format/CDataInterface.html>), so this
-- module needs no headers and the library ships no C sources. The
-- test-suite layout gate (@test\/cbits\/layout_gate.c@) re-derives every
-- offset with a real C compiler and fails the build on any disagreement;
-- 'arrowSchemaLayout' & friends exist for that gate.
--
-- Everything here is raw: 'Ptr'-level records, manual ownership. The
-- release-callback discipline of the spec applies — consumers must call
-- 'releaseArrowSchema' \/ 'releaseArrowArray' exactly once when done, and
-- a moved (released) struct has a null 'schemaRelease' \/ 'arrayRelease'.
-- Managed import\/export lives one layer up, in @Keel.Abi.Arrow@.
module Keel.Abi.Arrow.Raw
  ( -- * ArrowSchema
    ArrowSchema (..)
  , releaseArrowSchema
  , arrowFlagDictionaryOrdered
  , arrowFlagNullable
  , arrowFlagMapKeysSorted

    -- * ArrowArray
  , ArrowArray (..)
  , releaseArrowArray

    -- * ArrowArrayStream
  , ArrowArrayStream (..)
  , StreamGetSchemaFn
  , StreamGetNextFn
  , StreamGetLastErrorFn
  , callStreamGetSchema
  , callStreamGetNext
  , callStreamGetLastError
  , releaseArrowArrayStream

    -- * Layout tables (consumed by the test-suite layout gate)
  , arrowSchemaLayout
  , arrowArrayLayout
  , arrowArrayStreamLayout
  ) where

import Control.Monad (unless)
import Data.Int (Int64)
import Foreign.C.String (CString)
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, Ptr, nullFunPtr)
import Foreign.Storable (Storable (..))

-- ---------------------------------------------------------------------
-- ArrowSchema

-- | @struct ArrowSchema@. Field semantics (format strings, ownership)
-- are exactly those of the C Data Interface spec.
data ArrowSchema = ArrowSchema
  { schemaFormat :: CString
  , schemaName :: CString
  , schemaMetadata :: CString
  , schemaFlags :: Int64
  , schemaNChildren :: Int64
  , schemaChildren :: Ptr (Ptr ArrowSchema)
  , schemaDictionary :: Ptr ArrowSchema
  , schemaRelease :: FunPtr (Ptr ArrowSchema -> IO ())
  , schemaPrivateData :: Ptr ()
  }

arrowFlagDictionaryOrdered, arrowFlagNullable, arrowFlagMapKeysSorted :: Int64
arrowFlagDictionaryOrdered = 1
arrowFlagNullable = 2
arrowFlagMapKeysSorted = 4

oSchemaFormat, oSchemaName, oSchemaMetadata, oSchemaFlags, oSchemaNChildren,
  oSchemaChildren, oSchemaDictionary, oSchemaRelease, oSchemaPrivateData,
  szArrowSchema :: Int
oSchemaFormat = 0
oSchemaName = 8
oSchemaMetadata = 16
oSchemaFlags = 24
oSchemaNChildren = 32
oSchemaChildren = 40
oSchemaDictionary = 48
oSchemaRelease = 56
oSchemaPrivateData = 64
szArrowSchema = 72

-- | @(sizeof, [(field, offset)])@ in declaration order — compared
-- verbatim against C @offsetof@ by the layout gate.
arrowSchemaLayout :: (Int, [(String, Int)])
arrowSchemaLayout =
  ( szArrowSchema
  , [ ("format", oSchemaFormat)
    , ("name", oSchemaName)
    , ("metadata", oSchemaMetadata)
    , ("flags", oSchemaFlags)
    , ("n_children", oSchemaNChildren)
    , ("children", oSchemaChildren)
    , ("dictionary", oSchemaDictionary)
    , ("release", oSchemaRelease)
    , ("private_data", oSchemaPrivateData)
    ]
  )

instance Storable ArrowSchema where
  sizeOf _ = szArrowSchema
  alignment _ = 8
  peek p =
    ArrowSchema
      <$> peekByteOff p oSchemaFormat
      <*> peekByteOff p oSchemaName
      <*> peekByteOff p oSchemaMetadata
      <*> peekByteOff p oSchemaFlags
      <*> peekByteOff p oSchemaNChildren
      <*> peekByteOff p oSchemaChildren
      <*> peekByteOff p oSchemaDictionary
      <*> peekByteOff p oSchemaRelease
      <*> peekByteOff p oSchemaPrivateData
  poke p s = do
    pokeByteOff p oSchemaFormat (schemaFormat s)
    pokeByteOff p oSchemaName (schemaName s)
    pokeByteOff p oSchemaMetadata (schemaMetadata s)
    pokeByteOff p oSchemaFlags (schemaFlags s)
    pokeByteOff p oSchemaNChildren (schemaNChildren s)
    pokeByteOff p oSchemaChildren (schemaChildren s)
    pokeByteOff p oSchemaDictionary (schemaDictionary s)
    pokeByteOff p oSchemaRelease (schemaRelease s)
    pokeByteOff p oSchemaPrivateData (schemaPrivateData s)

foreign import ccall "dynamic"
  callSchemaRelease :: FunPtr (Ptr ArrowSchema -> IO ()) -> Ptr ArrowSchema -> IO ()

-- | Call the struct's release callback unless it is already null (i.e.
-- the struct was moved or released before). Idempotent per the spec:
-- the callback itself nulls the release member.
releaseArrowSchema :: Ptr ArrowSchema -> IO ()
releaseArrowSchema p = do
  fp <- peekByteOff p oSchemaRelease
  unless (fp == nullFunPtr) (callSchemaRelease fp p)

-- ---------------------------------------------------------------------
-- ArrowArray

-- | @struct ArrowArray@. Buffer count and meaning follow the format
-- string of the corresponding 'ArrowSchema'.
data ArrowArray = ArrowArray
  { arrayLength :: Int64
  , arrayNullCount :: Int64
  , arrayOffset :: Int64
  , arrayNBuffers :: Int64
  , arrayNChildren :: Int64
  , arrayBuffers :: Ptr (Ptr ())
  , arrayChildren :: Ptr (Ptr ArrowArray)
  , arrayDictionary :: Ptr ArrowArray
  , arrayRelease :: FunPtr (Ptr ArrowArray -> IO ())
  , arrayPrivateData :: Ptr ()
  }

oArrayLength, oArrayNullCount, oArrayOffset, oArrayNBuffers, oArrayNChildren,
  oArrayBuffers, oArrayChildren, oArrayDictionary, oArrayRelease,
  oArrayPrivateData, szArrowArray :: Int
oArrayLength = 0
oArrayNullCount = 8
oArrayOffset = 16
oArrayNBuffers = 24
oArrayNChildren = 32
oArrayBuffers = 40
oArrayChildren = 48
oArrayDictionary = 56
oArrayRelease = 64
oArrayPrivateData = 72
szArrowArray = 80

-- | @(sizeof, [(field, offset)])@ in declaration order.
arrowArrayLayout :: (Int, [(String, Int)])
arrowArrayLayout =
  ( szArrowArray
  , [ ("length", oArrayLength)
    , ("null_count", oArrayNullCount)
    , ("offset", oArrayOffset)
    , ("n_buffers", oArrayNBuffers)
    , ("n_children", oArrayNChildren)
    , ("buffers", oArrayBuffers)
    , ("children", oArrayChildren)
    , ("dictionary", oArrayDictionary)
    , ("release", oArrayRelease)
    , ("private_data", oArrayPrivateData)
    ]
  )

instance Storable ArrowArray where
  sizeOf _ = szArrowArray
  alignment _ = 8
  peek p =
    ArrowArray
      <$> peekByteOff p oArrayLength
      <*> peekByteOff p oArrayNullCount
      <*> peekByteOff p oArrayOffset
      <*> peekByteOff p oArrayNBuffers
      <*> peekByteOff p oArrayNChildren
      <*> peekByteOff p oArrayBuffers
      <*> peekByteOff p oArrayChildren
      <*> peekByteOff p oArrayDictionary
      <*> peekByteOff p oArrayRelease
      <*> peekByteOff p oArrayPrivateData
  poke p a = do
    pokeByteOff p oArrayLength (arrayLength a)
    pokeByteOff p oArrayNullCount (arrayNullCount a)
    pokeByteOff p oArrayOffset (arrayOffset a)
    pokeByteOff p oArrayNBuffers (arrayNBuffers a)
    pokeByteOff p oArrayNChildren (arrayNChildren a)
    pokeByteOff p oArrayBuffers (arrayBuffers a)
    pokeByteOff p oArrayChildren (arrayChildren a)
    pokeByteOff p oArrayDictionary (arrayDictionary a)
    pokeByteOff p oArrayRelease (arrayRelease a)
    pokeByteOff p oArrayPrivateData (arrayPrivateData a)

foreign import ccall "dynamic"
  callArrayRelease :: FunPtr (Ptr ArrowArray -> IO ()) -> Ptr ArrowArray -> IO ()

-- | Call the struct's release callback unless it is already null.
releaseArrowArray :: Ptr ArrowArray -> IO ()
releaseArrowArray p = do
  fp <- peekByteOff p oArrayRelease
  unless (fp == nullFunPtr) (callArrayRelease fp p)

-- ---------------------------------------------------------------------
-- ArrowArrayStream

-- | @get_schema@: fills the out-struct, returns 0 or an errno-style code.
type StreamGetSchemaFn = Ptr ArrowArrayStream -> Ptr ArrowSchema -> IO CInt

-- | @get_next@: fills the out-struct, or marks end-of-stream by leaving
-- its release member null. Returns 0 or an errno-style code.
type StreamGetNextFn = Ptr ArrowArrayStream -> Ptr ArrowArray -> IO CInt

-- | @get_last_error@: description of the last error, or null.
type StreamGetLastErrorFn = Ptr ArrowArrayStream -> IO CString

-- | @struct ArrowArrayStream@ — all members are function pointers plus
-- @private_data@; drive it with the @call*@ wrappers below.
data ArrowArrayStream = ArrowArrayStream
  { streamGetSchema :: FunPtr StreamGetSchemaFn
  , streamGetNext :: FunPtr StreamGetNextFn
  , streamGetLastError :: FunPtr StreamGetLastErrorFn
  , streamRelease :: FunPtr (Ptr ArrowArrayStream -> IO ())
  , streamPrivateData :: Ptr ()
  }

oStreamGetSchema, oStreamGetNext, oStreamGetLastError, oStreamRelease,
  oStreamPrivateData, szArrowArrayStream :: Int
oStreamGetSchema = 0
oStreamGetNext = 8
oStreamGetLastError = 16
oStreamRelease = 24
oStreamPrivateData = 32
szArrowArrayStream = 40

-- | @(sizeof, [(field, offset)])@ in declaration order.
arrowArrayStreamLayout :: (Int, [(String, Int)])
arrowArrayStreamLayout =
  ( szArrowArrayStream
  , [ ("get_schema", oStreamGetSchema)
    , ("get_next", oStreamGetNext)
    , ("get_last_error", oStreamGetLastError)
    , ("release", oStreamRelease)
    , ("private_data", oStreamPrivateData)
    ]
  )

instance Storable ArrowArrayStream where
  sizeOf _ = szArrowArrayStream
  alignment _ = 8
  peek p =
    ArrowArrayStream
      <$> peekByteOff p oStreamGetSchema
      <*> peekByteOff p oStreamGetNext
      <*> peekByteOff p oStreamGetLastError
      <*> peekByteOff p oStreamRelease
      <*> peekByteOff p oStreamPrivateData
  poke p s = do
    pokeByteOff p oStreamGetSchema (streamGetSchema s)
    pokeByteOff p oStreamGetNext (streamGetNext s)
    pokeByteOff p oStreamGetLastError (streamGetLastError s)
    pokeByteOff p oStreamRelease (streamRelease s)
    pokeByteOff p oStreamPrivateData (streamPrivateData s)

foreign import ccall "dynamic"
  callStreamGetSchema :: FunPtr StreamGetSchemaFn -> StreamGetSchemaFn

foreign import ccall "dynamic"
  callStreamGetNext :: FunPtr StreamGetNextFn -> StreamGetNextFn

foreign import ccall "dynamic"
  callStreamGetLastError :: FunPtr StreamGetLastErrorFn -> StreamGetLastErrorFn

foreign import ccall "dynamic"
  callStreamRelease :: FunPtr (Ptr ArrowArrayStream -> IO ()) -> Ptr ArrowArrayStream -> IO ()

-- | Call the stream's release callback unless it is already null.
releaseArrowArrayStream :: Ptr ArrowArrayStream -> IO ()
releaseArrowArrayStream p = do
  fp <- peekByteOff p oStreamRelease
  unless (fp == nullFunPtr) (callStreamRelease fp p)
