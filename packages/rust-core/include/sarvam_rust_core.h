#ifndef SARVAM_RUST_CORE_H
#define SARVAM_RUST_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

char* sarvam_rust_version(void);
char* sarvam_rust_invoke_json(const char* command_json);

uint8_t* sarvam_rust_alloc(size_t size);
void sarvam_rust_dealloc(uint8_t* ptr, size_t size);

uint8_t* sarvam_rust_invoke_bytes(
    const uint8_t* input_ptr,
    size_t input_len,
    uint64_t* out_meta_u64_pair
);

uint8_t* sarvam_rust_resample_pcm16(
    const uint8_t* input_ptr,
    size_t input_len,
    uint32_t input_sample_rate,
    uint16_t channel_count,
    uint64_t* out_meta_u64_pair
);

void sarvam_rust_free_string(char* ptr);
void sarvam_rust_free_bytes(uint8_t* ptr, size_t len, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* SARVAM_RUST_CORE_H */
