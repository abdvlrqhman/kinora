// Deep equality for the value types' field lists (lists, sets, maps).

/// Deep equality of two field values.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Set<Object?> && b is Set<Object?>) {
    return a.length == b.length && a.containsAll(b);
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !deepEquals(e.value, b[e.key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Hash consistent with [deepEquals].
int deepHash(Object? o) => switch (o) {
  final List<Object?> l => Object.hashAll(l.map(deepHash)),
  final Set<Object?> s => Object.hashAllUnordered(s.map(deepHash)),
  final Map<Object?, Object?> m => Object.hashAllUnordered(
    m.entries.map((e) => Object.hash(deepHash(e.key), deepHash(e.value))),
  ),
  _ => o.hashCode,
};
