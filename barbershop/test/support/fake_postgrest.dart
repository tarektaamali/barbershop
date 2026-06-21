import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `SupabaseClient.rpc` and the query builders return a `PostgrestFilterBuilder`
/// (a Future-like). This fake makes `await` resolve to a fixed value so RPC and
/// query calls can be stubbed in unit tests.
///
/// Use with `thenAnswer` (not `thenReturn`, which mocktail rejects for Futures):
///   when(() => client.rpc('fn', params: any(named: 'params')))
///       .thenAnswer((_) => FakeFilterBuilder(value));
class FakeFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  FakeFilterBuilder(this._value);

  final T _value;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) =>
      Future<T>.value(_value).then(onValue, onError: onError);
}
