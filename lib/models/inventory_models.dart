/// Immutable domain models for the DreamStore inventory application.
///
/// Monetary values are always represented in integer minor units. Quantities
/// are whole stock units. Keeping both as integers prevents rounding drift in
/// inventory valuation and sales reports.
library;

class InventoryException implements Exception {
  const InventoryException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

enum StockMovementType {
  opening,
  restock,
  sale,
  departmentIssue,
  adjustment,
  reversal,
}

extension StockMovementTypeLabel on StockMovementType {
  String get label => switch (this) {
    StockMovementType.opening => 'Opening stock',
    StockMovementType.restock => 'Restock',
    StockMovementType.sale => 'Sale',
    StockMovementType.departmentIssue => 'Department issue',
    StockMovementType.adjustment => 'Adjustment',
    StockMovementType.reversal => 'Sale reversal',
  };
}

enum RequisitionStatus { requested, approved, issued, received, rejected }

extension RequisitionStatusLabel on RequisitionStatus {
  String get label => switch (this) {
    RequisitionStatus.requested => 'Awaiting approval',
    RequisitionStatus.approved => 'Approved',
    RequisitionStatus.issued => 'Issued',
    RequisitionStatus.received => 'Received',
    RequisitionStatus.rejected => 'Rejected',
  };
}

enum HotelDepartment {
  kitchen,
  housekeeping,
  laundry,
  maintenance,
  reception,
  office,
  publicArea,
  restaurant,
  pool,
  security,
}

extension HotelDepartmentDetails on HotelDepartment {
  String get label => switch (this) {
    HotelDepartment.kitchen => 'Kitchen',
    HotelDepartment.housekeeping => 'Housekeeping',
    HotelDepartment.laundry => 'Laundry',
    HotelDepartment.maintenance => 'Maintenance',
    HotelDepartment.reception => 'Reception',
    HotelDepartment.office => 'Office',
    HotelDepartment.publicArea => 'Public area',
    HotelDepartment.restaurant => 'Restaurant',
    HotelDepartment.pool => 'Pool',
    HotelDepartment.security => 'Security',
  };
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.department,
    this.unit = 'Each',
    required this.description,
    required this.quantity,
    required this.unitCostMinor,
    required this.salePriceMinor,
    required this.lowStockThreshold,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? createdAt;

  final String id;
  final String name;
  final String sku;
  final String category;
  final HotelDepartment department;
  final String unit;
  final String description;
  final int quantity;
  final int unitCostMinor;
  final int salePriceMinor;
  final int lowStockThreshold;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The original stock arrival date, separate from when it was entered.
  final DateTime receivedAt;

  int get inventoryValueMinor => quantity * unitCostMinor;
  int get retailValueMinor => quantity * salePriceMinor;
  int get unitMarginMinor => salePriceMinor - unitCostMinor;
  int get potentialProfitMinor => quantity * unitMarginMinor;
  bool get isOutOfStock => quantity == 0;
  bool get isLowStock => quantity > 0 && quantity <= lowStockThreshold;
  bool get isInStock => quantity > 0;

  // Common terminology aliases keep view code readable.
  int get stockQuantity => quantity;
  int get costPriceMinor => unitCostMinor;
  int get sellingPriceMinor => salePriceMinor;

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? category,
    HotelDepartment? department,
    String? unit,
    String? description,
    int? quantity,
    int? unitCostMinor,
    int? salePriceMinor,
    int? lowStockThreshold,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? receivedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      department: department ?? this.department,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitCostMinor: unitCostMinor ?? this.unitCostMinor,
      salePriceMinor: salePriceMinor ?? this.salePriceMinor,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'sku': sku,
    'category': category,
    'department': department.name,
    'unit': unit,
    'description': description,
    'quantity': quantity,
    'unitCostMinor': unitCostMinor,
    'salePriceMinor': salePriceMinor,
    'lowStockThreshold': lowStockThreshold,
    'isArchived': isArchived,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'receivedAt': receivedAt.toIso8601String(),
  };

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      sku: _requiredString(json, 'sku'),
      category: _stringValue(json['category'], fallback: 'General'),
      department: _departmentValue(json['department'], json['category']),
      unit: _stringValue(json['unit'], fallback: 'Each'),
      description: _stringValue(json['description']),
      quantity: _intValue(json['quantity']),
      unitCostMinor: _intValue(json['unitCostMinor'] ?? json['costPriceMinor']),
      salePriceMinor: _intValue(
        json['salePriceMinor'] ?? json['sellingPriceMinor'],
      ),
      lowStockThreshold: _intValue(json['lowStockThreshold'], fallback: 5),
      isArchived: _boolValue(json['isArchived']),
      createdAt: _dateValue(json['createdAt']),
      updatedAt: _dateValue(json['updatedAt'] ?? json['createdAt']),
      receivedAt: _dateValue(json['receivedAt'] ?? json['createdAt']),
    );
  }
}

