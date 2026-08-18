-- | Conformance test: exchange DLPack v1.x versioned tensors with numpy,
-- in-process, in both directions.
--
-- CPython is loaded at run time through keel-dyn (see "PyEmbed").
--
-- * import direction: numpy exports @arange(6, float64)@ as a
--   @dltensor_versioned@ PyCapsule; the script writes the raw pointer
--   into a Haskell-allocated slot and renames the capsule to
--   @used_dltensor_versioned@ (ownership transferred to us); Haskell
--   verifies version\/dtype\/shape\/values under 'consumeManagedTensor',
--   whose exit calls numpy's deleter;
-- * export direction: Haskell builds a 2x3 float64 tensor with
--   'newManagedTensor'; a minimal producer class hands the capsule to
--   @np.from_dlpack@; Python verifies shape and values and drops the
--   array — numpy's consumer must call our deleter trampoline, which
--   runs our cleanup.
--
-- Requires numpy >= 2.1 (DLPack 1.0 protocol support); older or absent
-- numpy SKIPs unless @KEEL_ABI_REQUIRE_NUMPY@ is set (CI sets it).
module Main (main) where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Int (Int64)
import Foreign.Marshal.Alloc (callocBytes, free, mallocBytes)
import Foreign.Ptr (Ptr, castPtr, nullPtr)
import Foreign.Storable (peek, peekElemOff, pokeElemOff)

import Keel.Abi.DLPack
import Keel.Abi.DLPack.Raw
import PyEmbed

main :: IO ()
main = withEmbeddedPython "numpy" "KEEL_ABI_REQUIRE_NUMPY" $ \runScript -> do
  importDirection runScript
  exportDirection runScript
  putStrLn "keel-abi-dlpack: tensors round-tripped both directions against numpy"

-- ---------------------------------------------------------------------
-- Direction 1: numpy -> Haskell

importDirection :: RunScript -> IO ()
importDirection runScript = do
  slot <- callocBytes 8 :: IO (Ptr (Ptr DLManagedTensorVersioned))
  runScript "dlpack-import" $
    "import numpy as np, ctypes\n\
    \a = np.arange(6, dtype=np.float64)\n\
    \cap = a.__dlpack__(max_version=(1, 1))\n\
    \ctypes.pythonapi.PyCapsule_GetPointer.restype = ctypes.c_void_p\n\
    \ctypes.pythonapi.PyCapsule_GetPointer.argtypes = [ctypes.py_object, ctypes.c_char_p]\n\
    \p = ctypes.pythonapi.PyCapsule_GetPointer(cap, b'dltensor_versioned')\n\
    \ctypes.pythonapi.PyCapsule_SetName.argtypes = [ctypes.py_object, ctypes.c_char_p]\n\
    \ctypes.pythonapi.PyCapsule_SetName(cap, b'used_dltensor_versioned')\n\
    \ctypes.c_void_p.from_address(" <> addr slot <> ").value = p\n"
  mtp <- peek slot
  expect (mtp /= nullPtr) "python wrote no tensor pointer"

  vals <- consumeManagedTensor mtp $ \m -> do
    expect (dlverMajor (mtvVersion m) == dlpackMajorVersion)
      ("producer major version: " <> show (dlverMajor (mtvVersion m)))
    let t = mtvTensor m
    expect (dldtCode (dltDType t) == kDLFloat) "dtype code not float"
    expect (dldtBits (dltDType t) == 64) "dtype bits not 64"
    expect (dldtLanes (dltDType t) == 1) "dtype lanes not 1"
    expect (dldevType (dltDevice t) == kDLCPU) "device not CPU"
    expect (dltNDim t == 1) ("ndim: " <> show (dltNDim t))
    sh <- peekElemOff (dltShape t) 0
    expect (sh == 6) ("shape[0]: " <> show sh)
    -- strides: null means compact; a non-null [1] is equivalent for 1-D
    strideOk <-
      if dltStrides t == nullPtr
        then pure True
        else (== (1 :: Int64)) <$> peekElemOff (dltStrides t) 0
    expect strideOk "strides neither null nor [1]"
    expect (dltByteOffset t == 0) "byte_offset nonzero"
    mapM (peekElemOff (castPtr (dltData t) :: Ptr Double)) [0 .. 5]
  expect (vals == [0, 1, 2, 3, 4, 5]) ("values: " <> show vals)
  free slot

-- ---------------------------------------------------------------------
-- Direction 2: Haskell -> numpy

exportDirection :: RunScript -> IO ()
exportDirection runScript = do
  cleanupRan <- newIORef False
  buf <- mallocBytes (6 * 8) :: IO (Ptr Double)
  mapM_ (uncurry (pokeElemOff buf)) (zip [0 ..] [1 .. 6])
  mt <-
    newManagedTensor
      (DLDataType kDLFloat 64 1)
      [2, 3]
      (castPtr buf)
      0
      (free buf >> writeIORef cleanupRan True)

  runScript "dlpack-export" $
    "import numpy as np, ctypes, gc\n\
    \ctypes.pythonapi.PyCapsule_New.restype = ctypes.py_object\n\
    \ctypes.pythonapi.PyCapsule_New.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p]\n\
    \class _KeelTensor:\n\
    \    def __init__(self, p):\n\
    \        self._p = p\n\
    \    def __dlpack__(self, max_version=None, dl_device=None, copy=None):\n\
    \        return ctypes.pythonapi.PyCapsule_New(ctypes.c_void_p(self._p), b'dltensor_versioned', None)\n\
    \    def __dlpack_device__(self):\n\
    \        return (1, 0)\n\
    \b = np.from_dlpack(_KeelTensor(" <> addr mt <> "))\n\
    \if b.shape != (2, 3) or b.tolist() != [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]:\n\
    \    raise RuntimeError('dlpack import mismatch: %r' % (b.tolist(),))\n\
    \del b\n\
    \gc.collect()\n"

  done <- readIORef cleanupRan
  expect done "numpy never called our deleter (cleanup did not run)"
