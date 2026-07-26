class ReferenceCountedWatchRegistry<T> {
  final Map<T, int> _references = <T, int>{};

  Iterable<T> get activeKeys => _references.keys;
  int get activeKeyCount => _references.length;
  int get activeReferenceCount => _references.values.fold(
        0,
        (total, activeCount) => total + activeCount,
      );
  int referenceCountFor(T key) => _references[key] ?? 0;

  /// Returns true when this is the first watcher for [key].
  bool acquire(T key) {
    final current = _references[key] ?? 0;
    _references[key] = current + 1;
    return current == 0;
  }

  /// Returns true when the final watcher for [key] was released.
  bool release(T key) {
    final current = _references[key];
    if (current == null) return false;
    if (current > 1) {
      _references[key] = current - 1;
      return false;
    }
    _references.remove(key);
    return true;
  }

  void clear() => _references.clear();
}