class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.sku,
    this.category = 'General',
    this.department = HotelDepartment.kitchen,
    this.unit = 'Each',
    this.description = '',
    this.initialStock = 0,
    this.unitCostMinor = 0,
    this.salePriceMinor = 0,
    this.lowStockThreshold = 5,
    this.receivedAt,
  });

  final String name;
  final String sku;
  final String category;
  final HotelDepartment department;
  final String unit;
  final String description;
  final int initialStock;
  final int unitCostMinor;
  final int salePriceMinor;
  final int lowStockThreshold;
  final DateTime? receivedAt;

  int get costPriceMinor => unitCostMinor;
  int get sellingPriceMinor => salePriceMinor;

  ProductDraft copyWith({
    String? name,
    String? sku,
    String? category,
    HotelDepartment? department,
    String? unit,
    String? description,
    int? initialStock,
    int? unitCostMinor,
    int? salePriceMinor,
    int? lowStockThreshold,
    DateTime? receivedAt,
  }) {
    return ProductDraft(
      name: name ?? this.name,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      department: department ?? this.department,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      initialStock: initialStock ?? this.initialStock,
      unitCostMinor: unitCostMinor ?? this.unitCostMinor,
      salePriceMinor: salePriceMinor ?? this.salePriceMinor,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'sku': sku,
    'category': category,
    'department': department.name,
    'unit': unit,
    'description': description,
    'initialStock': initialStock,
    'unitCostMinor': unitCostMinor,
    'salePriceMinor': salePriceMinor,
    'lowStockThreshold': lowStockThreshold,
    if (receivedAt != null) 'receivedAt': receivedAt!.toIso8601String(),
  };

  factory ProductDraft.fromJson(Map<String, dynamic> json) {
    return ProductDraft(
      name: _requiredString(json, 'name'),
      sku: _requiredString(json, 'sku'),
      category: _stringValue(json['category'], fallback: 'General'),
      department: _departmentValue(json['department'], json['category']),
      unit: _stringValue(json['unit'], fallback: 'Each'),
      description: _stringValue(json['description']),
      initialStock: _intValue(json['initialStock']),
      unitCostMinor: _intValue(json['unitCostMinor'] ?? json['costPriceMinor']),
      salePriceMinor: _intValue(
        json['salePriceMinor'] ?? json['sellingPriceMinor'],
      ),
      lowStockThreshold: _intValue(json['lowStockThreshold'], fallback: 5),
      receivedAt: _nullableDateValue(json['receivedAt']),
    );
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.type,
    required this.quantityDelta,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.unitCostMinor,
    required this.occurredAt,
    DateTime? recordedAt,
    this.department,
    this.relatedSaleId,
    this.note,
    this.supplierName,
    this.invoiceNumber,
    this.expiryDate,
    this.actorName,
  }) : recordedAt = recordedAt ?? occurredAt;

  final String id;
  final String productId;
  final String productName;
  final String productSku;
  final StockMovementType type;

  /// Signed change: stock additions are positive and sales are negative.
  final int quantityDelta;
  final int quantityBefore;
  final int quantityAfter;
  final int unitCostMinor;
  final DateTime occurredAt;

  /// Audit timestamp; [occurredAt] is the actual arrival or usage date.
  final DateTime recordedAt;

  /// Historical department ownership at the time this movement was recorded.
  /// Older backups may not have this snapshot.
  final HotelDepartment? department;
  final String? relatedSaleId;
  final String? note;
  final String? supplierName;
  final String? invoiceNumber;
  final DateTime? expiryDate;
  final String? actorName;

  int get stockValueChangeMinor => quantityDelta * unitCostMinor;
  int get absoluteQuantity => quantityDelta.abs();

  StockMovement copyWith({
    String? id,
    String? productId,
    String? productName,
    String? productSku,
    StockMovementType? type,
    int? quantityDelta,
    int? quantityBefore,
    int? quantityAfter,
    int? unitCostMinor,
    DateTime? occurredAt,
    DateTime? recordedAt,
    HotelDepartment? department,
    String? relatedSaleId,
    String? note,
    String? supplierName,
    String? invoiceNumber,
    DateTime? expiryDate,
    String? actorName,
  }) {
    return StockMovement(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      type: type ?? this.type,
      quantityDelta: quantityDelta ?? this.quantityDelta,
      quantityBefore: quantityBefore ?? this.quantityBefore,
      quantityAfter: quantityAfter ?? this.quantityAfter,
      unitCostMinor: unitCostMinor ?? this.unitCostMinor,
      occurredAt: occurredAt ?? this.occurredAt,
      recordedAt: recordedAt ?? this.recordedAt,
      department: department ?? this.department,
      relatedSaleId: relatedSaleId ?? this.relatedSaleId,
      note: note ?? this.note,
      supplierName: supplierName ?? this.supplierName,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      actorName: actorName ?? this.actorName,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'productId': productId,
    'productName': productName,
    'productSku': productSku,
    'type': type.name,
    'quantityDelta': quantityDelta,
    'quantityBefore': quantityBefore,
    'quantityAfter': quantityAfter,
    'unitCostMinor': unitCostMinor,
    'occurredAt': occurredAt.toIso8601String(),
    'recordedAt': recordedAt.toIso8601String(),
    if (department != null) 'department': department!.name,
    if (relatedSaleId != null) 'relatedSaleId': relatedSaleId,
    if (note != null) 'note': note,
    if (supplierName != null) 'supplierName': supplierName,
    if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
    if (expiryDate != null) 'expiryDate': expiryDate!.toIso8601String(),
    if (actorName != null) 'actorName': actorName,
  };

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: _requiredString(json, 'id'),
      productId: _requiredString(json, 'productId'),
      productName: _stringValue(json['productName'], fallback: 'Product'),
      productSku: _stringValue(json['productSku']),
      type: _movementTypeValue(json['type']),
      quantityDelta: _intValue(json['quantityDelta']),
      quantityBefore: _intValue(json['quantityBefore']),
      quantityAfter: _intValue(json['quantityAfter']),
      unitCostMinor: _intValue(json['unitCostMinor']),
      occurredAt: _dateValue(json['occurredAt']),
      recordedAt: _dateValue(json['recordedAt'] ?? json['occurredAt']),
      department: json['department'] == null
          ? null
          : _departmentValue(json['department']),
      relatedSaleId: _nullableString(json['relatedSaleId']),
      note: _nullableString(json['note']),
      supplierName: _nullableString(json['supplierName']),
      invoiceNumber: _nullableString(json['invoiceNumber']),
      expiryDate: _nullableDateValue(json['expiryDate']),
      actorName: _nullableString(json['actorName']),
    );
  }
}

