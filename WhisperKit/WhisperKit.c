#include "include/WhisperKit.h"
#include "whisper.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

WhisperContextRef whisper_kit_init(const char* model_path) {
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;  // Enable Metal acceleration
    
    struct whisper_context* ctx = whisper_init_from_file_with_params(model_path, cparams);
    if (ctx == NULL) {
        fprintf(stderr, "whisper_kit: failed to load model from %s\n", model_path);
        return NULL;
    }
    
    return (WhisperContextRef)ctx;
}

void whisper_kit_free(WhisperContextRef ctx) {
    if (ctx != NULL) {
        whisper_free((struct whisper_context*)ctx);
    }
}

char* whisper_kit_transcribe(WhisperContextRef ctx, const float* samples, int n_samples) {
    if (ctx == NULL || samples == NULL || n_samples <= 0) {
        return NULL;
    }
    
    struct whisper_context* wctx = (struct whisper_context*)ctx;
    
    // Configure transcription parameters
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress = false;
    params.print_special = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.single_segment = true;
    params.max_tokens = 0;  // No limit
    params.language = "en";
    params.n_threads = 4;
    params.speed_up = false;  // Deprecated in newer versions
    params.suppress_blank = true;
    params.suppress_nst = true;
    
    // Run transcription
    int result = whisper_full(wctx, params, samples, n_samples);
    if (result != 0) {
        fprintf(stderr, "whisper_kit: transcription failed with error %d\n", result);
        return NULL;
    }
    
    // Collect all segments into one string
    int n_segments = whisper_full_n_segments(wctx);
    if (n_segments == 0) {
        // Return empty string
        char* empty = (char*)malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    
    // Calculate total length needed
    size_t total_len = 0;
    for (int i = 0; i < n_segments; i++) {
        const char* text = whisper_full_get_segment_text(wctx, i);
        if (text) {
            total_len += strlen(text);
        }
    }
    
    // Allocate result buffer
    char* result_text = (char*)malloc(total_len + 1);
    if (result_text == NULL) {
        return NULL;
    }
    
    // Concatenate all segments
    result_text[0] = '\0';
    for (int i = 0; i < n_segments; i++) {
        const char* text = whisper_full_get_segment_text(wctx, i);
        if (text) {
            strcat(result_text, text);
        }
    }
    
    return result_text;
}

void whisper_kit_free_string(char* str) {
    if (str != NULL) {
        free(str);
    }
}

bool whisper_kit_metal_available(void) {
#ifdef GGML_USE_METAL
    return true;
#else
    return false;
#endif
}

const char* whisper_kit_version(void) {
    return "1.0.0";
}
