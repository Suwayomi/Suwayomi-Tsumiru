// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#ifndef TSUMIRU_AVIF_H_
#define TSUMIRU_AVIF_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// AVIF bytes to PNG buffer: 0 on success; free with tsumiru_avif_free() (NULL-safe).
int tsumiru_avif_to_png(const uint8_t * input, size_t input_length, uint8_t ** output, size_t * output_length);

void tsumiru_avif_free(uint8_t * output);

#ifdef __cplusplus
}
#endif

#endif  // TSUMIRU_AVIF_H_
