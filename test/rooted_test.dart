import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:outstagram/app/rooted.dart';

void main() {
  GoRouter router(String initial, {void Function()? onDetailBuilt}) => GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/feed', builder: (_, _) => const Scaffold(body: Text('feed'))),
          GoRoute(
            path: '/p/:id',
            builder: (_, s) => Rooted(
              location: s.uri.toString(),
              child: Builder(builder: (_) {
                onDetailBuilt?.call();
                return Scaffold(appBar: AppBar(), body: Text('post ${s.pathParameters['id']}'));
              }),
            ),
          ),
        ],
      );

  testWidgets('a deep-linked page gets the feed underneath: back arrow, back goes to the feed', (tester) async {
    var builds = 0;
    final r = router('/p/42', onDetailBuilt: () => builds++);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    expect(find.text('post 42'), findsOneWidget);
    expect(builds, 1, reason: 'the page is built once, after re-rooting');
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('feed'), findsOneWidget);
  });

  testWidgets('a page pushed from inside the app is left alone', (tester) async {
    final r = router('/feed');
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    r.push('/p/7');
    await tester.pumpAndSettle();
    expect(find.text('post 7'), findsOneWidget);
    expect(r.state.uri.toString(), '/p/7');
    r.pop();
    await tester.pumpAndSettle();
    expect(find.text('feed'), findsOneWidget);
  });
}
