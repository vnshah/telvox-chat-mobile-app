import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What kind of file a name is, for the colour its page is drawn in, as
/// WhatsApp draws a document: PDF red, Word blue, spreadsheets green, and so
/// on. [icon] stands for it where only an icon fits (the composer's strip).
class FileType {
  const FileType(this.label, this.icon, this.colour);

  /// Read aloud with the icon: "PDF", "Word document"...
  final String label;
  final IconData icon;
  final Color colour;

  static const pdf = FileType(
    'PDF',
    Icons.picture_as_pdf_rounded,
    Color(0xFFE2574C),
  );
  static const word = FileType(
    'Word document',
    Icons.description_rounded,
    Color(0xFF2B5797),
  );
  static const sheet = FileType(
    'Spreadsheet',
    Icons.table_chart_rounded,
    Color(0xFF1F7244),
  );
  static const slides = FileType(
    'Presentation',
    Icons.slideshow_rounded,
    Color(0xFFD24625),
  );
  static const text = FileType(
    'Text file',
    Icons.article_rounded,
    Color(0xFF7E8D98),
  );
  static const archive = FileType(
    'Archive',
    Icons.folder_zip_rounded,
    Color(0xFFE8A317),
  );
  static const image = FileType(
    'Image',
    Icons.image_rounded,
    Color(0xFF8E5BD8),
  );
  static const video = FileType(
    'Video',
    Icons.movie_rounded,
    Color(0xFFE0457B),
  );
  static const audio = FileType(
    'Audio',
    Icons.audio_file_rounded,
    Color(0xFFF09A37),
  );
  static const contact = FileType(
    'Contact card',
    Icons.contact_page_rounded,
    Color(0xFF16958A),
  );
  static const app = FileType(
    'Android app',
    Icons.android_rounded,
    Color(0xFF3DDC84),
  );
  static const file = FileType(
    'File',
    Icons.insert_drive_file_rounded,
    Color(0xFF8696A0),
  );

  /// The file's extension, lower case, or '' when it has none.
  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toLowerCase()
        : '';
  }

  /// The kind as a document's details line names it, after its size:
  /// "Microsoft Word", "PDF"; otherwise the extension in capitals.
  static String nameOf(String name) {
    final ext = extensionOf(name);
    return switch (ext) {
      'doc' || 'docx' => 'Microsoft Word',
      'xls' || 'xlsx' => 'Microsoft Excel',
      'ppt' || 'pptx' => 'Microsoft PowerPoint',
      'txt' => 'Text',
      '' => 'File',
      _ => ext.toUpperCase(),
    };
  }

  /// By the file's name (its extension); an unknown kind is a plain file.
  static FileType of(String name) => switch (extensionOf(name)) {
    'pdf' => pdf,
    'doc' || 'docx' || 'odt' || 'rtf' || 'pages' => word,
    'xls' || 'xlsx' || 'csv' || 'ods' || 'numbers' => sheet,
    'ppt' || 'pptx' || 'odp' || 'key' => slides,
    'txt' || 'md' || 'log' => text,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => archive,
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => image,
    'mp4' || 'mov' || '3gp' || 'mkv' || 'avi' || 'webm' => video,
    'mp3' || 'ogg' || 'opus' || 'm4a' || 'aac' || 'wav' || 'amr' => audio,
    'vcf' => contact,
    'apk' => app,
    _ => file,
  };
}

/// A document's page, as in the chat's own document cards: a page with a
/// folded corner in its kind's colour (Word blue, PDF red, Excel green) and
/// a white mark of what it holds: lines of text, a grid, a slide.
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon(this.name, {super.key, this.size = 40});

  /// The file's name; its extension decides the colour and the mark.
  final String name;

  /// The page's height; it is a little narrower than tall.
  final double size;

  @override
  Widget build(BuildContext context) {
    final type = FileType.of(name);
    return Semantics(
      label: type.label,
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('file-type-icon'),
        width: size * .78,
        height: size,
        child: CustomPaint(painter: _PagePainter(type)),
      ),
    );
  }
}

/// The page, its corner folded down in a lighter shade, and its mark.
class _PagePainter extends CustomPainter {
  const _PagePainter(this.type);
  final FileType type;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fold = w * .34, r = w * .1;
    final page = Path()
      ..moveTo(r, 0)
      ..lineTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
    canvas.drawPath(page, Paint()..color = type.colour);
    canvas.drawPath(
      Path()
        ..moveTo(w - fold, 0)
        ..lineTo(w - fold, fold - r * .6)
        ..quadraticBezierTo(w - fold, fold, w - fold + r * .6, fold)
        ..lineTo(w, fold)
        ..close(),
      Paint()..color = Color.lerp(type.colour, Colors.white, .45)!,
    );

    final ink = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.4, h * .055);
    final left = w * .24, right = w * .76;
    final top = h * .44, bottom = h * .8;
    void lines(int count, {double last = 1}) {
      for (var i = 0; i < count; i++) {
        final y = top + (bottom - top) * i / (count - 1);
        final end = i == count - 1 ? left + (right - left) * last : right;
        canvas.drawLine(Offset(left, y), Offset(end, y), ink);
      }
    }

    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, h * .045);
    final box = Rect.fromLTRB(left, top - h * .03, right, bottom + h * .02);
    if (identical(type, FileType.sheet)) {
      // A grid of cells.
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(h * .02)),
        outline,
      );
      canvas.drawLine(
        Offset(box.left, box.center.dy),
        Offset(box.right, box.center.dy),
        outline,
      );
      canvas.drawLine(
        Offset(box.center.dx, box.top),
        Offset(box.center.dx, box.bottom),
        outline,
      );
    } else if (identical(type, FileType.slides)) {
      // A slide on its stand.
      final slide = Rect.fromLTRB(
        box.left,
        box.top,
        box.right,
        box.bottom - h * .1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(slide, Radius.circular(h * .02)),
        outline,
      );
      canvas.drawLine(
        Offset(slide.center.dx, slide.bottom),
        Offset(slide.center.dx, box.bottom),
        ink,
      );
    } else if (identical(type, FileType.archive)) {
      // A zipper down the middle.
      for (var i = 0; i < 4; i++) {
        final y = top + (bottom - top) * i / 3;
        final x = w * .5 + (i.isEven ? -w * .07 : w * .07);
        canvas.drawLine(Offset(x - w * .06, y), Offset(x + w * .06, y), ink);
      }
    } else if (identical(type, FileType.image)) {
      // Hills under a sun.
      canvas.drawCircle(Offset(w * .62, top + h * .02), h * .055, ink);
      canvas.drawPath(
        Path()
          ..moveTo(left, bottom)
          ..lineTo(w * .42, top + h * .14)
          ..lineTo(w * .58, bottom - h * .1)
          ..lineTo(w * .66, bottom - h * .18)
          ..lineTo(right, bottom)
          ..close(),
        Paint()..color = Colors.white,
      );
    } else if (identical(type, FileType.video) ||
        identical(type, FileType.audio)) {
      // A play mark.
      final c = Offset(w * .5, (top + bottom) / 2), s = h * .15;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * .7, c.dy - s)
          ..lineTo(c.dx + s, c.dy)
          ..lineTo(c.dx - s * .7, c.dy + s)
          ..close(),
        Paint()..color = Colors.white,
      );
    } else {
      // Lines of text: Word, PDF, text and any other file.
      lines(4, last: .6);
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) => !identical(old.type, type);
}