class RequisitionLine {
  const RequisitionLine({
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.quantity,
    required this.unitCostMinor,
    this.unit = 'Each',
  });

  final String productId;
  final String productName;
  final String productSku;
  final int quantity;
  final int unitCostMinor;
  final String unit;

  int get valueMinor => quantity * unitCostMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'productId': productId,
    'productName': productName,
    'productSku': productSku,
    'quantity': quantity,
    'unitCostMinor': unitCostMinor,
    'unit': unit,
  };

  factory RequisitionLine.fromJson(Map<String, dynamic> json) =>
      RequisitionLine(
        productId: _requiredString(json, 'productId'),
        productName: _requiredString(json, 'productName'),
        productSku: _stringValue(json['productSku']),
        quantity: _intValue(json['quantity']),
        unitCostMinor: _intValue(json['unitCostMinor']),
        unit: _stringValue(json['unit'], fallback: 'Each'),
      );
}

class StoreRequisition {
  StoreRequisition({
    required this.id,
    required this.department,
    required this.requestedBy,
    required this.requestedAt,
    required this.status,
    required List<RequisitionLine> lines,
    this.approvedBy,
    this.approvedAt,
    this.issuedBy,
    this.issuedAt,
    this.receivedBy,
    this.receivedAt,
    this.note,
  }) : lines = List<RequisitionLine>.unmodifiable(lines);

  final String id;
  final HotelDepartment department;
  final String requestedBy;
  final DateTime requestedAt;
  final RequisitionStatus status;
  final List<RequisitionLine> lines;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? issuedBy;
  final DateTime? issuedAt;
  final String? receivedBy;
  final DateTime? receivedAt;
  final String? note;

