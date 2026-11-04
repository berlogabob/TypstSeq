import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_auth.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/widgets/settings/github_sign_in.dart';

class FakeAuth extends GitHubAuth {
  String? value;
  @override
  Future<String?> token() async => value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<DeviceCodeResponse> requestDeviceCode() async =>
      const DeviceCodeResponse(
        deviceCode: 'device',
        userCode: 'ABCD',
        verificationUri: 'https://example.test',
        expiresIn: 60,
        interval: 1,
      );
  @override
  Future<String> pollForToken(DeviceCodeResponse code) async => value = 'token';
}

class MissingClientAuth extends FakeAuth {
  @override
  Future<DeviceCodeResponse> requestDeviceCode() async =>
      throw const GitHubDeviceFlowError('GITHUB_CLIENT_ID is not configured');
}

class FakeClient extends GitHubClient {
  @override
  Future<Map<String, dynamic>> currentUser() async => {'login': 'octocat'};
}

void main() {
  testWidgets('missing client ID has a helpful message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHubSignIn(
            auth: MissingClientAuth(),
            resolveToken: () async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Sign in with GitHub'));
    await tester.pump();
    expect(
      find.text(
        'Phone sign-in is not set up in this build. Public repos work without signing in.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('device sign in shows code and user, then signs out', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHubSignIn(
            auth: auth,
            resolveToken: () async => null,
            client: (_) => FakeClient(),
            openUrl: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Sign in with GitHub'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('ABCD'), findsOneWidget);
    expect(find.text('GitHub: octocat'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(find.text('Sign in with GitHub'), findsOneWidget);
  });
}
