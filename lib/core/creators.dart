import 'dart:async';
import 'dart:collection';

import 'api.dart';
import 'models.dart';

/// Creator profiles by key. Posts only carry the creator's id, so feeds look
/// names up here. Lookups are cached for the session and run a few at a
/// time to stay under Pawchive's rate limits.
class CreatorDirectory {
  CreatorDirectory(this._api);

  final PawchiveApi _api;
  final _known = <String, Creator>{};
  final _pending = <String, Completer<Creator?>>{};
  final _queue = Queue<(String service, String id)>();
  int _running = 0;

  static const _parallel = 3;

  Creator? known(String key) => _known[key];

  /// Adds profiles already in hand, such as follows.
  void remember(Iterable<Creator> creators) {
    for (final creator in creators) {
      _known[creator.key] = creator;
    }
  }

  /// The profile, or null when it could not be loaded.
  Future<Creator?> lookup(String service, String id) {
    final key = '$service/$id';
    final hit = _known[key];
    if (hit != null) return Future.value(hit);
    final pending = _pending[key];
    if (pending != null) return pending.future;
    final completer = _pending[key] = Completer<Creator?>();
    _queue.add((service, id));
    _pump();
    return completer.future;
  }

  void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      final (service, id) = _queue.removeFirst();
      _running++;
      unawaited(_load(service, id));
    }
  }

  Future<void> _load(String service, String id) async {
    final key = '$service/$id';
    Creator? creator;
    try {
      creator = await _api.creator(service, id);
      _known[key] = creator;
    } on ApiException {
      creator = null;
    } finally {
      _running--;
      _pending.remove(key)?.complete(creator);
      _pump();
    }
  }
}
