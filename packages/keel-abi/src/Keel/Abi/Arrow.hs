-- | Managed ownership over the raw Arrow C Data Interface structs.
--
-- The C Data Interface protocol: the /consumer/ allocates struct
-- storage and passes it to the producer to fill; whoever ends up holding
-- a filled struct must call its release callback exactly once. This
-- module packages both sides:
--
-- __Consumer (import)__: 'withArrowSchemaImport' \/ 'withArrowArrayImport'
-- allocate zeroed storage, hand it to your action (pass the pointer to
-- the foreign producer, then read the filled struct), and guarantee the
-- release callback runs on exit — including when the action throws.
-- A zeroed, never-filled struct has a null release member and releasing
-- it is a no-op, so allocation and release stay balanced no matter what
-- the producer did. The 'mallocArrowSchemaImport' variants give the same
-- storage as a 'ForeignPtr' whose finalizer releases at GC time, for
-- structs that must outlive a lexical scope.
--
-- __Producer (export)__: 'exportArrowSchema' \/ 'exportArrowArray' fill a
-- consumer-provided struct from a template record plus a cleanup action.
-- The installed release callback is one process-wide trampoline that
-- runs the cleanup exactly once, frees its 'StablePtr', and nulls the
-- struct's release member per spec — no per-export @\"wrapper\"@
-- 'FunPtr' is created, so there is nothing to free from inside its own
-- invocation (the classic exporter hazard).
module Keel.Abi.Arrow
  ( -- * Consumer side: allocate, let a producer fill, release
    withArrowSchemaImport
  , withArrowArrayImport
  , withArrowArrayStreamImport
  , mallocArrowSchemaImport
  , mallocArrowArrayImport
  , mallocArrowArrayStreamImport

    -- * Producer side: fill a consumer's struct
  , exportArrowSchema
  , exportArrowArray
  , ArrowStreamProducer (..)
  , exportArrowArrayStream
  ) where

import Control.Exception (bracket)
import Control.Monad (join)
import Foreign.C.String (CString)
import Foreign.C.Types (CInt (..))
import Foreign.Concurrent qualified as FC
import Foreign.ForeignPtr (ForeignPtr)
import Foreign.Marshal.Alloc (callocBytes, free)
import Foreign.Ptr (FunPtr, Ptr, freeHaskellFunPtr, nullFunPtr, nullPtr)
import Foreign.StablePtr
  ( StablePtr
  , castPtrToStablePtr
  , castStablePtrToPtr
  , deRefStablePtr
  , freeStablePtr
  , newStablePtr
  )
import Foreign.Storable (Storable, peek, poke, sizeOf)
import System.IO.Unsafe (unsafePerformIO)

import Keel.Abi.Arrow.Raw

-- ---------------------------------------------------------------------
-- Consumer side

withImport :: forall s a. Storable s => (Ptr s -> IO ()) -> (Ptr s -> IO a) -> IO a
withImport releaseIt act =
  bracket
    (callocBytes (sizeOf (undefined :: s)))
    (\p -> releaseIt p >> free p)
    act

-- | Zeroed 'ArrowSchema' storage for a producer to fill; released (if
-- filled) and freed on exit, exception-safe.
withArrowSchemaImport :: (Ptr ArrowSchema -> IO a) -> IO a
withArrowSchemaImport = withImport releaseArrowSchema

-- | Zeroed 'ArrowArray' storage for a producer to fill; released (if
-- filled) and freed on exit, exception-safe.
withArrowArrayImport :: (Ptr ArrowArray -> IO a) -> IO a
withArrowArrayImport = withImport releaseArrowArray

-- | Zeroed 'ArrowArrayStream' storage for a producer to fill; released
-- (if filled) and freed on exit, exception-safe.
withArrowArrayStreamImport :: (Ptr ArrowArrayStream -> IO a) -> IO a
withArrowArrayStreamImport = withImport releaseArrowArrayStream

mallocImport :: forall s. Storable s => (Ptr s -> IO ()) -> IO (ForeignPtr s)
mallocImport releaseIt = do
  p <- callocBytes (sizeOf (undefined :: s))
  FC.newForeignPtr p (releaseIt p >> free p)

-- | Like 'withArrowSchemaImport' but GC-managed: the release callback
-- (if the struct was filled) and the storage are reclaimed by the
-- finalizer. Prefer the @with@ variant when lifetime is lexical —
-- finalizers give no promptness guarantee.
mallocArrowSchemaImport :: IO (ForeignPtr ArrowSchema)
mallocArrowSchemaImport = mallocImport releaseArrowSchema

-- | GC-managed 'ArrowArray' import target; see 'mallocArrowSchemaImport'.
mallocArrowArrayImport :: IO (ForeignPtr ArrowArray)
mallocArrowArrayImport = mallocImport releaseArrowArray

-- | GC-managed 'ArrowArrayStream' import target; see
-- 'mallocArrowSchemaImport'.
mallocArrowArrayStreamImport :: IO (ForeignPtr ArrowArrayStream)
mallocArrowArrayStreamImport = mallocImport releaseArrowArrayStream

-- ---------------------------------------------------------------------
-- Producer side

foreign import ccall "wrapper"
  wrapSchemaRelease :: (Ptr ArrowSchema -> IO ()) -> IO (FunPtr (Ptr ArrowSchema -> IO ()))

foreign import ccall "wrapper"
  wrapArrayRelease :: (Ptr ArrowArray -> IO ()) -> IO (FunPtr (Ptr ArrowArray -> IO ()))

