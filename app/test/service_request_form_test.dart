import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmcs/api.dart';
import 'package:rmcs/forms.dart';

class _Picker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XK1kAAAAASUVORK5CYII=',
    ),
    name: 'site.png',
    mimeType: 'image/png',
  );
}

class _Api extends Api {
  int creates = 0;
  final firstUpload = Completer<void>();
  final uploads = <String>[];
  @override
  Future<Data> post(String path, Data data) async {
    expect(path, 'complaints');
    expect(data['job_id'], 'p1');
    creates++;
    return {'id': 'r1', 'code': 'RM-1'};
  }

  @override
  Future<void> upload(
    String id,
    String stage,
    Uint8List bytes,
    String mime,
    String requestId, {
    bool projectOnly = false,
  }) async {
    expect(id, 'r1');
    expect(stage, 'Before');
    expect(mime, 'image/png');
    uploads.add(requestId);
    if (uploads.length == 1) {
      await firstUpload.future;
      throw const ApiException('Interrupted', 503);
    }
  }
}

void main() {
  testWidgets(
    'Inline attachment retries the same upload on the saved request',
    (tester) async {
      final previous = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _Picker();
      addTearDown(() => ImagePickerPlatform.instance = previous);
      await tester.binding.setSurfaceSize(const Size(1100, 1250));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _Api();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<Data>(
                  context: context,
                  builder: (_) => EntryForm(
                    api: api,
                    createJob: false,
                    requester: 'Engineer',
                    jobs: const [
                      {
                        'id': 'p1',
                        'code': 'P1',
                        'site': 'Park',
                        'photos_linked': true,
                      },
                    ],
                  ),
                ),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attach Photo'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove Photo'), findsOneWidget);
      for (final label in ['Request Title', 'Description']) {
        await tester.enterText(
          find.widgetWithText(TextFormField, label),
          'Broken pipe',
        );
      }
      await tester.tap(find.text('Select Due Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create and Upload Photo'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Uploading photo…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      api.firstUpload.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('RM-1 was saved'), findsOneWidget);
      await tester.tap(find.text('Retry Photo Upload'));
      await tester.pumpAndSettle();
      expect(api.creates, 1);
      expect(api.uploads.length, 2);
      expect(api.uploads.toSet().length, 1);
      expect(find.text('Open form'), findsOneWidget);
    },
  );
  for (final width in [390.0, 1440.0]) {
    testWidgets('Requester, custom category and photo option at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = Api();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntryForm(
              api: api,
              createJob: false,
              requester: 'Engineer A',
              initialProjectId: 'project-a',
              jobs: const [
                {
                  'id': 'project-b',
                  'code': 'JOB-2',
                  'site': 'South Park',
                  'photos_linked': false,
                },
                {
                  'id': 'project-a',
                  'code': 'JOB-1',
                  'site': 'North Park',
                  'photos_linked': true,
                },
              ],
            ),
          ),
        ),
      );
      final requester = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .singleWhere((field) => field.initialValue == 'Engineer A');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byWidget(requester),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        true,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Attach Photo'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('Irrigation'));
      await tester.tap(find.text('Irrigation'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Other').last);
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Specify Category');
      expect(field.hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.enterText(field, 'Fence repair');
      expect(find.text('Fence repair'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