  int get totalUnits =>
      lines.fold<int>(0, (total, line) => total + line.quantity);
  int get totalValueMinor =>
      lines.fold<int>(0, (total, line) => total + line.valueMinor);

  StoreRequisition copyWith({
    RequisitionStatus? status,
    String? approvedBy,
    DateTime? approvedAt,
    String? issuedBy,
    DateTime? issuedAt,
    String? receivedBy,
    DateTime? receivedAt,
    String? note,
  }) => StoreRequisition(
    id: id,
    department: department,
    requestedBy: requestedBy,
    requestedAt: requestedAt,
    status: status ?? this.status,
    lines: lines,
    approvedBy: approvedBy ?? this.approvedBy,
    approvedAt: approvedAt ?? this.approvedAt,
    issuedBy: issuedBy ?? this.issuedBy,
    issuedAt: issuedAt ?? this.issuedAt,
    receivedBy: receivedBy ?? this.receivedBy,
    receivedAt: receivedAt ?? this.receivedAt,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'department': department.name,
    'requestedBy': requestedBy,
    'requestedAt': requestedAt.toIso8601String(),
    'status': status.name,
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
    if (approvedBy != null) 'approvedBy': approvedBy,
    if (approvedAt != null) 'approvedAt': approvedAt!.toIso8601String(),
    if (issuedBy != null) 'issuedBy': issuedBy,
    if (issuedAt != null) 'issuedAt': issuedAt!.toIso8601String(),
    if (receivedBy != null) 'receivedBy': receivedBy,
    if (receivedAt != null) 'receivedAt': receivedAt!.toIso8601String(),
    if (note != null) 'note': note,
  };

  factory StoreRequisition.fromJson(Map<String, dynamic> json) =>
      StoreRequisition(
        id: _requiredString(json, 'id'),
        department: _departmentValue(json['department']),
        requestedBy: _requiredString(json, 'requestedBy'),
        requestedAt: _dateValue(json['requestedAt']),
        status: RequisitionStatus.values.firstWhere(
          (status) => status.name == json['status'],
          orElse: () => RequisitionStatus.requested,
        ),
        lines: _mapList(json['lines'], RequisitionLine.fromJson),
        approvedBy: _nullableString(json['approvedBy']),
        approvedAt: _nullableDateValue(json['approvedAt']),
        issuedBy: _nullableString(json['issuedBy']),
        issuedAt: _nullableDateValue(json['issuedAt']),
        receivedBy: _nullableString(json['receivedBy']),
        receivedAt: _nullableDateValue(json['receivedAt']),
        note: _nullableString(json['note']),
      );
}

class DepartmentIssue {
  const DepartmentIssue({
    required this.id,
    required this.department,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.quantity,
    required this.unitCostMinor,
    required this.issuedAt,
    this.note,
  });

  final String id;
  final HotelDepartment department;
  final String productId;
  final String productName;
  final String productSku;
  final int quantity;
  final int unitCostMinor;
  final DateTime issuedAt;
  final String? note;

  int get valueMinor => quantity * unitCostMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'department': department.name,
    'productId': productId,
    'productName': productName,
    'productSku': productSku,
    'quantity': quantity,
    'unitCostMinor': unitCostMinor,
    'issuedAt': issuedAt.toIso8601String(),
    if (note != null) 'note': note,
  };

  factory DepartmentIssue.fromJson(Map<String, dynamic> json) {
    return DepartmentIssue(
      id: _requiredString(json, 'id'),
      department: _departmentValue(json['department']),
      productId: _requiredString(json, 'productId'),
      productName: _requiredString(json, 'productName'),
      productSku: _stringValue(json['productSku']),
      quantity: _intValue(json['quantity']),
      unitCostMinor: _intValue(json['unitCostMinor']),
      issuedAt: _dateValue(json['issuedAt']),
      note: _nullableString(json['note']),
    );
  }
}

class DailyDepartmentReport {
  const DailyDepartmentReport({
    required this.id,
    required this.day,
    required this.submittedAt,
    required this.totalUnits,
    required this.totalValueMinor,
    this.note,
  });

