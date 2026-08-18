-- | Conformance test: round-trip the Arrow C Data Interface AND the
-- C Stream Interface against pyarrow, in-process, in both directions.
--
-- CPython is loaded at run time through keel-dyn (dogfooding the
-- capability floor). Four directions:
--
-- 1. array  pyarrow -> Haskell: @[1, 2, 3, None, 5] :: int64@; verify
--    format\/length\/null bitmap\/values, release, check the callbacks
--    null themselves per spec (raw-layer conformance, managed alloc);
-- 2. array  Haskell -> pyarrow: hand-built @[10, 20, 30]@ with raw
--    @\"wrapper\"@ release callbacks; Python verifies and drops it,
--    which must call back into Haskell and free our buffers;
-- 3. stream pyarrow -> Haskell: a two-batch RecordBatchReader; verify
--    struct schema (+s with int64 child \"x\"), both batches, and the
--    end-of-stream convention;
-- 4. stream Haskell -> pyarrow: an 'ArrowStreamProducer' serving two
--    batches through the managed export layer; Python @read_all()@s,
--    verifies, and drops it — our cleanup must run.
--
-- If no usable python + pyarrow is found the test SKIPs (prints why,
-- exits 0) unless @KEEL_ABI_REQUIRE_PYARROW@ is set non-empty\/non-zero,
-- in which case absence is a failure. Publish-stage CI sets it.
module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (forM, unless, when)
import Data.Bits ((.&.))
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Int (Int64)
import Data.Word (Word8)
import Foreign.C.String (CString, newCString, peekCString, withCString)
import Foreign.C.Types (CInt (..))
import Foreign.Marshal.Alloc (callocBytes, free, mallocBytes)
import Foreign.Ptr
  ( FunPtr
  , Ptr
  , castPtr
  , freeHaskellFunPtr
  , nullFunPtr
  , nullPtr
  , ptrToIntPtr
  )
import Foreign.Storable (peek, peekElemOff, poke, pokeElemOff, sizeOf)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

import Keel.Abi.Arrow
import Keel.Abi.Arrow.Raw
import Keel.Dyn

-- ---------------------------------------------------------------------
-- Python C API via keel-dyn (all calls 'safe': python re-enters Haskell
-- through our release callbacks)

foreign import ccall safe "dynamic"
  mkPyInitEx :: FunPtr (CInt -> IO ()) -> CInt -> IO ()

foreign import ccall safe "dynamic"
  mkPyRun :: FunPtr (CString -> IO CInt) -> CString -> IO CInt

foreign import ccall safe "dynamic"
  mkPyFinalize :: FunPtr (IO CInt) -> IO CInt

foreign import ccall "wrapper"
  mkSchemaRelease :: (Ptr ArrowSchema -> IO ()) -> IO (FunPtr (Ptr ArrowSchema -> IO ()))

foreign import ccall "wrapper"
  mkArrayRelease :: (Ptr ArrowArray -> IO ()) -> IO (FunPtr (Ptr ArrowArray -> IO ()))

-- ---------------------------------------------------------------------
-- Discovery (out of process, so a broken python cannot kill the test)

runPy :: String -> [String] -> IO (Maybe String)
runPy exe args = do
  r <- try (readProcessWithExitCode exe args "")
        :: IO (Either IOException (ExitCode, String, String))
  pure $ case r of
    Right (ExitSuccess, out, _) -> Just (filter (`notElem` "\r\n") out)
    _ -> Nothing

findPython :: IO (Maybe (String, FilePath))
findPython = go ["python", "python3"]
  where
    dllScript =
      "import sys, sysconfig, os\n\
      \if os.name == 'nt':\n\
      \    print(os.path.join(sys.base_prefix, 'python%d%d.dll' % sys.version_info[:2]))\n\
      \else:\n\
      \    print(os.path.join(sysconfig.get_config_var('LIBDIR') or '', sysconfig.get_config_var('INSTSONAME') or ''))\n"
    go [] = pure Nothing
    go (exe : rest) = do
      ok <- runPy exe ["-c", "import pyarrow"]
      case ok of
        Nothing -> go rest
        Just _ -> do
          mdll <- runPy exe ["-c", dllScript]
          pure ((,) exe <$> mdll)

-- ---------------------------------------------------------------------

expect :: Bool -> String -> IO ()
expect ok msg = unless ok (fail msg)

addr :: Ptr a -> String
addr = show . ptrToIntPtr

type RunScript = String -> String -> IO ()

main :: IO ()
main = do
  found <- findPython
  required <- lookupEnv "KEEL_ABI_REQUIRE_PYARROW"
  case found of
    Nothing -> case required of
      Just v | v /= "" && v /= "0" ->
        fail "KEEL_ABI_REQUIRE_PYARROW set but no usable python+pyarrow found"
      _ -> putStrLn "keel-abi-pyarrow: SKIP - no usable python+pyarrow on this machine"
    Just (_, dll) -> runConformance dll

runConformance :: FilePath -> IO ()
runConformance dll = do
  lib <- either (\e -> fail ("load python: " <> show e)) pure =<< loadLibrary dll
  pyInitEx <- requireSym lib "Py_InitializeEx"
  pyRun <- requireSym lib "PyRun_SimpleString"
  pyFin <- requireSym lib "Py_FinalizeEx"
  mkPyInitEx pyInitEx 0
  let runScript label script = do
        rc <- withCString script (mkPyRun pyRun)
        expect (rc == 0) (label <> ": python script failed (traceback above)")

  arrayImportDirection runScript
  arrayExportDirection runScript
  streamImportDirection runScript
  streamExportDirection runScript

  fin <- mkPyFinalize pyFin
  when (fin /= 0) (putStrLn "note: Py_FinalizeEx reported errors (ignored)")
  closeLibrary lib
  putStrLn "keel-abi-pyarrow: arrays and streams round-tripped both directions"

-- ---------------------------------------------------------------------
-- Direction 1: array, pyarrow -> Haskell

arrayImportDirection :: RunScript -> IO ()
arrayImportDirection runScript =
  withArrowArrayImport $ \impArr ->
    withArrowSchemaImport $ \impSch -> do
      runScript "array-import" $
        "import pyarrow as pa\n\
        \arr = pa.array([1, 2, 3, None, 5], type=pa.int64())\n\
        \arr._export_to_c(" <> addr impArr <> ", " <> addr impSch <> ")\n"

      sch <- peek impSch
      fmt <- peekCString (schemaFormat sch)
      expect (fmt == "l") ("schema format: expected \"l\", got " <> show fmt)
      expect (schemaFlags sch .&. arrowFlagNullable /= 0) "schema not flagged nullable"

      arr <- peek impArr
      expect (arrayLength arr == 5) ("length: " <> show (arrayLength arr))
      expect (arrayNullCount arr == 1) ("null_count: " <> show (arrayNullCount arr))
      expect (arrayNBuffers arr == 2) ("n_buffers: " <> show (arrayNBuffers arr))
      expect (arrayOffset arr == 0) ("offset: " <> show (arrayOffset arr))

      validity <- peekElemOff (arrayBuffers arr) 0
      expect (validity /= nullPtr) "validity bitmap missing despite a null"
      vbyte <- peek (castPtr validity :: Ptr Word8)
      expect (vbyte .&. 0x1F == 0x17) -- rows 0,1,2,4 valid, row 3 null
        ("validity bitmap byte: " <> show vbyte)

      dataBuf <- peekElemOff (arrayBuffers arr) 1
      vals <- mapM (peekElemOff (castPtr dataBuf :: Ptr Int64)) [0, 1, 2, 4]
      expect (vals == [1, 2, 3, 5]) ("values: " <> show vals)

      -- release early (the with-brackets would anyway), then verify the
      -- callbacks nulled themselves per spec
      releaseArrowArray impArr
      releaseArrowSchema impSch
      arrAfter <- peek impArr
      schAfter <- peek impSch
      expect (arrayRelease arrAfter == nullFunPtr) "array release not nulled"
      expect (schemaRelease schAfter == nullFunPtr) "schema release not nulled"

-- ---------------------------------------------------------------------
-- Direction 2: array, Haskell -> pyarrow (raw-layer wrappers on purpose)

arrayExportDirection :: RunScript -> IO ()
arrayExportDirection runScript = do
  expData <- mallocBytes (3 * 8) :: IO (Ptr Int64)
  mapM_ (uncurry (pokeElemOff expData)) (zip [0 ..] [10, 20, 30])
  bufArr <- mallocBytes (2 * 8) :: IO (Ptr (Ptr ()))
  pokeElemOff bufArr 0 nullPtr
  pokeElemOff bufArr 1 (castPtr expData)
  expFmt <- newCString "l"

  schemaReleased <- newIORef False
  arrayReleased <- newIORef False
  sRel <- mkSchemaRelease (schemaReleaseAction schemaReleased)
  aRel <- mkArrayRelease (arrayReleaseAction arrayReleased)

  expArr <- callocBytes (sizeOf (undefined :: ArrowArray))
  expSch <- callocBytes (sizeOf (undefined :: ArrowSchema))
  poke expSch
    emptyArrowSchema
      { schemaFormat = expFmt
      , schemaFlags = arrowFlagNullable
      , schemaRelease = sRel
      }
  poke expArr
    emptyArrowArray
      { arrayLength = 3
      , arrayNBuffers = 2
      , arrayBuffers = bufArr
      , arrayRelease = aRel
      }

  runScript "array-export" $
    "import pyarrow as pa, gc\n\
    \imp = pa.Array._import_from_c(" <> addr expArr <> ", " <> addr expSch <> ")\n\
    \got = imp.to_pylist()\n\
    \if got != [10, 20, 30]:\n\
    \    raise RuntimeError('roundtrip mismatch: %r' % (got,))\n\
    \del imp\n\
    \gc.collect()\n"

  sDone <- readIORef schemaReleased
  aDone <- readIORef arrayReleased
  expect sDone "pyarrow never called our schema release callback"
  expect aDone "pyarrow never called our array release callback"
  free expArr
  free expSch
  freeHaskellFunPtr sRel
  freeHaskellFunPtr aRel

-- Raw exporter-side release callbacks: free what we allocated, then null
-- the release member per spec.
schemaReleaseAction :: IORef Bool -> Ptr ArrowSchema -> IO ()
schemaReleaseAction flag p = do
  s <- peek p
  free (schemaFormat s)
  poke p s { schemaRelease = nullFunPtr }
  writeIORef flag True

arrayReleaseAction :: IORef Bool -> Ptr ArrowArray -> IO ()
arrayReleaseAction flag p = do
  a <- peek p
  d <- peekElemOff (arrayBuffers a) 1
  free d
  free (arrayBuffers a)
  poke p a { arrayRelease = nullFunPtr }
  writeIORef flag True

-- ---------------------------------------------------------------------
-- Direction 3: stream, pyarrow -> Haskell

streamImportDirection :: RunScript -> IO ()
streamImportDirection runScript =
  withArrowArrayStreamImport $ \stp -> do
    runScript "stream-import" $
      "import pyarrow as pa\n\
      \schema = pa.schema([('x', pa.int64())])\n\
      \batches = [pa.record_batch([pa.array([1, 2, 3])], schema=schema),\n\
      \           pa.record_batch([pa.array([4, 5])], schema=schema)]\n\
      \reader = pa.RecordBatchReader.from_batches(schema, batches)\n\
      \reader._export_to_c(" <> addr stp <> ")\n"

    st <- peek stp
    withArrowSchemaImport $ \so -> do
      rc <- callStreamGetSchema (streamGetSchema st) stp so
      expect (rc == 0) "stream get_schema returned nonzero"
      sch <- peek so
      fmt <- peekCString (schemaFormat sch)
      expect (fmt == "+s") ("stream schema format: " <> show fmt)
      expect (schemaNChildren sch == 1) "stream schema child count"
      childP <- peekElemOff (schemaChildren sch) 0
      child <- peek childP
      cfmt <- peekCString (schemaFormat child)
      cname <- peekCString (schemaName child)
      expect (cfmt == "l") ("child format: " <> show cfmt)
      expect (cname == "x") ("child name: " <> show cname)

    b1 <- readBatch st stp
    b2 <- readBatch st stp
    b3 <- readBatch st stp
    expect (b1 == Just [1, 2, 3]) ("batch 1: " <> show b1)
    expect (b2 == Just [4, 5]) ("batch 2: " <> show b2)
    expect (b3 == Nothing) ("expected end-of-stream, got " <> show b3)

-- Read one record batch (struct array, one int64 child) from an
-- imported stream; Nothing = end-of-stream per the null-release rule.
readBatch :: ArrowArrayStream -> Ptr ArrowArrayStream -> IO (Maybe [Int64])
readBatch st stp =
  withArrowArrayImport $ \ao -> do
    rc <- callStreamGetNext (streamGetNext st) stp ao
    expect (rc == 0) "stream get_next returned nonzero"
    a <- peek ao
    if arrayRelease a == nullFunPtr
      then pure Nothing
      else do
        expect (arrayNChildren a == 1) "batch child count"
        childP <- peekElemOff (arrayChildren a) 0
        child <- peek childP
        dataBuf <- peekElemOff (arrayBuffers child) 1
        vals <- forM [0 .. fromIntegral (arrayLength child) - 1] $
          peekElemOff (castPtr dataBuf :: Ptr Int64)
        pure (Just vals)

-- ---------------------------------------------------------------------
-- Direction 4: stream, Haskell -> pyarrow (managed export layer)

streamExportDirection :: RunScript -> IO ()
streamExportDirection runScript = do
  cleanupRan <- newIORef False
  batchIx <- newIORef (0 :: Int)
  stp <- callocBytes (sizeOf (undefined :: ArrowArrayStream))
  exportArrowArrayStream stp
    ArrowStreamProducer
      { producerGetSchema = \o -> buildStructSchema o >> pure 0
      , producerGetNext = \o -> do
          i <- readIORef batchIx
          modifyIORef' batchIx (+ 1)
          case batchVals i of
            Just vs -> buildStructBatch o vs >> pure 0
            Nothing -> poke o emptyArrowArray >> pure 0
      , producerGetLastError = pure nullPtr
      , producerCleanup = writeIORef cleanupRan True
      }

  runScript "stream-export" $
    "import pyarrow as pa, gc\n\
    \r = pa.RecordBatchReader._import_from_c(" <> addr stp <> ")\n\
    \tbl = r.read_all()\n\
    \got = tbl.column('x').to_pylist()\n\
    \if got != [10, 20, 30, 40, 50]:\n\
    \    raise RuntimeError('stream mismatch: %r' % (got,))\n\
    \del r, tbl\n\
    \gc.collect()\n"

  done <- readIORef cleanupRan
  expect done "pyarrow never released our exported stream"
  free stp
  where
    batchVals :: Int -> Maybe [Int64]
    batchVals 0 = Just [10, 20, 30]
    batchVals 1 = Just [40, 50]
    batchVals _ = Nothing

-- Build the stream schema: struct "+s" with a single nullable int64
-- child named "x". Parent release cascades into the child per spec.
buildStructSchema :: Ptr ArrowSchema -> IO ()
buildStructSchema out = do
  childFmt <- newCString "l"
  childName <- newCString "x"
  child <- callocBytes (sizeOf (undefined :: ArrowSchema))
  exportArrowSchema child
    emptyArrowSchema
      { schemaFormat = childFmt
      , schemaName = childName
      , schemaFlags = arrowFlagNullable
      }
    (free childFmt >> free childName)
  kids <- mallocBytes 8
  pokeElemOff kids 0 child
  parentFmt <- newCString "+s"
  exportArrowSchema out
    emptyArrowSchema
      { schemaFormat = parentFmt
      , schemaNChildren = 1
      , schemaChildren = kids
      }
    (releaseArrowSchema child >> free child >> free kids >> free parentFmt)

-- Build one record batch: a struct array (validity-only buffer list)
-- with a single int64 child. Parent release cascades into the child.
buildStructBatch :: Ptr ArrowArray -> [Int64] -> IO ()
buildStructBatch out vs = do
  let n = length vs
  dataBuf <- mallocBytes (n * 8) :: IO (Ptr Int64)
  mapM_ (uncurry (pokeElemOff dataBuf)) (zip [0 ..] vs)
  childBufs <- mallocBytes (2 * 8) :: IO (Ptr (Ptr ()))
  pokeElemOff childBufs 0 nullPtr
  pokeElemOff childBufs 1 (castPtr dataBuf)
  child <- callocBytes (sizeOf (undefined :: ArrowArray))
  exportArrowArray child
    emptyArrowArray
      { arrayLength = fromIntegral n
      , arrayNBuffers = 2
      , arrayBuffers = childBufs
      }
    (free dataBuf >> free childBufs)
  kids <- mallocBytes 8
  pokeElemOff kids 0 child
  parentBufs <- mallocBytes 8 :: IO (Ptr (Ptr ()))
  pokeElemOff parentBufs 0 nullPtr
  exportArrowArray out
    emptyArrowArray
      { arrayLength = fromIntegral n
      , arrayNBuffers = 1
      , arrayBuffers = parentBufs
      , arrayNChildren = 1
      , arrayChildren = kids
      }
    (releaseArrowArray child >> free child >> free kids >> free parentBufs)
