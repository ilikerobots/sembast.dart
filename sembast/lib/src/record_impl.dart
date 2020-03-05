import 'package:sembast/sembast.dart';
import 'package:sembast/src/api/compat/record.dart';
import 'package:sembast/src/api/record_ref.dart';
import 'package:sembast/src/api/record_snapshot.dart';
import 'package:sembast/src/record_ref_impl.dart';
import 'package:sembast/src/record_snapshot_impl.dart';
import 'package:sembast/src/sembast_impl.dart';
import 'package:sembast/src/store_impl.dart';
import 'package:sembast/src/utils.dart';

// ignore_for_file: deprecated_member_use_from_same_package

mixin SembastRecordWithStoreMixin implements Record {
  // Kept for compatibility
  @override
  SembastStore store;
}
mixin SembastRecordHelperMixin implements Record {
  ///
  /// allow cloning a record to start modifying it
  ///
  MutableSembastRecord clone(
          {RecordRef<dynamic, dynamic> ref, dynamic value}) =>
      MutableSembastRecord(ref ?? this.ref, value ?? this.value);

  ///
  /// Copy a record.
  ///
  ImmutableSembastRecord sembastClone(
      {SembastStore store,
      dynamic key,
      RecordRef<dynamic, dynamic> ref,
      dynamic value,
      bool deleted}) {
    return ImmutableSembastRecord(ref ?? this.ref, value ?? this.value,
        deleted: deleted);
  }

  /// Clone as deleted.
  ImmutableSembastRecord sembastCloneAsDeleted() {
    return ImmutableSembastRecord(ref, null, deleted: true);
  }

  Map<String, dynamic> _toBaseMap() {
    var map = <String, dynamic>{};
    map[dbRecordKey] = key;

    if (deleted == true) {
      map[dbRecordDeletedKey] = true;
    }
    if (ref.store != null && ref.store != mainStoreRef) {
      map[dbStoreNameKey] = ref.store.name;
    }
    return map;
  }

  // The actual map written to disk
  Map<String, dynamic> toDatabaseRowMap() {
    var map = _toBaseMap();
    // Don't write the value for deleted
    // ...and for null too anyway...
    if (value != null && !deleted) {
      map[dbRecordValueKey] = value;
    }
    return map;
  }

  @override
  int get hashCode => key == null ? 0 : key.hashCode;

  @override
  bool operator ==(o) {
    if (o is Record) {
      return key == null ? false : (key == o.key);
    }
    return false;
  }
}

/// Used as an interface
abstract class SembastRecordValue<V> {
  /// Raw value/
  V rawValue;
}

mixin SembastRecordMixin implements Record, SembastRecordValue {
  bool _deleted;

  @override
  bool get deleted => _deleted == true;

  set deleted(bool deleted) => _deleted = deleted;

  set value(value) => rawValue = sanitizeValue(value);
}

/// Record that can modified although not cloned right away
class LazyMutableSembastRecord with SembastRecordHelperMixin implements Record {
  // For compatibility
  // Will be remove in 2.0
  @override
  SembastStore store;

  /// Can change overtime if modified
  Record record;

  /// Build a record lazily.
  LazyMutableSembastRecord(this.store, this.record) {
    assert(record != null);
    assert(!(record is LazyMutableSembastRecord));
  }

  @override
  void operator []=(String field, value) {
    // Mutate if needed
    mutableRecord[field] = value;
  }

  /// Mutate only once
  Record get mutableRecord {
    if (record is ImmutableSembastRecord) {
      var immutable = record as ImmutableSembastRecord;
      // Clone it as compatibility SembastRecord
      record = SembastRecord(store, cloneValue(immutable.value), record.key);
    }
    return record;
  }

  @override
  dynamic operator [](String field) {
    var value = record[field];

    if (record is ImmutableSembastRecord) {
      // Need mutation?
      if (isValueMutable(value)) {
        return mutableRecord[field];
      }
    }
    return value;
  }

  @override
  bool get deleted => record.deleted;

  @override
  dynamic get key => record.key;

  /// We allow the target to modify the map so clone it
  @override
  dynamic get value => mutableRecord.value;

  @override
  RecordRef get ref => record.ref;

  @override
  RecordSnapshot<RK, RV> cast<RK, RV>() => record.cast<RK, RV>();
}

/// Immutable record in jdb.
class ImmutableSembastRecordJdb extends ImmutableSembastRecord {
  /// Immutable record in jdb.
  ImmutableSembastRecordJdb(RecordRef ref, dynamic value,
      {bool deleted, int revision})
      : super(ref, value, deleted: deleted) {
    this.revision = revision;
  }
}