  final String id;
  final DateTime day;
  final DateTime submittedAt;
  final int totalUnits;
  final int totalValueMinor;
  final String? note;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'day': day.toIso8601String(),
    'submittedAt': submittedAt.toIso8601String(),
    'totalUnits': totalUnits,
    'totalValueMinor': totalValueMinor,
    if (note != null) 'note': note,
  };

  factory DailyDepartmentReport.fromJson(Map<String, dynamic> json) {
    return DailyDepartmentReport(
      id: _requiredString(json, 'id'),
      day: _dateValue(json['day']),
      submittedAt: _dateValue(json['submittedAt']),
      totalUnits: _intValue(json['totalUnits']),
      totalValueMinor: _intValue(json['totalValueMinor']),
      note: _nullableString(json['note']),
    );
  }
}

class SaleLine {
  const SaleLine({
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.quantity,
    required this.unitPriceMinor,
    required this.unitCostMinor,
  });

  final String productId;
  final String productName;
  final String productSku;
  final int quantity;
  final int unitPriceMinor;
  final int unitCostMinor;

  int get lineTotalMinor => quantity * unitPriceMinor;
  int get lineCostMinor => quantity * unitCostMinor;
  int get grossProfitMinor => lineTotalMinor - lineCostMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'productId': productId,
    'productName': productName,
    'productSku': productSku,
    'quantity': quantity,
    'unitPriceMinor': unitPriceMinor,
    'unitCostMinor': unitCostMinor,
  };

  factory SaleLine.fromJson(Map<String, dynamic> json) {
    return SaleLine(
      productId: _requiredString(json, 'productId'),
      productName: _requiredString(json, 'productName'),
      productSku: _stringValue(json['productSku']),
      quantity: _intValue(json['quantity']),
      unitPriceMinor: _intValue(json['unitPriceMinor']),
      unitCostMinor: _intValue(json['unitCostMinor']),
    );
  }
}

class SaleRecord {
  SaleRecord({
    required this.id,
    required this.receiptNumber,
    required List<SaleLine> lines,
    required this.createdAt,
    this.reference,
    this.customerName,
    this.paymentMethod = 'Cash',
    this.isVoided = false,
    this.voidedAt,
    this.voidReason,
  }) : lines = List<SaleLine>.unmodifiable(lines);

  final String id;
  final String receiptNumber;

  /// An optional external reference, purchase order, or user-supplied receipt.
  final String? reference;
  final String? customerName;
  final String paymentMethod;
  final List<SaleLine> lines;
  final DateTime createdAt;
  final bool isVoided;
  final DateTime? voidedAt;
  final String? voidReason;

  int get subtotalMinor =>
      lines.fold<int>(0, (total, line) => total + line.lineTotalMinor);
  int get totalMinor => subtotalMinor;
  int get costOfGoodsMinor =>
      lines.fold<int>(0, (total, line) => total + line.lineCostMinor);
  int get grossProfitMinor => totalMinor - costOfGoodsMinor;
  int get totalUnits =>
      lines.fold<int>(0, (total, line) => total + line.quantity);
  String get displayReference => reference ?? receiptNumber;

  SaleRecord copyWith({
    String? id,
    String? receiptNumber,
    String? reference,
    String? customerName,
    String? paymentMethod,
    List<SaleLine>? lines,
    DateTime? createdAt,
    bool? isVoided,
    DateTime? voidedAt,
    String? voidReason,
  }) {
    return SaleRecord(
      id: id ?? this.id,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      reference: reference ?? this.reference,
      customerName: customerName ?? this.customerName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      lines: lines ?? this.lines,
      createdAt: createdAt ?? this.createdAt,
      isVoided: isVoided ?? this.isVoided,
      voidedAt: voidedAt ?? this.voidedAt,
      voidReason: voidReason ?? this.voidReason,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'receiptNumber': receiptNumber,
    if (reference != null) 'reference': reference,
    if (customerName != null) 'customerName': customerName,
    'paymentMethod': paymentMethod,
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
    'createdAt': createdAt.toIso8601String(),
    'isVoided': isVoided,
    if (voidedAt != null) 'voidedAt': voidedAt!.toIso8601String(),
    if (voidReason != null) 'voidReason': voidReason,
  };

  factory SaleRecord.fromJson(Map<String, dynamic> json) {
    final receiptNumber = _stringValue(
      json['receiptNumber'] ?? json['reference'],
      fallback: 'Receipt',
    );
    return SaleRecord(
      id: _requiredString(json, 'id'),
      receiptNumber: receiptNumber,
      reference: _nullableString(json['reference']),
      customerName: _nullableString(json['customerName']),
      paymentMethod: _stringValue(json['paymentMethod'], fallback: 'Cash'),
      lines: _mapList(json['lines'], SaleLine.fromJson),
      createdAt: _dateValue(json['createdAt']),
      isVoided: _boolValue(json['isVoided']),
      voidedAt: _nullableDateValue(json['voidedAt']),
      voidReason: _nullableString(json['voidReason']),
    );
  }
}

class SaleItemInput {
  const SaleItemInput({
    required this.productId,
    required this.quantity,
    this.unitPriceMinor,
  });

