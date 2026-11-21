import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

void downloadReport(Uint8List bytes, String format, String filename) {
  final mime = format == 'pdf'
      ? 'application/pdf'
      : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  final blob = Blob([bytes.toJS].toJS, BlobPropertyBag(type: mime));
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = filename;
  document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
    const Duration(seconds: 10),
    () => URL.revokeObjectURL(url),
  );
}