/// Immutable record, used in storage
class ImmutableSembastRecord
    with SembastRecordMixin, SembastRecordHelperMixin, RecordSnapshotMixin {
  @override
  void operator []=(String field, value) {
    throw StateError('Record is immutable. Clone to modify it');
  }

  @override
  set value(value) {
    throw StateError('Record is immutable. Clone to modify it');
  }

  @override
  dynamic get value => immutableValue(super.value);

  static var _lastRevision = 0;

  int _makeRevision() {
    return ++_lastRevision;
  }

  /// Record from row map.
  ImmutableSembastRecord.fromDatabaseRowMap(Database db, Map map) {
    final storeName = map[dbStoreNameKey] as String;
    final storeRef = storeName == null
        ? mainStoreRef
        : StoreRef<dynamic, dynamic>(storeName);
    ref = storeRef.record(map[dbRecordKey]);
    super.value = sanitizeValue(map[dbRecordValueKey]);
    _deleted = map[dbRecordDeletedKey] == true;
    revision = _makeRevision();
  }

  ///
  /// Create a record at a given [ref] with a given [value] and
  /// We know data has been sanitized before
  /// an optional [key]
  ///
  ImmutableSembastRecord(RecordRef<dynamic, dynamic> ref, dynamic value,
      {bool deleted}) {
    this.ref = ref;
    super.value = value;
    _deleted = deleted;
    revision = _makeRevision();
  }

  @override
  @deprecated
  SembastStore get store => throw UnsupportedError(
      'Deprecated for immutable record. use ref.store instead');

  @override
  String toString() {
    var map = toDatabaseRowMap();
    if (revision != null) {
      map['revision'] = revision;
    }
    return map.toString();
  }
}

/// Transaction record.
class TxnRecord with SembastRecordHelperMixin implements Record {
  /// Can change overtime if modified
  ImmutableSembastRecord record;

  /// Transaction record.
  TxnRecord(this.store, this.record);

  @override
  void operator []=(String field, value) =>
      throw UnsupportedError('Not supported for txn records');

  @override
  dynamic operator [](String field) => record[field];

  @override
  bool get deleted => record.deleted;

  @override
  dynamic get key => record.key;

  @override
  SembastStore store;

  @override
  dynamic get value => record.value;

  @override
  RecordRef get ref => record.ref;

  @override
  RecordSnapshot<RK, RV> cast<RK, RV>() => record.cast<RK, RV>();

  /// non deleted record.
  ImmutableSembastRecord get nonDeletedRecord => deleted ? null : record;
}

mixin MutableSembastRecordMixin implements Record {
  set value(dynamic value);

  set ref(RecordRef<dynamic, dynamic> ref);

  ///
  /// set the [value] of the specified [field]
  ///
  void setField(String field, dynamic value) {
    if (field == Field.value) {
      this.value = value;
    } else if (field == Field.key) {
      ref = ref.store.record(value);
    } else {
      if (!(this.value is Map)) {
        this.value = {};
      }
      setMapFieldValue(this.value as Map, field, value);
    }
  }

  @override
  void operator []=(String field, value) => setField(field, value);
}

/// Mutable sembast record.
class MutableSembastRecord
    with
        SembastRecordMixin,
        SembastRecordHelperMixin,
        MutableSembastRecordMixin,
        RecordSnapshotMixin {
  ///
  /// Create a record at a given [ref] with a given [value] and
  /// We know data has been sanitized before
  /// an optional [key]
  ///
  MutableSembastRecord(RecordRef<dynamic, dynamic> ref, dynamic value) {
    this.ref = ref;
    this.value = value;
  }

  @override
  SembastStore get store =>
      throw UnsupportedError('Deprecated. use ref.store instead');
}

/// Sembast record.
class SembastRecord
    with
        SembastRecordMixin,
        SembastRecordHelperMixin,
        SembastRecordWithStoreMixin,
        MutableSembastRecordMixin,
        RecordSnapshotMixin {
  ///
  /// check whether the map specified looks like a record
  ///
  static bool isMapRecord(Map map) {
    var key = map[dbRecordKey];
    return (key != null);
  }

  ///
  /// Create a record in a given [store] with a given [value] and
  /// We know data has been sanitized before
  /// an optional [key]
  ///
  SembastRecord(SembastStore store, dynamic value, [dynamic key]) {
    /// Store kept for compatibility
    this.store = store;
    this.value = value;
    // The key could be null in the compat layer so we don't use
    // store.record that will throw an exception
    ref = SembastRecordRef(store?.ref ?? mainStoreRef, key);
  }
}

/// Convert to immultable if needed
ImmutableSembastRecord makeImmutableRecord(Record record) {
  if (record is ImmutableSembastRecord) {
    return record;
  } else if (record == null) {
    // This can happen when settings boundary
    return null;
  }
  return ImmutableSembastRecord(record.ref, cloneValue(record.value),
      deleted: record.deleted);
}

/// Convert to immutable if needed
ImmutableSembastRecordJdb makeImmutableRecordJdb(Record record) {
  if (record is ImmutableSembastRecordJdb) {
    return record;
  } else if (record == null) {
    // This can happen when settings boundary
    return null;
  }
  // no revision
  return ImmutableSembastRecordJdb(record.ref, cloneValue(record.value),
      deleted: record.deleted);
}

/// Make immutable snapshot.
RecordSnapshot makeImmutableRecordSnapshot(RecordSnapshot record) {
  if (record is ImmutableSembastRecord) {
    return record;
  } else if (record is SembastRecordSnapshot) {
    return record;
  } else if (record == null) {
    // This can happen when settings boundary
    return null;
  }
  return SembastRecordSnapshot(record.ref, cloneValue(record.value));
}

/// Make lazy mutable snapshot.
LazyMutableSembastRecord makeLazyMutableRecord(
    SembastStore store, ImmutableSembastRecord record) {
  if (record == null) {
    return null;
  }
  return LazyMutableSembastRecord(store, record);
}

/// create snapshot list.
List<SembastRecordSnapshot<K, V>> immutableListToSnapshots<K, V>(
    List<ImmutableSembastRecord> records) {
  return records
      .map((immutable) => SembastRecordSnapshot<K, V>.fromRecord(immutable))
      ?.toList(growable: false);
}
