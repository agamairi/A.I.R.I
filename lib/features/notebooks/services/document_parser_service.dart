/// Document parser service — extracts text from PDF, plain text, and markdown.
library;

import 'dart:io';

import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentParserService {
  /// Parses a document file and returns its text content.
  Future<String> parse(String filePath, DocumentType type) async {
    switch (type) {
      case DocumentType.txt:
      case DocumentType.markdown:
        return _readTextFile(filePath);

      case DocumentType.pdf:
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final document = PdfDocument(inputBytes: bytes);
        final extractor = PdfTextExtractor(document);
        final text = extractor.extractText();
        document.dispose();
        if (text.trim().isEmpty) {
          throw const FormatException('Parsed PDF document text is empty');
        }
        return text;

      case DocumentType.other:
        // Try to read as plain text
        return _readTextFile(filePath);
    }
  }

  /// Detects document type from file extension.
  static DocumentType detectType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return DocumentType.pdf;
      case 'txt':
        return DocumentType.txt;
      case 'md':
      case 'markdown':
        return DocumentType.markdown;
      default:
        return DocumentType.other;
    }
  }

  /// Chunks text into overlapping segments.
  List<String> chunkText(String text, {int chunkSize = 512, int overlap = 64}) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Must be > 0');
    }
    if (overlap < 0 || overlap >= chunkSize) {
      throw ArgumentError.value(
        overlap,
        'overlap',
        'Must be >= 0 and smaller than chunkSize',
      );
    }

    final normalized = text.trim();
    if (normalized.isEmpty) return [];
    if (normalized.length <= chunkSize) return [normalized];

    final chunks = <String>[];
    final step = chunkSize - overlap;
    int start = 0;
    while (start < normalized.length) {
      final end = (start + chunkSize).clamp(0, normalized.length);
      final chunk = normalized.substring(start, end).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
      if (end == normalized.length) break;
      start += step;
    }
    return chunks;
  }

  Future<String> _readTextFile(
    String filePath, {
    int maxBytes = 20 * 1024 * 1024,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final size = await file.length();
    final bytesToRead = size > maxBytes ? maxBytes : size;
    final bytes = await file.openRead(0, bytesToRead).fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    if (bytes.isEmpty) {
      throw const FormatException('Document is empty');
    }
    final zeroBytes = bytes.where((b) => b == 0).length;
    if (zeroBytes / bytes.length > 0.02) {
      throw const FormatException('Binary documents are not supported');
    }
    final text = String.fromCharCodes(bytes).trim();
    if (text.isEmpty) {
      throw const FormatException('Parsed document text is empty');
    }

    if (size > maxBytes) {
      return '$text\n\n[Truncated at ${maxBytes ~/ (1024 * 1024)}MB]';
    }
    return text;
  }
}
