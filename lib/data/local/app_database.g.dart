// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => UuidV7.generate());
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
      'type', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountCentsMeta =
      const VerificationMeta('amountCents');
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
      'amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
      'date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _familyIdMeta =
      const VerificationMeta('familyId');
  @override
  late final GeneratedColumn<String> familyId = GeneratedColumn<String>(
      'family_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _counterpartyMeta =
      const VerificationMeta('counterparty');
  @override
  late final GeneratedColumn<String> counterparty = GeneratedColumn<String>(
      'counterparty', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tradeNoMeta =
      const VerificationMeta('tradeNo');
  @override
  late final GeneratedColumn<String> tradeNo = GeneratedColumn<String>(
      'trade_no', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _merchantOrderNoMeta =
      const VerificationMeta('merchantOrderNo');
  @override
  late final GeneratedColumn<String> merchantOrderNo = GeneratedColumn<String>(
      'merchant_order_no', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _payMethodMeta =
      const VerificationMeta('payMethod');
  @override
  late final GeneratedColumn<String> payMethod = GeneratedColumn<String>(
      'pay_method', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _platformMeta =
      const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
      'platform', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _deletedMeta =
      const VerificationMeta('deleted');
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
      'deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _syncPendingMeta =
      const VerificationMeta('syncPending');
  @override
  late final GeneratedColumn<bool> syncPending = GeneratedColumn<bool>(
      'sync_pending', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("sync_pending" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        categoryId,
        amountCents,
        date,
        userId,
        familyId,
        description,
        counterparty,
        tradeNo,
        merchantOrderNo,
        payMethod,
        platform,
        version,
        updatedAt,
        deleted,
        syncPending
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(Insertable<Transaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
          _amountCentsMeta,
          amountCents.isAcceptableOrUnknown(
              data['amount_cents']!, _amountCentsMeta));
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('family_id')) {
      context.handle(_familyIdMeta,
          familyId.isAcceptableOrUnknown(data['family_id']!, _familyIdMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('counterparty')) {
      context.handle(
          _counterpartyMeta,
          counterparty.isAcceptableOrUnknown(
              data['counterparty']!, _counterpartyMeta));
    }
    if (data.containsKey('trade_no')) {
      context.handle(_tradeNoMeta,
          tradeNo.isAcceptableOrUnknown(data['trade_no']!, _tradeNoMeta));
    }
    if (data.containsKey('merchant_order_no')) {
      context.handle(
          _merchantOrderNoMeta,
          merchantOrderNo.isAcceptableOrUnknown(
              data['merchant_order_no']!, _merchantOrderNoMeta));
    }
    if (data.containsKey('pay_method')) {
      context.handle(_payMethodMeta,
          payMethod.isAcceptableOrUnknown(data['pay_method']!, _payMethodMeta));
    }
    if (data.containsKey('platform')) {
      context.handle(_platformMeta,
          platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted')) {
      context.handle(_deletedMeta,
          deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta));
    }
    if (data.containsKey('sync_pending')) {
      context.handle(
          _syncPendingMeta,
          syncPending.isAcceptableOrUnknown(
              data['sync_pending']!, _syncPendingMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}type'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id'])!,
      amountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_cents'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}date'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      familyId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}family_id'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      counterparty: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}counterparty']),
      tradeNo: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}trade_no']),
      merchantOrderNo: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}merchant_order_no']),
      payMethod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pay_method']),
      platform: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}platform']),
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}deleted'])!,
      syncPending: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sync_pending'])!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final String id;
  final int type;
  final String categoryId;
  final int amountCents;
  final DateTime date;
  final String userId;
  final String familyId;
  final String? description;
  final String? counterparty;
  final String? tradeNo;
  final String? merchantOrderNo;
  final String? payMethod;
  final String? platform;
  final int version;
  final DateTime updatedAt;
  final bool deleted;
  final bool syncPending;
  const Transaction(
      {required this.id,
      required this.type,
      required this.categoryId,
      required this.amountCents,
      required this.date,
      required this.userId,
      required this.familyId,
      this.description,
      this.counterparty,
      this.tradeNo,
      this.merchantOrderNo,
      this.payMethod,
      this.platform,
      required this.version,
      required this.updatedAt,
      required this.deleted,
      required this.syncPending});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<int>(type);
    map['category_id'] = Variable<String>(categoryId);
    map['amount_cents'] = Variable<int>(amountCents);
    map['date'] = Variable<DateTime>(date);
    map['user_id'] = Variable<String>(userId);
    map['family_id'] = Variable<String>(familyId);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || counterparty != null) {
      map['counterparty'] = Variable<String>(counterparty);
    }
    if (!nullToAbsent || tradeNo != null) {
      map['trade_no'] = Variable<String>(tradeNo);
    }
    if (!nullToAbsent || merchantOrderNo != null) {
      map['merchant_order_no'] = Variable<String>(merchantOrderNo);
    }
    if (!nullToAbsent || payMethod != null) {
      map['pay_method'] = Variable<String>(payMethod);
    }
    if (!nullToAbsent || platform != null) {
      map['platform'] = Variable<String>(platform);
    }
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    map['sync_pending'] = Variable<bool>(syncPending);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      type: Value(type),
      categoryId: Value(categoryId),
      amountCents: Value(amountCents),
      date: Value(date),
      userId: Value(userId),
      familyId: Value(familyId),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      counterparty: counterparty == null && nullToAbsent
          ? const Value.absent()
          : Value(counterparty),
      tradeNo: tradeNo == null && nullToAbsent
          ? const Value.absent()
          : Value(tradeNo),
      merchantOrderNo: merchantOrderNo == null && nullToAbsent
          ? const Value.absent()
          : Value(merchantOrderNo),
      payMethod: payMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(payMethod),
      platform: platform == null && nullToAbsent
          ? const Value.absent()
          : Value(platform),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(syncPending),
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<int>(json['type']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      date: serializer.fromJson<DateTime>(json['date']),
      userId: serializer.fromJson<String>(json['userId']),
      familyId: serializer.fromJson<String>(json['familyId']),
      description: serializer.fromJson<String?>(json['description']),
      counterparty: serializer.fromJson<String?>(json['counterparty']),
      tradeNo: serializer.fromJson<String?>(json['tradeNo']),
      merchantOrderNo: serializer.fromJson<String?>(json['merchantOrderNo']),
      payMethod: serializer.fromJson<String?>(json['payMethod']),
      platform: serializer.fromJson<String?>(json['platform']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      syncPending: serializer.fromJson<bool>(json['syncPending']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<int>(type),
      'categoryId': serializer.toJson<String>(categoryId),
      'amountCents': serializer.toJson<int>(amountCents),
      'date': serializer.toJson<DateTime>(date),
      'userId': serializer.toJson<String>(userId),
      'familyId': serializer.toJson<String>(familyId),
      'description': serializer.toJson<String?>(description),
      'counterparty': serializer.toJson<String?>(counterparty),
      'tradeNo': serializer.toJson<String?>(tradeNo),
      'merchantOrderNo': serializer.toJson<String?>(merchantOrderNo),
      'payMethod': serializer.toJson<String?>(payMethod),
      'platform': serializer.toJson<String?>(platform),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'syncPending': serializer.toJson<bool>(syncPending),
    };
  }

  Transaction copyWith(
          {String? id,
          int? type,
          String? categoryId,
          int? amountCents,
          DateTime? date,
          String? userId,
          String? familyId,
          Value<String?> description = const Value.absent(),
          Value<String?> counterparty = const Value.absent(),
          Value<String?> tradeNo = const Value.absent(),
          Value<String?> merchantOrderNo = const Value.absent(),
          Value<String?> payMethod = const Value.absent(),
          Value<String?> platform = const Value.absent(),
          int? version,
          DateTime? updatedAt,
          bool? deleted,
          bool? syncPending}) =>
      Transaction(
        id: id ?? this.id,
        type: type ?? this.type,
        categoryId: categoryId ?? this.categoryId,
        amountCents: amountCents ?? this.amountCents,
        date: date ?? this.date,
        userId: userId ?? this.userId,
        familyId: familyId ?? this.familyId,
        description: description.present ? description.value : this.description,
        counterparty:
            counterparty.present ? counterparty.value : this.counterparty,
        tradeNo: tradeNo.present ? tradeNo.value : this.tradeNo,
        merchantOrderNo: merchantOrderNo.present
            ? merchantOrderNo.value
            : this.merchantOrderNo,
        payMethod: payMethod.present ? payMethod.value : this.payMethod,
        platform: platform.present ? platform.value : this.platform,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        syncPending: syncPending ?? this.syncPending,
      );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      date: data.date.present ? data.date.value : this.date,
      userId: data.userId.present ? data.userId.value : this.userId,
      familyId: data.familyId.present ? data.familyId.value : this.familyId,
      description:
          data.description.present ? data.description.value : this.description,
      counterparty: data.counterparty.present
          ? data.counterparty.value
          : this.counterparty,
      tradeNo: data.tradeNo.present ? data.tradeNo.value : this.tradeNo,
      merchantOrderNo: data.merchantOrderNo.present
          ? data.merchantOrderNo.value
          : this.merchantOrderNo,
      payMethod: data.payMethod.present ? data.payMethod.value : this.payMethod,
      platform: data.platform.present ? data.platform.value : this.platform,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      syncPending:
          data.syncPending.present ? data.syncPending.value : this.syncPending,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountCents: $amountCents, ')
          ..write('date: $date, ')
          ..write('userId: $userId, ')
          ..write('familyId: $familyId, ')
          ..write('description: $description, ')
          ..write('counterparty: $counterparty, ')
          ..write('tradeNo: $tradeNo, ')
          ..write('merchantOrderNo: $merchantOrderNo, ')
          ..write('payMethod: $payMethod, ')
          ..write('platform: $platform, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      type,
      categoryId,
      amountCents,
      date,
      userId,
      familyId,
      description,
      counterparty,
      tradeNo,
      merchantOrderNo,
      payMethod,
      platform,
      version,
      updatedAt,
      deleted,
      syncPending);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.type == this.type &&
          other.categoryId == this.categoryId &&
          other.amountCents == this.amountCents &&
          other.date == this.date &&
          other.userId == this.userId &&
          other.familyId == this.familyId &&
          other.description == this.description &&
          other.counterparty == this.counterparty &&
          other.tradeNo == this.tradeNo &&
          other.merchantOrderNo == this.merchantOrderNo &&
          other.payMethod == this.payMethod &&
          other.platform == this.platform &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.syncPending == this.syncPending);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<String> id;
  final Value<int> type;
  final Value<String> categoryId;
  final Value<int> amountCents;
  final Value<DateTime> date;
  final Value<String> userId;
  final Value<String> familyId;
  final Value<String?> description;
  final Value<String?> counterparty;
  final Value<String?> tradeNo;
  final Value<String?> merchantOrderNo;
  final Value<String?> payMethod;
  final Value<String?> platform;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> deleted;
  final Value<bool> syncPending;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.date = const Value.absent(),
    this.userId = const Value.absent(),
    this.familyId = const Value.absent(),
    this.description = const Value.absent(),
    this.counterparty = const Value.absent(),
    this.tradeNo = const Value.absent(),
    this.merchantOrderNo = const Value.absent(),
    this.payMethod = const Value.absent(),
    this.platform = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    this.id = const Value.absent(),
    required int type,
    required String categoryId,
    required int amountCents,
    required DateTime date,
    required String userId,
    this.familyId = const Value.absent(),
    this.description = const Value.absent(),
    this.counterparty = const Value.absent(),
    this.tradeNo = const Value.absent(),
    this.merchantOrderNo = const Value.absent(),
    this.payMethod = const Value.absent(),
    this.platform = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : type = Value(type),
        categoryId = Value(categoryId),
        amountCents = Value(amountCents),
        date = Value(date),
        userId = Value(userId);
  static Insertable<Transaction> custom({
    Expression<String>? id,
    Expression<int>? type,
    Expression<String>? categoryId,
    Expression<int>? amountCents,
    Expression<DateTime>? date,
    Expression<String>? userId,
    Expression<String>? familyId,
    Expression<String>? description,
    Expression<String>? counterparty,
    Expression<String>? tradeNo,
    Expression<String>? merchantOrderNo,
    Expression<String>? payMethod,
    Expression<String>? platform,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? deleted,
    Expression<bool>? syncPending,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (categoryId != null) 'category_id': categoryId,
      if (amountCents != null) 'amount_cents': amountCents,
      if (date != null) 'date': date,
      if (userId != null) 'user_id': userId,
      if (familyId != null) 'family_id': familyId,
      if (description != null) 'description': description,
      if (counterparty != null) 'counterparty': counterparty,
      if (tradeNo != null) 'trade_no': tradeNo,
      if (merchantOrderNo != null) 'merchant_order_no': merchantOrderNo,
      if (payMethod != null) 'pay_method': payMethod,
      if (platform != null) 'platform': platform,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (syncPending != null) 'sync_pending': syncPending,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith(
      {Value<String>? id,
      Value<int>? type,
      Value<String>? categoryId,
      Value<int>? amountCents,
      Value<DateTime>? date,
      Value<String>? userId,
      Value<String>? familyId,
      Value<String?>? description,
      Value<String?>? counterparty,
      Value<String?>? tradeNo,
      Value<String?>? merchantOrderNo,
      Value<String?>? payMethod,
      Value<String?>? platform,
      Value<int>? version,
      Value<DateTime>? updatedAt,
      Value<bool>? deleted,
      Value<bool>? syncPending,
      Value<int>? rowid}) {
    return TransactionsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      amountCents: amountCents ?? this.amountCents,
      date: date ?? this.date,
      userId: userId ?? this.userId,
      familyId: familyId ?? this.familyId,
      description: description ?? this.description,
      counterparty: counterparty ?? this.counterparty,
      tradeNo: tradeNo ?? this.tradeNo,
      merchantOrderNo: merchantOrderNo ?? this.merchantOrderNo,
      payMethod: payMethod ?? this.payMethod,
      platform: platform ?? this.platform,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      syncPending: syncPending ?? this.syncPending,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (familyId.present) {
      map['family_id'] = Variable<String>(familyId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (counterparty.present) {
      map['counterparty'] = Variable<String>(counterparty.value);
    }
    if (tradeNo.present) {
      map['trade_no'] = Variable<String>(tradeNo.value);
    }
    if (merchantOrderNo.present) {
      map['merchant_order_no'] = Variable<String>(merchantOrderNo.value);
    }
    if (payMethod.present) {
      map['pay_method'] = Variable<String>(payMethod.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (syncPending.present) {
      map['sync_pending'] = Variable<bool>(syncPending.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountCents: $amountCents, ')
          ..write('date: $date, ')
          ..write('userId: $userId, ')
          ..write('familyId: $familyId, ')
          ..write('description: $description, ')
          ..write('counterparty: $counterparty, ')
          ..write('tradeNo: $tradeNo, ')
          ..write('merchantOrderNo: $merchantOrderNo, ')
          ..write('payMethod: $payMethod, ')
          ..write('platform: $platform, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => UuidV7.generate());
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
      'icon', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
      'type', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _isBuiltinMeta =
      const VerificationMeta('isBuiltin');
  @override
  late final GeneratedColumn<bool> isBuiltin = GeneratedColumn<bool>(
      'is_builtin', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_builtin" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _familyIdMeta =
      const VerificationMeta('familyId');
  @override
  late final GeneratedColumn<String> familyId = GeneratedColumn<String>(
      'family_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _deletedMeta =
      const VerificationMeta('deleted');
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
      'deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _syncPendingMeta =
      const VerificationMeta('syncPending');
  @override
  late final GeneratedColumn<bool> syncPending = GeneratedColumn<bool>(
      'sync_pending', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("sync_pending" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        icon,
        type,
        isBuiltin,
        sortOrder,
        familyId,
        version,
        updatedAt,
        deleted,
        syncPending
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(Insertable<Category> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
          _iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('is_builtin')) {
      context.handle(_isBuiltinMeta,
          isBuiltin.isAcceptableOrUnknown(data['is_builtin']!, _isBuiltinMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('family_id')) {
      context.handle(_familyIdMeta,
          familyId.isAcceptableOrUnknown(data['family_id']!, _familyIdMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted')) {
      context.handle(_deletedMeta,
          deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta));
    }
    if (data.containsKey('sync_pending')) {
      context.handle(
          _syncPendingMeta,
          syncPending.isAcceptableOrUnknown(
              data['sync_pending']!, _syncPendingMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      icon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}type'])!,
      isBuiltin: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_builtin'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      familyId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}family_id'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}deleted'])!,
      syncPending: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sync_pending'])!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String name;
  final String icon;
  final int type;
  final bool isBuiltin;
  final int sortOrder;
  final String familyId;
  final int version;
  final DateTime updatedAt;
  final bool deleted;
  final bool syncPending;
  const Category(
      {required this.id,
      required this.name,
      required this.icon,
      required this.type,
      required this.isBuiltin,
      required this.sortOrder,
      required this.familyId,
      required this.version,
      required this.updatedAt,
      required this.deleted,
      required this.syncPending});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['type'] = Variable<int>(type);
    map['is_builtin'] = Variable<bool>(isBuiltin);
    map['sort_order'] = Variable<int>(sortOrder);
    map['family_id'] = Variable<String>(familyId);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    map['sync_pending'] = Variable<bool>(syncPending);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      type: Value(type),
      isBuiltin: Value(isBuiltin),
      sortOrder: Value(sortOrder),
      familyId: Value(familyId),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(syncPending),
    );
  }

  factory Category.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      type: serializer.fromJson<int>(json['type']),
      isBuiltin: serializer.fromJson<bool>(json['isBuiltin']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      familyId: serializer.fromJson<String>(json['familyId']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      syncPending: serializer.fromJson<bool>(json['syncPending']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'type': serializer.toJson<int>(type),
      'isBuiltin': serializer.toJson<bool>(isBuiltin),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'familyId': serializer.toJson<String>(familyId),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'syncPending': serializer.toJson<bool>(syncPending),
    };
  }

  Category copyWith(
          {String? id,
          String? name,
          String? icon,
          int? type,
          bool? isBuiltin,
          int? sortOrder,
          String? familyId,
          int? version,
          DateTime? updatedAt,
          bool? deleted,
          bool? syncPending}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        type: type ?? this.type,
        isBuiltin: isBuiltin ?? this.isBuiltin,
        sortOrder: sortOrder ?? this.sortOrder,
        familyId: familyId ?? this.familyId,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        syncPending: syncPending ?? this.syncPending,
      );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      type: data.type.present ? data.type.value : this.type,
      isBuiltin: data.isBuiltin.present ? data.isBuiltin.value : this.isBuiltin,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      familyId: data.familyId.present ? data.familyId.value : this.familyId,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      syncPending:
          data.syncPending.present ? data.syncPending.value : this.syncPending,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('type: $type, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('familyId: $familyId, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, icon, type, isBuiltin, sortOrder,
      familyId, version, updatedAt, deleted, syncPending);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.type == this.type &&
          other.isBuiltin == this.isBuiltin &&
          other.sortOrder == this.sortOrder &&
          other.familyId == this.familyId &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.syncPending == this.syncPending);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<int> type;
  final Value<bool> isBuiltin;
  final Value<int> sortOrder;
  final Value<String> familyId;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> deleted;
  final Value<bool> syncPending;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.type = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.familyId = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String icon,
    required int type,
    this.isBuiltin = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.familyId = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : name = Value(name),
        icon = Value(icon),
        type = Value(type);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<int>? type,
    Expression<bool>? isBuiltin,
    Expression<int>? sortOrder,
    Expression<String>? familyId,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? deleted,
    Expression<bool>? syncPending,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (type != null) 'type': type,
      if (isBuiltin != null) 'is_builtin': isBuiltin,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (familyId != null) 'family_id': familyId,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (syncPending != null) 'sync_pending': syncPending,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? icon,
      Value<int>? type,
      Value<bool>? isBuiltin,
      Value<int>? sortOrder,
      Value<String>? familyId,
      Value<int>? version,
      Value<DateTime>? updatedAt,
      Value<bool>? deleted,
      Value<bool>? syncPending,
      Value<int>? rowid}) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      sortOrder: sortOrder ?? this.sortOrder,
      familyId: familyId ?? this.familyId,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      syncPending: syncPending ?? this.syncPending,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (isBuiltin.present) {
      map['is_builtin'] = Variable<bool>(isBuiltin.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (familyId.present) {
      map['family_id'] = Variable<String>(familyId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (syncPending.present) {
      map['sync_pending'] = Variable<bool>(syncPending.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('type: $type, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('familyId: $familyId, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTable extends Budgets with TableInfo<$BudgetsTable, Budget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => UuidV7.generate());
  static const VerificationMeta _familyIdMeta =
      const VerificationMeta('familyId');
  @override
  late final GeneratedColumn<String> familyId = GeneratedColumn<String>(
      'family_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<int> month = GeneratedColumn<int>(
      'month', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _amountCentsMeta =
      const VerificationMeta('amountCents');
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
      'amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _deletedMeta =
      const VerificationMeta('deleted');
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
      'deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _syncPendingMeta =
      const VerificationMeta('syncPending');
  @override
  late final GeneratedColumn<bool> syncPending = GeneratedColumn<bool>(
      'sync_pending', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("sync_pending" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        familyId,
        year,
        month,
        amountCents,
        version,
        updatedAt,
        deleted,
        syncPending
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  VerificationContext validateIntegrity(Insertable<Budget> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('family_id')) {
      context.handle(_familyIdMeta,
          familyId.isAcceptableOrUnknown(data['family_id']!, _familyIdMeta));
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('month')) {
      context.handle(
          _monthMeta, month.isAcceptableOrUnknown(data['month']!, _monthMeta));
    } else if (isInserting) {
      context.missing(_monthMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
          _amountCentsMeta,
          amountCents.isAcceptableOrUnknown(
              data['amount_cents']!, _amountCentsMeta));
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted')) {
      context.handle(_deletedMeta,
          deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta));
    }
    if (data.containsKey('sync_pending')) {
      context.handle(
          _syncPendingMeta,
          syncPending.isAcceptableOrUnknown(
              data['sync_pending']!, _syncPendingMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Budget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Budget(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      familyId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}family_id'])!,
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year'])!,
      month: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}month'])!,
      amountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_cents'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}deleted'])!,
      syncPending: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sync_pending'])!,
    );
  }

  @override
  $BudgetsTable createAlias(String alias) {
    return $BudgetsTable(attachedDatabase, alias);
  }
}

class Budget extends DataClass implements Insertable<Budget> {
  final String id;
  final String familyId;
  final int year;
  final int month;
  final int amountCents;
  final int version;
  final DateTime updatedAt;
  final bool deleted;
  final bool syncPending;
  const Budget(
      {required this.id,
      required this.familyId,
      required this.year,
      required this.month,
      required this.amountCents,
      required this.version,
      required this.updatedAt,
      required this.deleted,
      required this.syncPending});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['family_id'] = Variable<String>(familyId);
    map['year'] = Variable<int>(year);
    map['month'] = Variable<int>(month);
    map['amount_cents'] = Variable<int>(amountCents);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    map['sync_pending'] = Variable<bool>(syncPending);
    return map;
  }

  BudgetsCompanion toCompanion(bool nullToAbsent) {
    return BudgetsCompanion(
      id: Value(id),
      familyId: Value(familyId),
      year: Value(year),
      month: Value(month),
      amountCents: Value(amountCents),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(syncPending),
    );
  }

  factory Budget.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Budget(
      id: serializer.fromJson<String>(json['id']),
      familyId: serializer.fromJson<String>(json['familyId']),
      year: serializer.fromJson<int>(json['year']),
      month: serializer.fromJson<int>(json['month']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      syncPending: serializer.fromJson<bool>(json['syncPending']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'familyId': serializer.toJson<String>(familyId),
      'year': serializer.toJson<int>(year),
      'month': serializer.toJson<int>(month),
      'amountCents': serializer.toJson<int>(amountCents),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'syncPending': serializer.toJson<bool>(syncPending),
    };
  }

  Budget copyWith(
          {String? id,
          String? familyId,
          int? year,
          int? month,
          int? amountCents,
          int? version,
          DateTime? updatedAt,
          bool? deleted,
          bool? syncPending}) =>
      Budget(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        year: year ?? this.year,
        month: month ?? this.month,
        amountCents: amountCents ?? this.amountCents,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        syncPending: syncPending ?? this.syncPending,
      );
  Budget copyWithCompanion(BudgetsCompanion data) {
    return Budget(
      id: data.id.present ? data.id.value : this.id,
      familyId: data.familyId.present ? data.familyId.value : this.familyId,
      year: data.year.present ? data.year.value : this.year,
      month: data.month.present ? data.month.value : this.month,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      syncPending:
          data.syncPending.present ? data.syncPending.value : this.syncPending,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Budget(')
          ..write('id: $id, ')
          ..write('familyId: $familyId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('amountCents: $amountCents, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, familyId, year, month, amountCents,
      version, updatedAt, deleted, syncPending);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Budget &&
          other.id == this.id &&
          other.familyId == this.familyId &&
          other.year == this.year &&
          other.month == this.month &&
          other.amountCents == this.amountCents &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.syncPending == this.syncPending);
}

class BudgetsCompanion extends UpdateCompanion<Budget> {
  final Value<String> id;
  final Value<String> familyId;
  final Value<int> year;
  final Value<int> month;
  final Value<int> amountCents;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> deleted;
  final Value<bool> syncPending;
  final Value<int> rowid;
  const BudgetsCompanion({
    this.id = const Value.absent(),
    this.familyId = const Value.absent(),
    this.year = const Value.absent(),
    this.month = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetsCompanion.insert({
    this.id = const Value.absent(),
    this.familyId = const Value.absent(),
    required int year,
    required int month,
    required int amountCents,
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : year = Value(year),
        month = Value(month),
        amountCents = Value(amountCents);
  static Insertable<Budget> custom({
    Expression<String>? id,
    Expression<String>? familyId,
    Expression<int>? year,
    Expression<int>? month,
    Expression<int>? amountCents,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? deleted,
    Expression<bool>? syncPending,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (familyId != null) 'family_id': familyId,
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (amountCents != null) 'amount_cents': amountCents,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (syncPending != null) 'sync_pending': syncPending,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetsCompanion copyWith(
      {Value<String>? id,
      Value<String>? familyId,
      Value<int>? year,
      Value<int>? month,
      Value<int>? amountCents,
      Value<int>? version,
      Value<DateTime>? updatedAt,
      Value<bool>? deleted,
      Value<bool>? syncPending,
      Value<int>? rowid}) {
    return BudgetsCompanion(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      year: year ?? this.year,
      month: month ?? this.month,
      amountCents: amountCents ?? this.amountCents,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      syncPending: syncPending ?? this.syncPending,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (familyId.present) {
      map['family_id'] = Variable<String>(familyId.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (month.present) {
      map['month'] = Variable<int>(month.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (syncPending.present) {
      map['sync_pending'] = Variable<bool>(syncPending.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsCompanion(')
          ..write('id: $id, ')
          ..write('familyId: $familyId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('amountCents: $amountCents, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoryRulesTable extends CategoryRules
    with TableInfo<$CategoryRulesTable, CategoryRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoryRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => UuidV7.generate());
  static const VerificationMeta _matchTextMeta =
      const VerificationMeta('matchText');
  @override
  late final GeneratedColumn<String> matchText = GeneratedColumn<String>(
      'match_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<int> source = GeneratedColumn<int>(
      'source', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _hitCountMeta =
      const VerificationMeta('hitCount');
  @override
  late final GeneratedColumn<int> hitCount = GeneratedColumn<int>(
      'hit_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _deletedMeta =
      const VerificationMeta('deleted');
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
      'deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _syncPendingMeta =
      const VerificationMeta('syncPending');
  @override
  late final GeneratedColumn<bool> syncPending = GeneratedColumn<bool>(
      'sync_pending', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("sync_pending" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        matchText,
        categoryId,
        source,
        hitCount,
        version,
        updatedAt,
        deleted,
        syncPending
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_rules';
  @override
  VerificationContext validateIntegrity(Insertable<CategoryRule> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('match_text')) {
      context.handle(_matchTextMeta,
          matchText.isAcceptableOrUnknown(data['match_text']!, _matchTextMeta));
    } else if (isInserting) {
      context.missing(_matchTextMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('hit_count')) {
      context.handle(_hitCountMeta,
          hitCount.isAcceptableOrUnknown(data['hit_count']!, _hitCountMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted')) {
      context.handle(_deletedMeta,
          deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta));
    }
    if (data.containsKey('sync_pending')) {
      context.handle(
          _syncPendingMeta,
          syncPending.isAcceptableOrUnknown(
              data['sync_pending']!, _syncPendingMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRule(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      matchText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}match_text'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}source'])!,
      hitCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}hit_count'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}deleted'])!,
      syncPending: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sync_pending'])!,
    );
  }

  @override
  $CategoryRulesTable createAlias(String alias) {
    return $CategoryRulesTable(attachedDatabase, alias);
  }
}

class CategoryRule extends DataClass implements Insertable<CategoryRule> {
  final String id;
  final String matchText;
  final String categoryId;
  final int source;
  final int hitCount;
  final int version;
  final DateTime updatedAt;
  final bool deleted;
  final bool syncPending;
  const CategoryRule(
      {required this.id,
      required this.matchText,
      required this.categoryId,
      required this.source,
      required this.hitCount,
      required this.version,
      required this.updatedAt,
      required this.deleted,
      required this.syncPending});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['match_text'] = Variable<String>(matchText);
    map['category_id'] = Variable<String>(categoryId);
    map['source'] = Variable<int>(source);
    map['hit_count'] = Variable<int>(hitCount);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    map['sync_pending'] = Variable<bool>(syncPending);
    return map;
  }

  CategoryRulesCompanion toCompanion(bool nullToAbsent) {
    return CategoryRulesCompanion(
      id: Value(id),
      matchText: Value(matchText),
      categoryId: Value(categoryId),
      source: Value(source),
      hitCount: Value(hitCount),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(syncPending),
    );
  }

  factory CategoryRule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRule(
      id: serializer.fromJson<String>(json['id']),
      matchText: serializer.fromJson<String>(json['matchText']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      source: serializer.fromJson<int>(json['source']),
      hitCount: serializer.fromJson<int>(json['hitCount']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      syncPending: serializer.fromJson<bool>(json['syncPending']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'matchText': serializer.toJson<String>(matchText),
      'categoryId': serializer.toJson<String>(categoryId),
      'source': serializer.toJson<int>(source),
      'hitCount': serializer.toJson<int>(hitCount),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'syncPending': serializer.toJson<bool>(syncPending),
    };
  }

  CategoryRule copyWith(
          {String? id,
          String? matchText,
          String? categoryId,
          int? source,
          int? hitCount,
          int? version,
          DateTime? updatedAt,
          bool? deleted,
          bool? syncPending}) =>
      CategoryRule(
        id: id ?? this.id,
        matchText: matchText ?? this.matchText,
        categoryId: categoryId ?? this.categoryId,
        source: source ?? this.source,
        hitCount: hitCount ?? this.hitCount,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        syncPending: syncPending ?? this.syncPending,
      );
  CategoryRule copyWithCompanion(CategoryRulesCompanion data) {
    return CategoryRule(
      id: data.id.present ? data.id.value : this.id,
      matchText: data.matchText.present ? data.matchText.value : this.matchText,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      source: data.source.present ? data.source.value : this.source,
      hitCount: data.hitCount.present ? data.hitCount.value : this.hitCount,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      syncPending:
          data.syncPending.present ? data.syncPending.value : this.syncPending,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRule(')
          ..write('id: $id, ')
          ..write('matchText: $matchText, ')
          ..write('categoryId: $categoryId, ')
          ..write('source: $source, ')
          ..write('hitCount: $hitCount, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, matchText, categoryId, source, hitCount,
      version, updatedAt, deleted, syncPending);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRule &&
          other.id == this.id &&
          other.matchText == this.matchText &&
          other.categoryId == this.categoryId &&
          other.source == this.source &&
          other.hitCount == this.hitCount &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.syncPending == this.syncPending);
}

class CategoryRulesCompanion extends UpdateCompanion<CategoryRule> {
  final Value<String> id;
  final Value<String> matchText;
  final Value<String> categoryId;
  final Value<int> source;
  final Value<int> hitCount;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> deleted;
  final Value<bool> syncPending;
  final Value<int> rowid;
  const CategoryRulesCompanion({
    this.id = const Value.absent(),
    this.matchText = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.source = const Value.absent(),
    this.hitCount = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoryRulesCompanion.insert({
    this.id = const Value.absent(),
    required String matchText,
    required String categoryId,
    required int source,
    this.hitCount = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncPending = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : matchText = Value(matchText),
        categoryId = Value(categoryId),
        source = Value(source);
  static Insertable<CategoryRule> custom({
    Expression<String>? id,
    Expression<String>? matchText,
    Expression<String>? categoryId,
    Expression<int>? source,
    Expression<int>? hitCount,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? deleted,
    Expression<bool>? syncPending,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (matchText != null) 'match_text': matchText,
      if (categoryId != null) 'category_id': categoryId,
      if (source != null) 'source': source,
      if (hitCount != null) 'hit_count': hitCount,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (syncPending != null) 'sync_pending': syncPending,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoryRulesCompanion copyWith(
      {Value<String>? id,
      Value<String>? matchText,
      Value<String>? categoryId,
      Value<int>? source,
      Value<int>? hitCount,
      Value<int>? version,
      Value<DateTime>? updatedAt,
      Value<bool>? deleted,
      Value<bool>? syncPending,
      Value<int>? rowid}) {
    return CategoryRulesCompanion(
      id: id ?? this.id,
      matchText: matchText ?? this.matchText,
      categoryId: categoryId ?? this.categoryId,
      source: source ?? this.source,
      hitCount: hitCount ?? this.hitCount,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      syncPending: syncPending ?? this.syncPending,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (matchText.present) {
      map['match_text'] = Variable<String>(matchText.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (source.present) {
      map['source'] = Variable<int>(source.value);
    }
    if (hitCount.present) {
      map['hit_count'] = Variable<int>(hitCount.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (syncPending.present) {
      map['sync_pending'] = Variable<bool>(syncPending.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRulesCompanion(')
          ..write('id: $id, ')
          ..write('matchText: $matchText, ')
          ..write('categoryId: $categoryId, ')
          ..write('source: $source, ')
          ..write('hitCount: $hitCount, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('syncPending: $syncPending, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $BudgetsTable budgets = $BudgetsTable(this);
  late final $CategoryRulesTable categoryRules = $CategoryRulesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [transactions, categories, budgets, categoryRules];
}

typedef $$TransactionsTableCreateCompanionBuilder = TransactionsCompanion
    Function({
  Value<String> id,
  required int type,
  required String categoryId,
  required int amountCents,
  required DateTime date,
  required String userId,
  Value<String> familyId,
  Value<String?> description,
  Value<String?> counterparty,
  Value<String?> tradeNo,
  Value<String?> merchantOrderNo,
  Value<String?> payMethod,
  Value<String?> platform,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});
typedef $$TransactionsTableUpdateCompanionBuilder = TransactionsCompanion
    Function({
  Value<String> id,
  Value<int> type,
  Value<String> categoryId,
  Value<int> amountCents,
  Value<DateTime> date,
  Value<String> userId,
  Value<String> familyId,
  Value<String?> description,
  Value<String?> counterparty,
  Value<String?> tradeNo,
  Value<String?> merchantOrderNo,
  Value<String?> payMethod,
  Value<String?> platform,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amountCents => $composableBuilder(
      column: $table.amountCents, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get familyId => $composableBuilder(
      column: $table.familyId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get counterparty => $composableBuilder(
      column: $table.counterparty, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tradeNo => $composableBuilder(
      column: $table.tradeNo, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get merchantOrderNo => $composableBuilder(
      column: $table.merchantOrderNo,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payMethod => $composableBuilder(
      column: $table.payMethod, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get platform => $composableBuilder(
      column: $table.platform, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnFilters(column));
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amountCents => $composableBuilder(
      column: $table.amountCents, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get familyId => $composableBuilder(
      column: $table.familyId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get counterparty => $composableBuilder(
      column: $table.counterparty,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tradeNo => $composableBuilder(
      column: $table.tradeNo, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get merchantOrderNo => $composableBuilder(
      column: $table.merchantOrderNo,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payMethod => $composableBuilder(
      column: $table.payMethod, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get platform => $composableBuilder(
      column: $table.platform, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnOrderings(column));
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
      column: $table.amountCents, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get familyId =>
      $composableBuilder(column: $table.familyId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get counterparty => $composableBuilder(
      column: $table.counterparty, builder: (column) => column);

  GeneratedColumn<String> get tradeNo =>
      $composableBuilder(column: $table.tradeNo, builder: (column) => column);

  GeneratedColumn<String> get merchantOrderNo => $composableBuilder(
      column: $table.merchantOrderNo, builder: (column) => column);

  GeneratedColumn<String> get payMethod =>
      $composableBuilder(column: $table.payMethod, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => column);
}

class $$TransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableAnnotationComposer,
    $$TransactionsTableCreateCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder,
    (
      Transaction,
      BaseReferences<_$AppDatabase, $TransactionsTable, Transaction>
    ),
    Transaction,
    PrefetchHooks Function()> {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<int> type = const Value.absent(),
            Value<String> categoryId = const Value.absent(),
            Value<int> amountCents = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> familyId = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> counterparty = const Value.absent(),
            Value<String?> tradeNo = const Value.absent(),
            Value<String?> merchantOrderNo = const Value.absent(),
            Value<String?> payMethod = const Value.absent(),
            Value<String?> platform = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionsCompanion(
            id: id,
            type: type,
            categoryId: categoryId,
            amountCents: amountCents,
            date: date,
            userId: userId,
            familyId: familyId,
            description: description,
            counterparty: counterparty,
            tradeNo: tradeNo,
            merchantOrderNo: merchantOrderNo,
            payMethod: payMethod,
            platform: platform,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            Value<String> id = const Value.absent(),
            required int type,
            required String categoryId,
            required int amountCents,
            required DateTime date,
            required String userId,
            Value<String> familyId = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> counterparty = const Value.absent(),
            Value<String?> tradeNo = const Value.absent(),
            Value<String?> merchantOrderNo = const Value.absent(),
            Value<String?> payMethod = const Value.absent(),
            Value<String?> platform = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionsCompanion.insert(
            id: id,
            type: type,
            categoryId: categoryId,
            amountCents: amountCents,
            date: date,
            userId: userId,
            familyId: familyId,
            description: description,
            counterparty: counterparty,
            tradeNo: tradeNo,
            merchantOrderNo: merchantOrderNo,
            payMethod: payMethod,
            platform: platform,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TransactionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableAnnotationComposer,
    $$TransactionsTableCreateCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder,
    (
      Transaction,
      BaseReferences<_$AppDatabase, $TransactionsTable, Transaction>
    ),
    Transaction,
    PrefetchHooks Function()>;
typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  required String name,
  required String icon,
  required int type,
  Value<bool> isBuiltin,
  Value<int> sortOrder,
  Value<String> familyId,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> icon,
  Value<int> type,
  Value<bool> isBuiltin,
  Value<int> sortOrder,
  Value<String> familyId,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBuiltin => $composableBuilder(
      column: $table.isBuiltin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get familyId => $composableBuilder(
      column: $table.familyId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnFilters(column));
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBuiltin => $composableBuilder(
      column: $table.isBuiltin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get familyId => $composableBuilder(
      column: $table.familyId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnOrderings(column));
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltin =>
      $composableBuilder(column: $table.isBuiltin, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get familyId =>
      $composableBuilder(column: $table.familyId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => column);
}

class $$CategoriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()> {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> icon = const Value.absent(),
            Value<int> type = const Value.absent(),
            Value<bool> isBuiltin = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<String> familyId = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoriesCompanion(
            id: id,
            name: name,
            icon: icon,
            type: type,
            isBuiltin: isBuiltin,
            sortOrder: sortOrder,
            familyId: familyId,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            Value<String> id = const Value.absent(),
            required String name,
            required String icon,
            required int type,
            Value<bool> isBuiltin = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<String> familyId = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoriesCompanion.insert(
            id: id,
            name: name,
            icon: icon,
            type: type,
            isBuiltin: isBuiltin,
            sortOrder: sortOrder,
            familyId: familyId,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CategoriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()>;
typedef $$BudgetsTableCreateCompanionBuilder = BudgetsCompanion Function({
  Value<String> id,
  Value<String> familyId,
  required int year,
  required int month,
  required int amountCents,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});
typedef $$BudgetsTableUpdateCompanionBuilder = BudgetsCompanion Function({
  Value<String> id,
  Value<String> familyId,
  Value<int> year,
  Value<int> month,
  Value<int> amountCents,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});

class $$BudgetsTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get familyId => $composableBuilder(
      column: $table.familyId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amountCents => $composableBuilder(
      column: $table.amountCents, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnFilters(column));
}

class $$BudgetsTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get familyId => $composableBuilder(
      column: $table.familyId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amountCents => $composableBuilder(
      column: $table.amountCents, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnOrderings(column));
}

class $$BudgetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get familyId =>
      $composableBuilder(column: $table.familyId, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
      column: $table.amountCents, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => column);
}

class $$BudgetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BudgetsTable,
    Budget,
    $$BudgetsTableFilterComposer,
    $$BudgetsTableOrderingComposer,
    $$BudgetsTableAnnotationComposer,
    $$BudgetsTableCreateCompanionBuilder,
    $$BudgetsTableUpdateCompanionBuilder,
    (Budget, BaseReferences<_$AppDatabase, $BudgetsTable, Budget>),
    Budget,
    PrefetchHooks Function()> {
  $$BudgetsTableTableManager(_$AppDatabase db, $BudgetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> familyId = const Value.absent(),
            Value<int> year = const Value.absent(),
            Value<int> month = const Value.absent(),
            Value<int> amountCents = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BudgetsCompanion(
            id: id,
            familyId: familyId,
            year: year,
            month: month,
            amountCents: amountCents,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> familyId = const Value.absent(),
            required int year,
            required int month,
            required int amountCents,
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BudgetsCompanion.insert(
            id: id,
            familyId: familyId,
            year: year,
            month: month,
            amountCents: amountCents,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BudgetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BudgetsTable,
    Budget,
    $$BudgetsTableFilterComposer,
    $$BudgetsTableOrderingComposer,
    $$BudgetsTableAnnotationComposer,
    $$BudgetsTableCreateCompanionBuilder,
    $$BudgetsTableUpdateCompanionBuilder,
    (Budget, BaseReferences<_$AppDatabase, $BudgetsTable, Budget>),
    Budget,
    PrefetchHooks Function()>;
typedef $$CategoryRulesTableCreateCompanionBuilder = CategoryRulesCompanion
    Function({
  Value<String> id,
  required String matchText,
  required String categoryId,
  required int source,
  Value<int> hitCount,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});
typedef $$CategoryRulesTableUpdateCompanionBuilder = CategoryRulesCompanion
    Function({
  Value<String> id,
  Value<String> matchText,
  Value<String> categoryId,
  Value<int> source,
  Value<int> hitCount,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> deleted,
  Value<bool> syncPending,
  Value<int> rowid,
});

class $$CategoryRulesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoryRulesTable> {
  $$CategoryRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get matchText => $composableBuilder(
      column: $table.matchText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get hitCount => $composableBuilder(
      column: $table.hitCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnFilters(column));
}

class $$CategoryRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoryRulesTable> {
  $$CategoryRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get matchText => $composableBuilder(
      column: $table.matchText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get hitCount => $composableBuilder(
      column: $table.hitCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => ColumnOrderings(column));
}

class $$CategoryRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoryRulesTable> {
  $$CategoryRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get matchText =>
      $composableBuilder(column: $table.matchText, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<int> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get hitCount =>
      $composableBuilder(column: $table.hitCount, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<bool> get syncPending => $composableBuilder(
      column: $table.syncPending, builder: (column) => column);
}

class $$CategoryRulesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CategoryRulesTable,
    CategoryRule,
    $$CategoryRulesTableFilterComposer,
    $$CategoryRulesTableOrderingComposer,
    $$CategoryRulesTableAnnotationComposer,
    $$CategoryRulesTableCreateCompanionBuilder,
    $$CategoryRulesTableUpdateCompanionBuilder,
    (
      CategoryRule,
      BaseReferences<_$AppDatabase, $CategoryRulesTable, CategoryRule>
    ),
    CategoryRule,
    PrefetchHooks Function()> {
  $$CategoryRulesTableTableManager(_$AppDatabase db, $CategoryRulesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoryRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoryRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoryRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> matchText = const Value.absent(),
            Value<String> categoryId = const Value.absent(),
            Value<int> source = const Value.absent(),
            Value<int> hitCount = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoryRulesCompanion(
            id: id,
            matchText: matchText,
            categoryId: categoryId,
            source: source,
            hitCount: hitCount,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            Value<String> id = const Value.absent(),
            required String matchText,
            required String categoryId,
            required int source,
            Value<int> hitCount = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<bool> syncPending = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoryRulesCompanion.insert(
            id: id,
            matchText: matchText,
            categoryId: categoryId,
            source: source,
            hitCount: hitCount,
            version: version,
            updatedAt: updatedAt,
            deleted: deleted,
            syncPending: syncPending,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CategoryRulesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CategoryRulesTable,
    CategoryRule,
    $$CategoryRulesTableFilterComposer,
    $$CategoryRulesTableOrderingComposer,
    $$CategoryRulesTableAnnotationComposer,
    $$CategoryRulesTableCreateCompanionBuilder,
    $$CategoryRulesTableUpdateCompanionBuilder,
    (
      CategoryRule,
      BaseReferences<_$AppDatabase, $CategoryRulesTable, CategoryRule>
    ),
    CategoryRule,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$BudgetsTableTableManager get budgets =>
      $$BudgetsTableTableManager(_db, _db.budgets);
  $$CategoryRulesTableTableManager get categoryRules =>
      $$CategoryRulesTableTableManager(_db, _db.categoryRules);
}
