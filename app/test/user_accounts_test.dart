import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmcs/api.dart';
import 'package:rmcs/user_accounts.dart';

class _AccountsApi extends Api {
  bool canCreate = true;
  Data? submitted;

  @override
  Future<Data> get(String path) async => {
    'can_add_user': true,
    'hosted': true,
    'can_create_credentials': canCreate,
    'users': [],
  };

  @override
  Future<Data> post(String path, Data data) async {
    expect(path, 'accounts');
    submitted = data;
    return {};
  }
}

void main() {
  testWidgets('New hosted sign-ins ask for a password by default', (
    tester,
  ) async {
    final api = _AccountsApi();
    await tester.pumpWidget(MaterialApp(home: UserAccounts(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add User'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Test User');
    await tester.enterText(fields.at(1), 'tester@example.test');
    await tester.enterText(fields.at(2), 'too short');
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(api.submitted, isNull);
    expect(find.textContaining('Use 14'), findsOneWidget);

    await tester.enterText(fields.at(2), 'test-password-123');
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(api.submitted, {
      'name': 'Test User',
      'email': 'tester@example.test',
      'role': 'foreman',
      'password': 'test-password-123',
    });
  });

  testWidgets('Linking an existing account omits the password', (tester) async {
    final api = _AccountsApi()..canCreate = false;
    await tester.pumpWidget(MaterialApp(home: UserAccounts(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add User'));
    await tester.pumpAndSettle();
    expect(find.text('Initial Password'), findsNothing);
    expect(find.text('Link Existing Account'), findsOneWidget);
  });
}
