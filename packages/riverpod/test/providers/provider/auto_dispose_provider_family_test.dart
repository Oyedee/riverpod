import 'package:mockito/mockito.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import '../../third_party/fake_async.dart';
import '../../utils.dart';

void main() {
  group('Provider.autoDispose.family', () {
    test('supports cacheTime', () async {
      final onDispose = cacheFamily<int, OnDisposeMock>(
        (key) => OnDisposeMock(),
      );

      await fakeAsync((async) async {
        final container = createContainer();
        final provider = Provider.autoDispose.family<int, int>(
          cacheTime: 5 * 1000,
          (ref, value) {
            ref.onDispose(onDispose(value));
            return value;
          },
        );

        final sub = container.listen<int>(provider(42), (previous, next) {});

        expect(sub.read(), 42);

        verifyZeroInteractions(onDispose(42));

        sub.close();

        async.elapse(const Duration(seconds: 2));
        await container.pump();

        verifyZeroInteractions(onDispose(42));

        async.elapse(const Duration(seconds: 3));
        await container.pump();

        verifyOnly(onDispose(42), onDispose(42)());
      });
    });

    test('specifies `from` & `argument` for related providers', () {
      final provider = Provider.autoDispose.family<int, int>((ref, _) => 0);

      expect(provider(0).from, provider);
      expect(provider(0).argument, 0);
    });

    group('scoping an override overrides all the associated subproviders', () {
      test('when passing the provider itself', () {
        final provider = Provider.autoDispose.family<int, int>((ref, _) => 0);
        final root = createContainer();
        final container = createContainer(parent: root, overrides: [provider]);

        expect(container.read(provider(0)), 0);
        expect(container.getAllProviderElements(), [
          isA<ProviderElementBase>()
              .having((e) => e.origin, 'origin', provider(0))
        ]);
        expect(root.getAllProviderElements(), isEmpty);
      });
    });

    test('can be auto-scoped', () async {
      final dep = Provider((ref) => 0);
      final provider = Provider.family.autoDispose<int, int>(
        (ref, i) => ref.watch(dep) + i,
        dependencies: [dep],
      );
      final root = createContainer();
      final container = createContainer(
        parent: root,
        overrides: [dep.overrideWithValue(42)],
      );

      expect(container.read(provider(10)), 52);

      expect(root.getAllProviderElements(), isEmpty);
    });

    test('works', () async {
      final onDispose = OnDisposeMock();
      final provider = Provider.autoDispose.family<String, int>((ref, value) {
        ref.onDispose(onDispose);
        return '$value';
      });
      final listener = Listener<String>();
      final container = createContainer();

      final sub =
          container.listen(provider(0), listener, fireImmediately: true);

      verifyOnly(listener, listener(null, '0'));

      sub.close();

      verifyZeroInteractions(onDispose);

      await container.pump();

      verifyOnly(onDispose, onDispose());
    });

    test('Provider.autoDispose.family override', () async {
      final onDispose = OnDisposeMock();
      final provider = Provider.autoDispose.family<String, int>((ref, value) {
        return '$value';
      });
      final listener = Listener<String>();
      final container = ProviderContainer(
        overrides: [
          provider.overrideWithProvider((value) {
            return Provider.autoDispose<String>((ref) {
              ref.onDispose(onDispose);
              return '$value override';
            });
          })
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        provider(0),
        listener,
        fireImmediately: true,
      );

      verifyOnly(listener, listener(null, '0 override'));

      sub.close();

      verifyZeroInteractions(onDispose);

      await container.pump();

      verifyOnly(onDispose, onDispose());
    });
  });
}