-- One process-wide trampoline per struct kind, never freed. It reads the
-- cleanup action out of private_data, runs it once, and marks the struct
-- released. Consumers may call release from any OS thread; a threaded
-- RTS handles that, a non-threaded one blocks the call until the RTS is
-- idle (standard foreign-export semantics).

{-# NOINLINE schemaReleaseTrampoline #-}
schemaReleaseTrampoline :: FunPtr (Ptr ArrowSchema -> IO ())
schemaReleaseTrampoline = unsafePerformIO . wrapSchemaRelease $ \p -> do
  s <- peek p
  runCleanup (schemaPrivateData s)
  poke p s { schemaRelease = nullFunPtr, schemaPrivateData = nullPtr }

{-# NOINLINE arrayReleaseTrampoline #-}
arrayReleaseTrampoline :: FunPtr (Ptr ArrowArray -> IO ())
arrayReleaseTrampoline = unsafePerformIO . wrapArrayRelease $ \p -> do
  a <- peek p
  runCleanup (arrayPrivateData a)
  poke p a { arrayRelease = nullFunPtr, arrayPrivateData = nullPtr }

runCleanup :: Ptr () -> IO ()
runCleanup pd = do
  let sp = castPtrToStablePtr pd :: StablePtr (IO ())
  join (deRefStablePtr sp)
  freeStablePtr sp

-- | Fill @out@ as an exported schema: every field is taken from the
-- template except @release@\/@private_data@, which are overwritten with
-- the trampoline and the cleanup action. The cleanup must free whatever
-- the template's pointers own (format\/name\/metadata strings, children,
-- dictionary) and runs exactly once, from whichever thread the consumer
-- releases on.
exportArrowSchema :: Ptr ArrowSchema -> ArrowSchema -> IO () -> IO ()
exportArrowSchema out template cleanup = do
  sp <- newStablePtr cleanup
  poke out
    template
      { schemaRelease = schemaReleaseTrampoline
      , schemaPrivateData = castStablePtrToPtr sp
      }

-- | Fill @out@ as an exported array; see 'exportArrowSchema'. The
-- cleanup must keep the buffers alive until it runs and then free them
-- (typically: 'Foreign.ForeignPtr.touchForeignPtr' captures, or explicit
-- 'free's of malloc'd buffers plus the buffer-pointer table).
exportArrowArray :: Ptr ArrowArray -> ArrowArray -> IO () -> IO ()
exportArrowArray out template cleanup = do
  sp <- newStablePtr cleanup
  poke out
    template
      { arrayRelease = arrayReleaseTrampoline
      , arrayPrivateData = castStablePtrToPtr sp
      }

-- ---------------------------------------------------------------------
-- Producer side: streams

-- | A Haskell implementation of an exported 'ArrowArrayStream'. The
-- consumer's struct pointer is dropped from each signature — callbacks
-- are closures, so carry state by capture, not through @private_data@.
data ArrowStreamProducer = ArrowStreamProducer
  { producerGetSchema :: Ptr ArrowSchema -> IO CInt
    -- ^ Fill the out-schema (e.g. via 'exportArrowSchema'); return 0,
    -- or an errno-style code on failure.
  , producerGetNext :: Ptr ArrowArray -> IO CInt
    -- ^ Fill the out-array with the next chunk, or zero the whole
    -- struct (null release member) to signal end-of-stream; return 0,
    -- or an errno-style code on failure.
  , producerGetLastError :: IO CString
    -- ^ Description of the last error, or 'nullPtr'. The string must
    -- stay valid until the next stream call.
  , producerCleanup :: IO ()
    -- ^ Runs exactly once when the consumer releases the stream.
  }

foreign import ccall "wrapper"
  wrapStreamGetSchema :: StreamGetSchemaFn -> IO (FunPtr StreamGetSchemaFn)

foreign import ccall "wrapper"
  wrapStreamGetNext :: StreamGetNextFn -> IO (FunPtr StreamGetNextFn)

foreign import ccall "wrapper"
  wrapStreamGetLastError :: StreamGetLastErrorFn -> IO (FunPtr StreamGetLastErrorFn)

{-# NOINLINE streamReleaseTrampoline #-}
streamReleaseTrampoline :: FunPtr (Ptr ArrowArrayStream -> IO ())
streamReleaseTrampoline = unsafePerformIO . wrapStreamRelease $ \p -> do
  s <- peek p
  runCleanup (streamPrivateData s)
  poke p s { streamRelease = nullFunPtr, streamPrivateData = nullPtr }

foreign import ccall "wrapper"
  wrapStreamRelease :: (Ptr ArrowArrayStream -> IO ()) -> IO (FunPtr (Ptr ArrowArrayStream -> IO ()))

-- | Fill @out@ as an exported stream backed by the producer's Haskell
-- callbacks. The release callback (the shared trampoline again) frees
-- the three callback 'FunPtr's — none of them is the one executing —
-- and then runs 'producerCleanup'.
exportArrowArrayStream :: Ptr ArrowArrayStream -> ArrowStreamProducer -> IO ()
exportArrowArrayStream out producer = do
  gsF <- wrapStreamGetSchema (\_self o -> producerGetSchema producer o)
  gnF <- wrapStreamGetNext (\_self o -> producerGetNext producer o)
  geF <- wrapStreamGetLastError (\_self -> producerGetLastError producer)
  sp <- newStablePtr $ do
    freeHaskellFunPtr gsF
    freeHaskellFunPtr gnF
    freeHaskellFunPtr geF
    producerCleanup producer
  poke out
    ArrowArrayStream
      { streamGetSchema = gsF
      , streamGetNext = gnF
      , streamGetLastError = geF
      , streamRelease = streamReleaseTrampoline
      , streamPrivateData = castStablePtrToPtr sp
      }
