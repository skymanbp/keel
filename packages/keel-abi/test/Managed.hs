-- | Unit tests for the managed layer ("Keel.Abi.Arrow") that need no
-- foreign producer: Haskell plays both exporter and consumer.
module Main (main) where

import Control.Monad (forM_, unless)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Foreign.ForeignPtr (finalizeForeignPtr, withForeignPtr)
import GHC.Stats (GCDetails (..), RTSStats (..), getRTSStats, getRTSStatsEnabled)
import System.Mem (performMajorGC)
import Foreign.Marshal.Alloc (callocBytes, free, mallocBytes)
import Foreign.Ptr (Ptr, castPtr, nullFunPtr, nullPtr)
import Foreign.Storable (peek, peekElemOff, poke, pokeElemOff, sizeOf)

import Keel.Abi.Arrow
import Keel.Abi.Arrow.Raw
import Keel.Abi.DLPack
import Keel.Abi.DLPack.Raw

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

main :: IO ()
main = do
  -- 1. releasing a never-filled import target is a no-op (with* variant)
  r <- withArrowArrayImport $ \p -> do
    a <- peek p
    expect (arrayRelease a == nullFunPtr) "import target not zeroed"
    pure (42 :: Int)
  expect (r == 42) "with-import did not return the action result"

  -- 2. export -> consumer-release lifecycle, array side
  cnt <- newIORef (0 :: Int)
  p <- callocBytes (sizeOf (undefined :: ArrowArray))
  exportArrowArray p emptyArrowArray { arrayLength = 3 } (modifyIORef' cnt (+ 1))
  a0 <- peek p
  expect (arrayLength a0 == 3) "template field lost on export"
  expect (arrayRelease a0 /= nullFunPtr) "export installed no release"
  releaseArrowArray p
  releaseArrowArray p -- double release must be a no-op
  n <- readIORef cnt
  expect (n == 1) ("cleanup ran " <> show n <> " times, want 1")
  a1 <- peek p
  expect (arrayRelease a1 == nullFunPtr) "release not nulled"
  expect (arrayPrivateData a1 == nullPtr) "private_data not nulled"
  free p

  -- 3. same lifecycle, schema side
  scnt <- newIORef (0 :: Int)
  sp <- callocBytes (sizeOf (undefined :: ArrowSchema))
  exportArrowSchema sp emptyArrowSchema (modifyIORef' scnt (+ 1))
  releaseArrowSchema sp
  releaseArrowSchema sp
  sn <- readIORef scnt
  expect (sn == 1) ("schema cleanup ran " <> show sn <> " times, want 1")
  free sp

  -- 4. with-import releases an exported struct on scope exit
  wcnt <- newIORef (0 :: Int)
  withArrowArrayImport $ \wp ->
    exportArrowArray wp emptyArrowArray (modifyIORef' wcnt (+ 1))
  wn <- readIORef wcnt
  expect (wn == 1) ("bracket cleanup ran " <> show wn <> " times, want 1")

  -- 5. malloc variant: finalizeForeignPtr runs the release deterministically
  fcnt <- newIORef (0 :: Int)
  fp <- mallocArrowArrayImport
  withForeignPtr fp $ \rawp ->
    exportArrowArray rawp emptyArrowArray (modifyIORef' fcnt (+ 1))
  finalizeForeignPtr fp
  fn <- readIORef fcnt
  expect (fn == 1) ("finalizer cleanup ran " <> show fn <> " times, want 1")

  -- 6. exported stream: drive it as a consumer, entirely in-process
  streamCnt <- newIORef (0 :: Int)
  gnCalls <- newIORef (0 :: Int)
  stp <- callocBytes (sizeOf (undefined :: ArrowArrayStream))
  exportArrowArrayStream stp
    ArrowStreamProducer
      { producerGetSchema = \o -> do
          exportArrowSchema o emptyArrowSchema (pure ())
          pure 0
      , producerGetNext = \o -> do
          i <- readIORef gnCalls
          modifyIORef' gnCalls (+ 1)
          if i < 2
            then exportArrowArray o emptyArrowArray { arrayLength = fromIntegral (i + 1) } (pure ())
            else poke' o -- end-of-stream: zeroed struct, null release
          pure 0
      , producerGetLastError = pure nullPtr
      , producerCleanup = modifyIORef' streamCnt (+ 1)
      }
  st <- peek stp
  -- schema call
  withArrowSchemaImport $ \so -> do
    rc <- callStreamGetSchema (streamGetSchema st) stp so
    expect (rc == 0) "get_schema returned nonzero"
  -- two batches then end-of-stream
  lens <- mapM (const (nextLen st stp)) [1 :: Int, 2, 3]
  expect (lens == [Just 1, Just 2, Nothing]) ("stream batches: " <> show lens)
  releaseArrowArrayStream stp
  releaseArrowArrayStream stp -- double release no-op
  stn <- readIORef streamCnt
  expect (stn == 1) ("stream cleanup ran " <> show stn <> " times, want 1")
  free stp

  -- 7. DLPack: produce and consume entirely in-process
  dcnt <- newIORef (0 :: Int)
  dbuf <- mallocBytes (6 * 8) :: IO (Ptr Double)
  mapM_ (uncurry (pokeElemOff dbuf)) (zip [0 ..] [1 .. 6])
  mt <-
    newManagedTensor
      (DLDataType kDLFloat 64 1)
      [2, 3]
      (castPtr dbuf)
      dlpackFlagReadOnly
      (free dbuf >> modifyIORef' dcnt (+ 1))
  dvals <- consumeManagedTensor mt $ \m -> do
    expect (dlverMajor (mtvVersion m) == dlpackMajorVersion) "tensor version major"
    expect (mtvFlags m == dlpackFlagReadOnly) "tensor flags lost"
    let t = mtvTensor m
    expect (dltNDim t == 2) ("tensor ndim: " <> show (dltNDim t))
    dsh <- mapM (peekElemOff (dltShape t)) [0, 1]
    expect (dsh == [2, 3]) ("tensor shape: " <> show dsh)
    expect (dltStrides t == nullPtr) "strides not null (compact expected)"
    mapM (peekElemOff (castPtr (dltData t) :: Ptr Double)) [0 .. 5]
  expect (dvals == [1 .. 6]) ("tensor values: " <> show dvals)
  dn <- readIORef dcnt
  expect (dn == 1) ("tensor cleanup ran " <> show dn <> " times, want 1")

  -- 8. leak gate: 10k full export/release cycles must not grow the live
  -- Haskell heap (a leaked StablePtr or cleanup closure would). C-side
  -- malloc leaks are invisible here — that is the publish-stage valgrind
  -- lane's job.
  statsOn <- getRTSStatsEnabled
  expect statsOn "RTS stats disabled - test suite must be built with -with-rtsopts=-T"
  performMajorGC
  live0 <- gcdetails_live_bytes . gc <$> getRTSStats
  forM_ [1 :: Int .. 10000] $ \_ ->
    withArrowArrayImport $ \lp ->
      exportArrowArray lp emptyArrowArray (pure ())
  performMajorGC
  live1 <- gcdetails_live_bytes . gc <$> getRTSStats
  let grownKiB = (fromIntegral live1 - fromIntegral live0) `div` 1024 :: Integer
  expect (grownKiB < 1024)
    ("live heap grew " <> show grownKiB <> " KiB over 10k cycles (leak)")

  putStrLn "keel-abi: managed-layer lifecycle tests passed (8 scenarios)"
  where
    poke' o = poke o emptyArrowArray
    nextLen st stp = withArrowArrayImport $ \ao -> do
      rc <- callStreamGetNext (streamGetNext st) stp ao
      expect (rc == 0) "get_next returned nonzero"
      a <- peek ao
      pure $
        if arrayRelease a == nullFunPtr
          then Nothing
          else Just (arrayLength a)