  final String productId;
  final int quantity;

  /// Optional selling-price override for this transaction.
  final int? unitPriceMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'productId': productId,
    'quantity': quantity,
    if (unitPriceMinor != null) 'unitPriceMinor': unitPriceMinor,
  };

  factory SaleItemInput.fromJson(Map<String, dynamic> json) {
    return SaleItemInput(
      productId: _requiredString(json, 'productId'),
      quantity: _intValue(json['quantity']),
      unitPriceMinor: json['unitPriceMinor'] == null
          ? null
          : _intValue(json['unitPriceMinor']),
    );
  }
}

class StoreSettings {
  const StoreSettings({
    this.storeName = 'The Dream Of Sau Inn Beach Hotel',
    this.currencyCode = 'TZS',
    this.currencySymbol = 'TSh',
    this.currencyDecimalDigits = 0,
    this.defaultLowStockThreshold = 5,
    this.themeMode = 'system',
  }) : assert(
         themeMode == 'system' || themeMode == 'light' || themeMode == 'dark',
         'themeMode must be system, light, or dark.',
       );

  static const Set<String> allowedThemeModes = <String>{
    'system',
    'light',
    'dark',
  };

  final String storeName;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDecimalDigits;
  final int defaultLowStockThreshold;
  final String themeMode;

  StoreSettings copyWith({
    String? storeName,
    String? currencyCode,
    String? currencySymbol,
    int? currencyDecimalDigits,
    int? defaultLowStockThreshold,
    String? themeMode,
  }) {
    return StoreSettings(
      storeName: storeName ?? this.storeName,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyDecimalDigits:
          currencyDecimalDigits ?? this.currencyDecimalDigits,
      defaultLowStockThreshold:
          defaultLowStockThreshold ?? this.defaultLowStockThreshold,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'storeName': storeName,
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'currencyDecimalDigits': currencyDecimalDigits,
    'defaultLowStockThreshold': defaultLowStockThreshold,
    'themeMode': themeMode,
  };

  factory StoreSettings.fromJson(Map<String, dynamic> json) {
    return StoreSettings(
      storeName: _stringValue(
        json['storeName'],
        fallback: 'The Dream Of Sau Inn Beach Hotel',
      ),
      currencyCode: _stringValue(json['currencyCode'], fallback: 'TZS'),
      currencySymbol: _stringValue(json['currencySymbol'], fallback: 'TSh'),
      currencyDecimalDigits: _intValue(
        json['currencyDecimalDigits'],
        fallback: 0,
      ),
      defaultLowStockThreshold: _intValue(
        json['defaultLowStockThreshold'],
        fallback: 5,
      ),
      themeMode: _themeModeValue(json['themeMode']),
    );
  }
}

class InventoryData {
  InventoryData({
    this.schemaVersion = currentSchemaVersion,
    List<Product> products = const <Product>[],
    List<SaleRecord> sales = const <SaleRecord>[],
    List<StockMovement> movements = const <StockMovement>[],
    List<DepartmentIssue> departmentIssues = const <DepartmentIssue>[],
    List<DailyDepartmentReport> dailyReports = const <DailyDepartmentReport>[],
    List<StoreRequisition> requisitions = const <StoreRequisition>[],
    this.settings = const StoreSettings(),
  }) : products = List<Product>.unmodifiable(products),
       sales = List<SaleRecord>.unmodifiable(sales),
       movements = List<StockMovement>.unmodifiable(movements),
       departmentIssues = List<DepartmentIssue>.unmodifiable(departmentIssues),
       dailyReports = List<DailyDepartmentReport>.unmodifiable(dailyReports),
       requisitions = List<StoreRequisition>.unmodifiable(requisitions);

  static const int currentSchemaVersion = 4;

