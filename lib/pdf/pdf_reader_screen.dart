import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../database/tylog_database.dart';
import 'annotation_reattach.dart';
import 'pdf_extraction.dart';
import 'pdf_reader_store.dart';

/// The vault owns the database; leaving the reader never closes it.
class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    super.key,
    required this.bytes,
    required this.path,
    required this.database,
    this.initialSourceVersionId,
    this.initialStartOffset,
    this.initialEndOffset,
  });
  final Uint8List bytes;
  final String path;
  final TyLogDatabase? database;
  final String? initialSourceVersionId;
  final int? initialStartOffset;
  final int? initialEndOffset;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final _controller = PdfViewerController();
  PdfExtraction? _extraction;
  PdfDocument? _document;
  List<AnnotationData> _annotations = [];
  bool _preparing = false;
  bool _saving = false;
  bool _hasSelection = false;
  AnnotationData? _reassigningAnnotation;
  String? _status;

  @override
  void initState() {
    super.initState();
    if (widget.database == null) {
      _status = 'Highlights unavailable for this vault.';
    }
  }

  Future<void> _prepare(PdfDocument document) async {
    if (_preparing || _extraction != null || widget.database == null) return;
    _document = document;
    _preparing = true;
    try {
      final pages = <String?>[];
      for (final page in document.pages) {
        if (!mounted) return;
        // Use the viewer's structured text, so selected UTF-16 ranges agree.
        pages.add((await page.loadStructuredText()).fullText);
      }
      if (!mounted) return;
      final extraction = await persistPdfReaderExtraction(
        database: widget.database!,
        path: widget.path,
        bytes: widget.bytes,
        pageTexts: pages,
      );
      if (!mounted) return;
      _extraction = extraction;
      await _refreshAnnotations();
      if (mounted) {
        setState(() {
          _status = extraction.status == PdfExtractionStatus.unsupported
              ? 'No selectable text. You can still read this PDF.'
              : null;
        });
      }
      await _openInitialCitation(extraction);
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Could not prepare highlights. Reopen this PDF to retry.',
        );
      }
    } finally {
      _preparing = false;
    }
  }

  Future<void> _openInitialCitation(PdfExtraction extraction) async {
    final versionId = widget.initialSourceVersionId;
    final start = widget.initialStartOffset;
    final end = widget.initialEndOffset;
    if (versionId == null || start == null || end == null) return;
    if (versionId != extraction.sourceVersionId) {
      if (mounted) setState(() => _status = 'This citation is out of date.');
      return;
    }
    final range = pdfPageRangeForOffset(extraction, start, end);
    if (range == null || range.end <= range.start) {
      if (mounted) setState(() => _status = 'This citation cannot be opened.');
      return;
    }
    final document = _document;
    if (document == null ||
        range.page < 0 ||
        range.page >= document.pages.length) {
      return;
    }
    try {
      final pageText = await document.pages[range.page].loadStructuredText();
      if (!mounted || range.end > pageText.fullText.length) return;
      await _controller.goToPage(pageNumber: range.page + 1);
      if (!mounted) return;
      await _controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(pageText, range.start),
          PdfTextSelectionPoint(pageText, range.end - 1),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _status = 'This citation cannot be opened.');
    }
  }

  Future<void> _refreshAnnotations() async {
    final db = widget.database!;
    final version = await (db.select(
      db.sourceVersions,
    )..where((row) => row.id.equals(_extraction!.sourceVersionId))).getSingle();
    final versions = await db.sourceVersionsFor(version.sourceId);
    final annotations = <AnnotationData>[];
    for (final item in versions) {
      annotations.addAll(await db.annotationsFor(item.id));
    }
    if (mounted) setState(() => _annotations = annotations);
  }

  Future<void> _saveSelection() async {
    final extraction = _extraction;
    if (extraction == null || _saving) return;
    setState(() => _saving = true);
    try {
      final selection = _controller.textSelectionDelegate;
      if (!selection.isCopyAllowed) return;
      final ranges = await selection.getSelectedTextRanges();
      if (ranges.isEmpty) return;
      final reassigning = _reassigningAnnotation;
      if (reassigning != null) {
        if (ranges.length != 1) {
          throw StateError('Select one replacement range');
        }
        final range = ranges.single;
        await reassignPdfReaderSelection(
          database: widget.database!,
          annotationId: reassigning.id,
          extraction: extraction,
          page: range.pageNumber - 1,
          localStart: range.start,
          localEnd: range.end,
        );
        if (mounted) setState(() => _reassigningAnnotation = null);
      } else {
        await widget.database!.transaction(() async {
          for (final range in ranges) {
            await savePdfReaderSelection(
              database: widget.database!,
              extraction: extraction,
              page: range.pageNumber - 1,
              localStart: range.start,
              localEnd: range.end,
            );
          }
        });
      }
      await _refreshAnnotations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reassigning == null ? 'Highlight saved' : 'Highlight reassigned',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save highlight. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ReattachedAnnotation _target(AnnotationData annotation) {
    final extraction = _extraction!;
    if (annotation.sourceVersionId == extraction.sourceVersionId) {
      return ReattachedAnnotation(
        status: ReattachmentStatus.exact,
        page: annotation.page,
        startOffset: annotation.startOffset,
        endOffset: annotation.endOffset,
      );
    }
    return reattachAnnotation(
      quote: annotation.quote,
      oldStartOffset: annotation.startOffset,
      pages: extraction.pages,
    );
  }

  Future<void> _navigate(ReattachedAnnotation target) async {
    final document = _document;
    final extraction = _extraction;
    if (document == null || extraction == null || target.page == null) return;
    try {
      final page = target.page!;
      if (page < 0 || page >= extraction.pages.length) return;
      final text = await document.pages[page].loadStructuredText();
      if (!mounted) return;
      final start = target.startOffset! - extraction.pages[page].start;
      final end = target.endOffset! - extraction.pages[page].start;
      if (start < 0 || end > text.fullText.length || end <= start) return;
      await _controller.goToPage(pageNumber: page + 1);
      if (!mounted) return;
      await _controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(text, start),
          PdfTextSelectionPoint(text, end - 1),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this highlight.')),
        );
      }
    }
  }

  Future<void> _review(AnnotationData annotation, ReattachedAnnotation target) {
    final message = target.status == ReattachmentStatus.ambiguous
        ? 'This quote appears more than once in the current PDF.'
        : 'This quote is not present in the current PDF.';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Highlight needs review'),
        content: Text(
          '$message\n\n“${annotation.quote}”\n\n${annotation.context}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) {
                setState(() => _reassigningAnnotation = annotation);
              }
            },
            child: const Text('Select replacement'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.path.split('/').last),
      actions: [
        IconButton(
          tooltip: 'Save highlight',
          icon: const Icon(Icons.bookmark_add_outlined),
          onPressed:
              _hasSelection &&
                  _extraction?.status == PdfExtractionStatus.extracted &&
                  !_saving
              ? _saveSelection
              : null,
        ),
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Highlights',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
      ],
    ),
    endDrawer: Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const ListTile(title: Text('Highlights')),
            if (_annotations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Select text, then choose Save highlight.'),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _annotations.length,
                itemBuilder: (context, index) {
                  final annotation = _annotations[index];
                  final target = _target(annotation);
                  final exact = target.status == ReattachmentStatus.exact;
                  return ListTile(
                    title: Text(
                      annotation.quote,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      exact
                          ? 'Page ${target.page! + 1}'
                          : target.status == ReattachmentStatus.ambiguous
                          ? 'Needs review: quote appears more than once'
                          : 'Needs review: quote not found',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (exact) {
                        _navigate(target);
                      } else {
                        _review(annotation, target);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
    body: Column(
      children: [
        if (_status != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_status!)),
        if (_reassigningAnnotation != null)
          MaterialBanner(
            content: const Text(
              'Select replacement text, then save highlight.',
            ),
            actions: [
              TextButton(
                onPressed: () => setState(() => _reassigningAnnotation = null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        Expanded(
          child: PdfViewer.data(
            widget.bytes,
            sourceName: widget.path,
            useProgressiveLoading: false,
            controller: _controller,
            params: PdfViewerParams(
              onViewerReady: (doc, _) => _prepare(doc),
              textSelectionParams: PdfTextSelectionParams(
                onTextSelectionChange: (selection) {
                  if (mounted) {
                    setState(
                      () => _hasSelection =
                          selection.hasSelectedText && selection.isCopyAllowed,
                    );
                  }
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
