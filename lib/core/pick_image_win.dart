import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

Future<Uint8List?> pickImage() async {
  if (!Platform.isWindows) return null;
  const maxPath = 4096;
  final nul = String.fromCharCode(0);
  final file = calloc<Uint16>(maxPath).cast<Utf16>();
  final filter = 'Pictures$nul*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp$nul$nul'.toNativeUtf16();
  final dialog = calloc<OPENFILENAME>();
  dialog.ref
    ..lStructSize = sizeOf<OPENFILENAME>()
    ..hwndOwner = GetActiveWindow()
    ..lpstrFilter = filter
    ..lpstrFile = file
    ..nMaxFile = maxPath
    ..Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
  try {
    if (GetOpenFileName(dialog) == 0) return null;
    return await File(file.toDartString()).readAsBytes();
  } finally {
    calloc.free(dialog);
    calloc.free(filter);
    calloc.free(file);
  }
}