  final int schemaVersion;
  final List<Product> products;
  final List<SaleRecord> sales;
  final List<StockMovement> movements;
  final List<DepartmentIssue> departmentIssues;
  final List<DailyDepartmentReport> dailyReports;
  final List<StoreRequisition> requisitions;
  final StoreSettings settings;

  factory InventoryData.empty({StoreSettings? settings}) {
    return InventoryData(settings: settings ?? const StoreSettings());
  }

  bool get isEmpty =>
      products.isEmpty &&
      sales.isEmpty &&
      movements.isEmpty &&
      departmentIssues.isEmpty &&
      dailyReports.isEmpty &&
      requisitions.isEmpty;

  InventoryData copyWith({
    int? schemaVersion,
    List<Product>? products,
    List<SaleRecord>? sales,
    List<StockMovement>? movements,
    List<DepartmentIssue>? departmentIssues,
    List<DailyDepartmentReport>? dailyReports,
    List<StoreRequisition>? requisitions,
    StoreSettings? settings,
  }) {
    return InventoryData(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      products: products ?? this.products,
      sales: sales ?? this.sales,
      movements: movements ?? this.movements,
      departmentIssues: departmentIssues ?? this.departmentIssues,
      dailyReports: dailyReports ?? this.dailyReports,
      requisitions: requisitions ?? this.requisitions,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'products': products
        .map((product) => product.toJson())
        .toList(growable: false),
    'sales': sales.map((sale) => sale.toJson()).toList(growable: false),
    'movements': movements
        .map((movement) => movement.toJson())
        .toList(growable: false),
    'departmentIssues': departmentIssues
        .map((issue) => issue.toJson())
        .toList(growable: false),
    'dailyReports': dailyReports
        .map((report) => report.toJson())
        .toList(growable: false),
    'requisitions': requisitions
        .map((requisition) => requisition.toJson())
        .toList(growable: false),
    'settings': settings.toJson(),
  };

  factory InventoryData.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _intValue(json['schemaVersion'], fallback: 1);
    if (schemaVersion > currentSchemaVersion) {
      throw const FormatException(
        'This inventory was created by a newer version of DreamStore.',
      );
    }
    return InventoryData(
      schemaVersion: currentSchemaVersion,
      products: _mapList(json['products'], Product.fromJson),
      sales: _mapList(json['sales'], SaleRecord.fromJson),
      movements: _mapList(json['movements'], StockMovement.fromJson),
      departmentIssues: _mapList(
        json['departmentIssues'],
        DepartmentIssue.fromJson,
      ),
      dailyReports: _mapList(
        json['dailyReports'],
        DailyDepartmentReport.fromJson,
      ),
      requisitions: _mapList(
        json['requisitions'],
        StoreRequisition.fromJson,
      ),
      settings: json['settings'] is Map
          ? StoreSettings.fromJson(
              Map<String, dynamic>.from(json['settings'] as Map),
            )
          : const StoreSettings(),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _nullableString(json[key]);
  if (value == null) {
    throw FormatException('Missing required field "$key".');
  }
  return value;
}

String _stringValue(Object? value, {String fallback = ''}) {
  return _nullableString(value) ?? fallback;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  return fallback;
}

DateTime _dateValue(Object? value) {
  final result = _nullableDateValue(value);
  if (result == null) {
    throw const FormatException('A stored date is missing or invalid.');
  }
  return result;
}

DateTime? _nullableDateValue(Object? value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.tryParse(value.toString());
}

StockMovementType _movementTypeValue(Object? value) {
  final name = value?.toString();
  for (final type in StockMovementType.values) {
    if (type.name == name) return type;
  }
  return StockMovementType.adjustment;
}

HotelDepartment _departmentValue(Object? value, [Object? legacyCategory]) {
  final raw = (value ?? legacyCategory)?.toString().trim().toLowerCase();
  for (final department in HotelDepartment.values) {
    if (department.name.toLowerCase() == raw ||
        department.label.toLowerCase() == raw) {
      return department;
    }
  }
  return HotelDepartment.kitchen;
}

String _themeModeValue(Object? value) {
  final themeMode = _stringValue(value, fallback: 'system').toLowerCase();
  if (StoreSettings.allowedThemeModes.contains(themeMode)) return themeMode;
  return 'system';
}

List<T> _mapList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value == null) return <T>[];
  if (value is! List) {
    throw const FormatException('A stored inventory list is invalid.');
  }
  return value
      .map((item) => parse(Map<String, dynamic>.from(item as Map)))
      .toList(growable: false);
}
