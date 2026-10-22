import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Converts [CameraImage] frames into ML Kit [InputImage]s.
///
/// Android delivers YUV420_888 (three planes with possibly padded rows and
/// sub-sampled chroma), which ML Kit cannot read directly — it wants NV21.
/// iOS delivers BGRA8888 which can be passed straight through.
InputImage? cameraImageToInputImage(
  CameraImage image,
  InputImageRotation rotation,
) {
  final size = Size(image.width.toDouble(), image.height.toDouble());
  final format = image.format.group;

  switch (format) {
    case ImageFormatGroup.yuv420:
      return InputImage.fromBytes(
        bytes: yuv420ToNv21(image),
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.nv21,
          // Converted frames are tightly packed: one row = width bytes.
          bytesPerRow: image.width,
        ),
      );
    case ImageFormatGroup.nv21:
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    case ImageFormatGroup.bgra8888:
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    default:
      return null;
  }
}

/// YUV420_888 → NV21, respecting plane row strides and pixel strides
/// (some devices pad rows, so a naive concat would corrupt frames).
Uint8List yuv420ToNv21(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final uvWidth = width ~/ 2;
  final uvHeight = height ~/ 2;

  final out = Uint8List(width * height + uvWidth * uvHeight * 2);
  var index = 0;

  // Y — copy row by row, stripping any row padding.
  for (var row = 0; row < height; row++) {
    out.setRange(index, index + width, yPlane.bytes, row * yPlane.bytesPerRow);
    index += width;
  }

  // VU interleaved (that's what makes NV21 = "Y + VU").
  for (var row = 0; row < uvHeight; row++) {
    final vRow = row * vPlane.bytesPerRow;
    final uRow = row * uPlane.bytesPerRow;
    for (var col = 0; col < uvWidth; col++) {
      out[index++] = vPlane.bytes[vRow + col * (vPlane.bytesPerPixel ?? 1)];
      out[index++] = uPlane.bytes[uRow + col * (uPlane.bytesPerPixel ?? 1)];
    }
  }

  return out;
}
