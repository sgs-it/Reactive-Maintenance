import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmcs/api.dart';
import 'package:rmcs/complaint.dart';
import 'package:rmcs/field_draft.dart';

class MemoryDraft extends FieldDraft {
  MemoryDraft(this.value) : super('test');
  Map? value;
  @override
  Future<Map?> read() async => value;
  @override
  Future<void> save(Map value) async {
    this.value = value;
  }

  @override
  Future<void> remove() async {
    value = null;
  }
}

class RetryApi extends Api {
  final references = <String>[];
  @override
  Future<void> upload(
    String id,
    String stage,
    Uint8List bytes,
    String mime,
    String requestId, {
    bool projectOnly = false,
  }) async {
    references.add(requestId);
    if (references.length == 1) {
      throw const ApiException('Connection interrupted', 0);
    }
  }
}

void main() {
  testWidgets(
    'Photo draft survives interruption and retry uses its original reference',
    (tester) async {
      final draft = MemoryDraft({
        'name': 'field.jpg',
        'bytes': Uint8List.fromList([255, 216, 255]),
        'stage': 'Progress',
        'mime': 'image/jpeg',
        'reference': 'original',
      });
      final api = RetryApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      UploadForm(api: api, id: 'request', draft: draft),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Photo'));
      await tester.pumpAndSettle();
      expect(find.text('Connection interrupted'), findsOneWidget);
      expect(draft.value?['stage'], 'Progress');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Photo'));
      await tester.pumpAndSettle();
      expect(api.references, ['original', 'original']);
      expect(draft.value, isNull);
    },
  );
}
