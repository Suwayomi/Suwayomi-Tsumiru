// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include "tsumiru_avif.h"

#include <avif/avif.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <glib.h>
#include <png.h>

#include <cstdint>
#include <cstdlib>
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

struct PngBuffer {
  uint8_t * data;
  size_t size;
  size_t capacity;
};

void WritePng(png_structp png, png_bytep data, png_size_t length) {
  auto * buffer = static_cast<PngBuffer *>(png_get_io_ptr(png));
  if (length > SIZE_MAX - buffer->size) {
    png_error(png, "PNG output too large");
  }
  const size_t size = buffer->size + length;
  if (size > buffer->capacity) {
    const size_t capacity = size <= SIZE_MAX / 2 ? size * 2 : size;
    auto * resized = static_cast<uint8_t *>(realloc(buffer->data, capacity));
    if (resized == nullptr) {
      png_error(png, "PNG allocation failed");
    }
    buffer->data = resized;
    buffer->capacity = capacity;
  }
  memcpy(buffer->data + buffer->size, data, length);
  buffer->size = size;
}

bool EncodePng(GdkPixbuf * pixbuf, uint8_t ** output, size_t * output_length) {
  png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
  if (png == nullptr) {
    return false;
  }
  png_infop info = png_create_info_struct(png);
  auto * buffer = static_cast<PngBuffer *>(calloc(1, sizeof(PngBuffer)));
  if (info == nullptr || buffer == nullptr) {
    png_destroy_write_struct(&png, &info);
    free(buffer);
    return false;
  }
  // Keep mutable buffer state on the heap so it survives libpng's longjmp.
  if (setjmp(png_jmpbuf(png))) {
    png_destroy_write_struct(&png, &info);
    free(buffer->data);
    free(buffer);
    return false;
  }
  png_set_write_fn(png, buffer, WritePng, nullptr);
  png_set_IHDR(png, info, gdk_pixbuf_get_width(pixbuf), gdk_pixbuf_get_height(pixbuf), 8,
               gdk_pixbuf_get_has_alpha(pixbuf) ? PNG_COLOR_TYPE_RGBA : PNG_COLOR_TYPE_RGB,
               PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
  png_write_info(png, info);
  const uint8_t * pixels = gdk_pixbuf_get_pixels(pixbuf);
  const int stride = gdk_pixbuf_get_rowstride(pixbuf);
  for (int y = 0; y < gdk_pixbuf_get_height(pixbuf); ++y) {
    png_write_row(png, pixels + static_cast<size_t>(y) * stride);
  }
  png_write_end(png, info);
  png_destroy_write_struct(&png, &info);
  *output = buffer->data;
  *output_length = buffer->size;
  free(buffer);
  return true;
}

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

    if (!EncodePng(pixbuf, output, output_length)) {
      result = kEncodeFailed;
      break;
    }
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
  free(output);
}
