#ifndef WhisperKit_h
#define WhisperKit_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle to whisper context
typedef void* WhisperContextRef;

// Initialize whisper with model file path
// Returns NULL on failure
WhisperContextRef whisper_kit_init(const char* model_path);

// Free whisper context
void whisper_kit_free(WhisperContextRef ctx);

// Transcribe audio samples
// samples: array of float32 audio samples (mono, 16kHz)
// n_samples: number of samples
// Returns transcribed text (caller must free with whisper_kit_free_string)
char* whisper_kit_transcribe(WhisperContextRef ctx, const float* samples, int n_samples);

// Free string returned by whisper_kit_transcribe
void whisper_kit_free_string(char* str);

// Check if Metal acceleration is available
bool whisper_kit_metal_available(void);

// Get whisper library version
const char* whisper_kit_version(void);

#ifdef __cplusplus
}
#endif

#endif /* WhisperKit_h */
