// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "tsumiru_avif.h"

#include <avif/avif.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <glib.h>

#include <cstdint>
#include <cstring>

namespace {

constexpr uint32_t kMaxDimension = 131072;
constexpr uint32_t kMaxPixels = 64u * 1024u * 1024u;
constexpr int kMaxThreads = 2;

enum : int {
  kInvalidInput = 1,
  kDecodeFailed = 2,
  kEncodeFailed = 3,
};

bool ApplyCleanAperture(const avifImage * image, GdkPixbuf ** pixbuf) {
  avifCropRect rect;
  avifDiagnostics diag;
  memset(&diag, 0, sizeof(diag));
#if AVIF_VERSION >= 1020000
  const avifBool ok =
      avifCropRectFromCleanApertureBox(&rect, &image->clap, image->width, image->height, &diag);
#else
  const avifBool ok = avifCropRectConvertCleanApertureBox(&rect, &image->clap, image->width,
                                                          image->height, image->yuvFormat, &diag);
#endif
  if (ok != AVIF_TRUE || rect.width == 0 || rect.height == 0 ||
      static_cast<uint64_t>(rect.x) + rect.width >
          static_cast<uint64_t>(gdk_pixbuf_get_width(*pixbuf)) ||
      static_cast<uint64_t>(rect.y) + rect.height >
          static_cast<uint64_t>(gdk_pixbuf_get_height(*pixbuf))) {
    return false;
  }
  GdkPixbuf * cropped =
      gdk_pixbuf_new_subpixbuf(*pixbuf, static_cast<int>(rect.x), static_cast<int>(rect.y),
                               static_cast<int>(rect.width), static_cast<int>(rect.height));
  if (cropped == nullptr) {
    return false;
  }
  g_object_unref(*pixbuf);
  *pixbuf = cropped;
  return true;
}

int DecodeToPng(const uint8_t * input, size_t input_length, uint8_t ** output,
                size_t * output_length) {
  avifDecoder * decoder = avifDecoderCreate();
  if (decoder == nullptr) {
    return kDecodeFailed;
  }
  decoder->maxThreads = kMaxThreads;
  decoder->imageSizeLimit = kMaxPixels;
  decoder->imageDimensionLimit = kMaxDimension;

  int result = kDecodeFailed;
  avifRGBImage rgb;
  memset(&rgb, 0, sizeof(rgb));
  bool have_rgb = false;
  GdkPixbuf * pixbuf = nullptr;

  do {
    if (avifDecoderSetIOMemory(decoder, input, input_length) != AVIF_RESULT_OK) {
      break;
    }
    if (avifDecoderParse(decoder) != AVIF_RESULT_OK) {
      break;
    }
    if (avifDecoderNextImage(decoder) != AVIF_RESULT_OK) {
      break;
    }
    const avifImage * image = decoder->image;
    if (image == nullptr || image->width == 0 || image->height == 0) {
      break;
    }
    if (image->width > kMaxDimension || image->height > kMaxDimension) {
      break;
    }
    if (static_cast<uint64_t>(image->width) * image->height > kMaxPixels) {
      break;
    }

    avifRGBImageSetDefaults(&rgb, image);
    rgb.format = AVIF_RGB_FORMAT_RGBA;
    rgb.depth = 8;
    rgb.alphaPremultiplied = AVIF_FALSE;
    if (avifRGBImageAllocatePixels(&rgb) != AVIF_RESULT_OK) {
      result = kEncodeFailed;
      break;
    }
    have_rgb = true;
    if (avifImageYUVToRGB(image, &rgb) != AVIF_RESULT_OK) {
      break;
    }

    pixbuf = gdk_pixbuf_new_from_data(rgb.pixels, GDK_COLORSPACE_RGB, TRUE, 8,
                                      static_cast<int>(rgb.width), static_cast<int>(rgb.height),
                                      static_cast<int>(rgb.rowBytes), nullptr, nullptr);
    if (pixbuf == nullptr) {
      result = kEncodeFailed;
      break;
    }
    if ((image->transformFlags & AVIF_TRANSFORM_CLAP) != 0) {
      if (!ApplyCleanAperture(image, &pixbuf)) {
        break;
      }
    }
    if ((image->transformFlags & AVIF_TRANSFORM_IROT) != 0) {
      if (image->irot.angle > 3) {
        break;
      }
      static const GdkPixbufRotation kRotations[] = {
          GDK_PIXBUF_ROTATE_NONE,
          GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE,
          GDK_PIXBUF_ROTATE_UPSIDEDOWN,
          GDK_PIXBUF_ROTATE_CLOCKWISE,
      };
      if (image->irot.angle != 0) {
        GdkPixbuf * rotated = gdk_pixbuf_rotate_simple(pixbuf, kRotations[image->irot.angle]);
        if (rotated == nullptr) {
          result = kEncodeFailed;
          break;
        }
        g_object_unref(pixbuf);
        pixbuf = rotated;
      }
    }
    if ((image->transformFlags & AVIF_TRANSFORM_IMIR) != 0) {
      if (image->imir.axis > 1) {
        break;
      }
      GdkPixbuf * flipped = gdk_pixbuf_flip(pixbuf, image->imir.axis == 1 ? TRUE : FALSE);
      if (flipped == nullptr) {
        result = kEncodeFailed;
        break;
      }
      g_object_unref(pixbuf);
      pixbuf = flipped;
    }

    gchar * png_data = nullptr;
    gsize png_size = 0;
    GError * error = nullptr;
    if (gdk_pixbuf_save_to_buffer(pixbuf, &png_data, &png_size, "png", &error, nullptr) == FALSE ||
        png_data == nullptr || png_size == 0) {
      if (error != nullptr) {
        g_error_free(error);
      }
      g_free(png_data);
      result = kEncodeFailed;
      break;
    }
    *output = reinterpret_cast<uint8_t *>(png_data);
    *output_length = static_cast<size_t>(png_size);
    result = 0;
  } while (false);

  // Subpixbufs share the parent's pixels, so rgb outlives every pixbuf reference.
  if (pixbuf != nullptr) {
    g_object_unref(pixbuf);
  }
  if (have_rgb) {
    avifRGBImageFreePixels(&rgb);
  }
  avifDecoderDestroy(decoder);
  return result;
}

}  // namespace

int tsumiru_avif_to_png(const uint8_t * input, size_t input_length, uint8_t ** output,
                         size_t * output_length) {
  if (output != nullptr) {
    *output = nullptr;
  }
  if (output_length != nullptr) {
    *output_length = 0;
  }
  if (input == nullptr || input_length == 0 || output == nullptr || output_length == nullptr) {
    return kInvalidInput;
  }
  try {
    return DecodeToPng(input, input_length, output, output_length);
  } catch (...) {
    return kDecodeFailed;
  }
}

void tsumiru_avif_free(uint8_t * output) {
  g_free(output);
}
