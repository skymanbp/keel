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

import Control.Exception (SomeException, bracket, finally, mask_, try)
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
    (\p -> releaseIt p `finally` free p)
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

-- masked: an async exception between the allocation and the finalizer
-- registration would leak the block
mallocImport :: forall s. Storable s => (Ptr s -> IO ()) -> IO (ForeignPtr s)
mallocImport releaseIt = mask_ $ do
  p <- callocBytes (sizeOf (undefined :: s))
  FC.newForeignPtr p (releaseIt p `finally` free p)

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
  -- null the release member BEFORE the cleanup runs: the consumer then
  -- sees the spec-mandated released state no matter what the cleanup does
  poke p s { schemaRelease = nullFunPtr, schemaPrivateData = nullPtr }
  runCleanup (schemaPrivateData s)

{-# NOINLINE arrayReleaseTrampoline #-}
arrayReleaseTrampoline :: FunPtr (Ptr ArrowArray -> IO ())
arrayReleaseTrampoline = unsafePerformIO . wrapArrayRelease $ \p -> do
  a <- peek p
  poke p a { arrayRelease = nullFunPtr, arrayPrivateData = nullPtr }
  runCleanup (arrayPrivateData a)

-- Runs the carried cleanup and frees its StablePtr. The cleanup runs
-- under 'try' with the exception dropped: this executes inside a
-- callback invoked by foreign code, and a Haskell exception escaping
-- into a C caller is undefined behaviour (in practice it aborts the
-- process) — the C Data Interface expects release callbacks not to fail.
runCleanup :: Ptr () -> IO ()
runCleanup pd = do
  let sp = castPtrToStablePtr pd :: StablePtr (IO ())
  cleanup <- deRefStablePtr sp
  _ <- try @SomeException cleanup
  freeStablePtr sp

-- | Fill @out@ as an exported schema: every field is taken from the
-- template except @release@\/@private_data@, which are overwritten with
-- the trampoline and the cleanup action. The cleanup must free whatever
-- the template's pointers own (format\/name\/metadata strings, children,
-- dictionary) and runs exactly once, from whichever thread the consumer
-- releases on. It must not throw: a thrown exception is caught and
-- discarded — the C caller of the release callback cannot receive it.
exportArrowSchema :: Ptr ArrowSchema -> ArrowSchema -> IO () -> IO ()
exportArrowSchema out template cleanup = mask_ $ do
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
exportArrowArray out template cleanup = mask_ $ do
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
    -- or an errno-style code on failure. A thrown exception is caught
    -- and reported to the consumer as @EIO@ (5).
  , producerGetNext :: Ptr ArrowArray -> IO CInt
    -- ^ Fill the out-array with the next chunk, or zero the whole
    -- struct (null release member) to signal end-of-stream; return 0,
    -- or an errno-style code on failure. A thrown exception is caught
    -- and reported to the consumer as @EIO@ (5).
  , producerGetLastError :: IO CString
    -- ^ Description of the last error, or 'nullPtr'. The string must
    -- stay valid until the next stream call. A thrown exception is
    -- caught and reported as 'nullPtr'.
  , producerCleanup :: IO ()
    -- ^ Runs exactly once when the consumer releases the stream. Must
    -- not throw: a thrown exception is caught and discarded.
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
  poke p s { streamRelease = nullFunPtr, streamPrivateData = nullPtr }
  runCleanup (streamPrivateData s)

foreign import ccall "wrapper"
  wrapStreamRelease :: (Ptr ArrowArrayStream -> IO ()) -> IO (FunPtr (Ptr ArrowArrayStream -> IO ()))

-- These callbacks execute inside a call from foreign code, where a
-- Haskell exception must not escape (undefined behaviour in the C
-- caller) — it is caught and mapped to the value the protocol can
-- carry: an errno-style code, or a null error string.
guardErrno :: IO CInt -> IO CInt
guardErrno act = either (\(_ :: SomeException) -> 5 {- EIO -}) id <$> try act

guardLastError :: IO CString -> IO CString
guardLastError act = either (\(_ :: SomeException) -> nullPtr) id <$> try act

-- | Fill @out@ as an exported stream backed by the producer's Haskell
-- callbacks. The release callback (the shared trampoline again) frees
-- the three callback 'FunPtr's — none of them is the one executing —
-- and then runs 'producerCleanup'.
exportArrowArrayStream :: Ptr ArrowArrayStream -> ArrowStreamProducer -> IO ()
exportArrowArrayStream out producer = mask_ $ do
  gsF <- wrapStreamGetSchema (\_self o -> guardErrno (producerGetSchema producer o))
  gnF <- wrapStreamGetNext (\_self o -> guardErrno (producerGetNext producer o))
  geF <- wrapStreamGetLastError (\_self -> guardLastError (producerGetLastError producer))
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
