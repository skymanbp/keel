/* Test-only slot gate for keel-onnx. The shipped library has NO C
 * sources; this file exists so the test suite fails if the hand-pinned
 * OrtApi slot indices in Keel.Onnx.Raw ever disagree with the vendored
 * onnxruntime_c_api.h (v1.24.4, MIT — see the header's own notice).
 * OrtApi members are all function pointers, so slot = offsetof / 8.
 */
#include <stddef.h>
#include "onnxruntime_c_api.h"

_Static_assert(sizeof(void*) == 8, "keel-onnx targets 64-bit platforms only");

int keel_ort_api_version(void) { return ORT_API_VERSION; }

/* Fill `out` with the slot index of each bound member, in exactly the
 * order of Keel.Onnx.Raw.ortSlotTable; return how many were written. */
size_t keel_ort_slot_gate(size_t* out) {
  size_t i = 0;
#define SLOT(m) out[i++] = offsetof(OrtApi, m) / sizeof(void*)
  SLOT(GetErrorCode);
  SLOT(GetErrorMessage);
  SLOT(CreateEnv);
  SLOT(CreateSessionFromArray);
  SLOT(Run);
  SLOT(CreateSessionOptions);
  SLOT(SessionGetInputCount);
  SLOT(SessionGetOutputCount);
  SLOT(SessionGetInputName);
  SLOT(SessionGetOutputName);
  SLOT(CreateTensorWithDataAsOrtValue);
  SLOT(GetTensorMutableData);
  SLOT(GetTensorElementType);
  SLOT(GetDimensionsCount);
  SLOT(GetDimensions);
  SLOT(GetTensorShapeElementCount);
  SLOT(GetTensorTypeAndShape);
  SLOT(CreateCpuMemoryInfo);
  SLOT(AllocatorFree);
  SLOT(GetAllocatorWithDefaultOptions);
  SLOT(ReleaseEnv);
  SLOT(ReleaseStatus);
  SLOT(ReleaseMemoryInfo);
  SLOT(ReleaseSession);
  SLOT(ReleaseValue);
  SLOT(ReleaseTensorTypeAndShapeInfo);
  SLOT(ReleaseSessionOptions);
#undef SLOT
  return i;
}

/* Enum values used by the bindings, same technique. */
size_t keel_ort_enum_gate(long long* out) {
  size_t i = 0;
  out[i++] = ORT_LOGGING_LEVEL_WARNING;
  out[i++] = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
  out[i++] = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
  out[i++] = ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE;
  out[i++] = OrtArenaAllocator;
  out[i++] = OrtMemTypeDefault;
  return i;
}
