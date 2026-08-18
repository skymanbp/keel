-- | Conformance test: round-trip the Arrow C Data Interface against
-- pyarrow, in-process, in both directions.
--
-- CPython is loaded at run time through keel-dyn (dogfooding the
-- capability floor), then:
--
-- * import direction: pyarrow builds @[1, 2, 3, None, 5] :: int64@ and
--   exports it into Haskell-allocated structs; Haskell verifies format,
--   length, null bitmap and values, then calls pyarrow's release
--   callbacks and checks they null themselves per spec;
-- * export direction: Haskell hand-builds @[10, 20, 30] :: int64@ with
--   release callbacks made by @foreign import ccall \"wrapper\"@;
--   pyarrow imports, checks the values in Python, and drops the array —
--   which must call back into Haskell and free our buffers.
--
-- If no usable python + pyarrow is found the test SKIPs (prints why,
-- exits 0) unless @KEEL_ABI_REQUIRE_PYARROW@ is set non-empty\/non-zero,
-- in which case absence is a failure. Publish-stage CI sets it.
module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (unless, when)
import Data.Bits ((.&.))
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
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

  -- ------------------------------------------------------------------
  -- Direction 1: pyarrow -> Haskell
  impArr <- callocBytes (sizeOf (undefined :: ArrowArray))
  impSch <- callocBytes (sizeOf (undefined :: ArrowSchema))
  runScript "import-direction" $
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

  -- consumer duty: release both, then verify the callbacks nulled
  -- themselves (spec conformance of *pyarrow's* callbacks, and of our
  -- call-through machinery)
  releaseArrowArray impArr
  releaseArrowSchema impSch
  arrAfter <- peek impArr
  schAfter <- peek impSch
  expect (arrayRelease arrAfter == nullFunPtr) "array release not nulled after release"
  expect (schemaRelease schAfter == nullFunPtr) "schema release not nulled after release"
  free impArr
  free impSch

  -- ------------------------------------------------------------------
  -- Direction 2: Haskell -> pyarrow
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
    ArrowSchema
      { schemaFormat = expFmt
      , schemaName = nullPtr
      , schemaMetadata = nullPtr
      , schemaFlags = arrowFlagNullable
      , schemaNChildren = 0
      , schemaChildren = nullPtr
      , schemaDictionary = nullPtr
      , schemaRelease = sRel
      , schemaPrivateData = nullPtr
      }
  poke expArr
    ArrowArray
      { arrayLength = 3
      , arrayNullCount = 0
      , arrayOffset = 0
      , arrayNBuffers = 2
      , arrayNChildren = 0
      , arrayBuffers = bufArr
      , arrayChildren = nullPtr
      , arrayDictionary = nullPtr
      , arrayRelease = aRel
      , arrayPrivateData = nullPtr
      }

  runScript "export-direction" $
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

  fin <- mkPyFinalize pyFin
  when (fin /= 0) (putStrLn "note: Py_FinalizeEx reported errors (ignored)")
  closeLibrary lib
  putStrLn "keel-abi-pyarrow: both directions round-tripped against pyarrow"

-- Our exporter-side release callbacks: free what we allocated, then null
-- the release member per spec (peek/poke of the whole struct keeps the
-- Raw module's offsets private).
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
