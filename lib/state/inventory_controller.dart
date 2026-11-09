import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/inventory_store.dart';
import '../models/inventory_models.dart';

class InventoryController extends ChangeNotifier {
  InventoryController(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final InventoryStore _store;
  final DateTime Function() _clock;

  InventoryData _data = InventoryData.empty();
  Future<void> _serialQueue = Future<void>.value();
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasLoaded = false;
  bool _disposed = false;
  String? _error;
  String _currentActor = 'Store administrator';

  UnmodifiableListView<Product> get products =>
      UnmodifiableListView<Product>(_data.products);
  UnmodifiableListView<SaleRecord> get sales =>
      UnmodifiableListView<SaleRecord>(_data.sales);
  UnmodifiableListView<StockMovement> get movements =>
      UnmodifiableListView<StockMovement>(_data.movements);
  UnmodifiableListView<StockMovement> get stockMovements => movements;
  UnmodifiableListView<DepartmentIssue> get departmentIssues =>
      UnmodifiableListView<DepartmentIssue>(_data.departmentIssues);
  UnmodifiableListView<DailyDepartmentReport> get dailyReports =>
      UnmodifiableListView<DailyDepartmentReport>(_data.dailyReports);
  UnmodifiableListView<StoreRequisition> get requisitions =>
      UnmodifiableListView<StoreRequisition>(_data.requisitions);
  StoreSettings get settings => _data.settings;
  InventoryData get snapshot => _data;
  DateTime get currentTime => _clock();

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isBusy => _isLoading || _isSaving;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  void setCurrentActor(String name) {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isNotEmpty) _currentActor = clean;
  }

  UnmodifiableListView<Product> get activeProducts {
    final result =
        _data.products.where((product) => !product.isArchived).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return UnmodifiableListView<Product>(result);
  }

  UnmodifiableListView<Product> get archivedProducts {
    final result =
        _data.products.where((product) => product.isArchived).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return UnmodifiableListView<Product>(result);
  }

  UnmodifiableListView<Product> get lowStockProducts {
    final result =
        _data.products
            .where((product) => !product.isArchived && product.isLowStock)
            .toList()
          ..sort((a, b) => a.quantity.compareTo(b.quantity));
    return UnmodifiableListView<Product>(result);
  }

  UnmodifiableListView<Product> get outOfStockProducts {
    final result =
        _data.products
            .where((product) => !product.isArchived && product.isOutOfStock)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return UnmodifiableListView<Product>(result);
  }

  UnmodifiableListView<SaleRecord> get recentSales =>
      UnmodifiableListView<SaleRecord>(latestSales());

  UnmodifiableListView<StockMovement> get recentMovements {
    final result = _data.movements.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return UnmodifiableListView<StockMovement>(result.take(10));
  }

  int get totalProductCount => _data.products.length;
  int get activeProductCount =>
      _data.products.where((product) => !product.isArchived).length;
  int get lowStockCount => lowStockProducts.length;
  int get outOfStockCount => outOfStockProducts.length;
  int get totalStockUnits => _data.products
      .where((product) => !product.isArchived)
      .fold<int>(0, (total, product) => total + product.quantity);
  int get inventoryCostValueMinor => _data.products
      .where((product) => !product.isArchived)
      .fold<int>(0, (total, product) => total + product.inventoryValueMinor);
  int get inventoryRetailValueMinor => _data.products
      .where((product) => !product.isArchived)
      .fold<int>(0, (total, product) => total + product.retailValueMinor);
  int get potentialProfitMinor =>
      inventoryRetailValueMinor - inventoryCostValueMinor;
  int get totalSalesCount => _data.sales.where((sale) => !sale.isVoided).length;
  int get totalSalesRevenueMinor => _data.sales
      .where((sale) => !sale.isVoided)
      .fold<int>(0, (total, sale) => total + sale.totalMinor);
  int get totalCostOfGoodsSoldMinor => _data.sales
      .where((sale) => !sale.isVoided)
      .fold<int>(0, (total, sale) => total + sale.costOfGoodsMinor);
  int get totalGrossProfitMinor =>
      totalSalesRevenueMinor - totalCostOfGoodsSoldMinor;

  int get todaysSalesCount {
    final today = _clock().toLocal();
    return _data.sales
        .where(
          (sale) =>
              !sale.isVoided && _isSameDay(sale.createdAt.toLocal(), today),
        )
        .length;
  }

  int get todaysRevenueMinor {
    final today = _clock().toLocal();
    return _data.sales
        .where(
          (sale) =>
              !sale.isVoided && _isSameDay(sale.createdAt.toLocal(), today),
        )
        .fold<int>(0, (total, sale) => total + sale.totalMinor);
  }

  int revenueForPeriod(DateTime from, DateTime to) {
    if (to.isBefore(from)) {
      throw const InventoryException(
        'The report end date must be after its start date.',
        code: 'invalid_date_range',
      );
    }
    return _data.sales
        .where(
          (sale) =>
              !sale.isVoided &&
              !sale.createdAt.isBefore(from) &&
              !sale.createdAt.isAfter(to),
        )
        .fold<int>(0, (total, sale) => total + sale.totalMinor);
  }

  List<SaleRecord> latestSales([int limit = 5]) {
    if (limit <= 0) return const <SaleRecord>[];
    final result = _data.sales.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<SaleRecord>.unmodifiable(result.take(limit));
  }

  Product? productById(String productId) {
    for (final product in _data.products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  Product? productBySku(String sku) {
    final normalized = normalizeSku(sku);
    for (final product in _data.products) {
      if (normalizeSku(product.sku) == normalized) return product;
    }
    return null;
  }

  List<Product> searchProducts(String query, {bool includeArchived = false}) {
    final term = query.trim().toLowerCase();
    final result =
        _data.products.where((product) {
          if (!includeArchived && product.isArchived) return false;
          return term.isEmpty ||
              product.name.toLowerCase().contains(term) ||
              product.sku.toLowerCase().contains(term) ||
              product.category.toLowerCase().contains(term);
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return List<Product>.unmodifiable(result);
  }

  static String normalizeSku(String sku) {
    return sku
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-');
  }

  Future<void> load() {
    return _runSerial<void>(() async {
      _ensureActive();
      _isLoading = true;
      _error = null;
      _notify();
      try {
        final loaded = await _store.load();
        var next = loaded ?? InventoryData.empty();
        if (next.settings.storeName == 'StockPilot') {
          next = next.copyWith(
            settings: next.settings.copyWith(
              storeName: 'The Dream Of Sau Inn Beach Hotel',
            ),
          );
          await _store.save(next);
        }
        _validateInventoryData(next);
        _data = next;
        _hasLoaded = true;
      } catch (error, stackTrace) {
        final exception = _friendlyException(
          error,
          'Your inventory could not be loaded.',
        );
        _error = exception.message;
        Error.throwWithStackTrace(exception, stackTrace);
      } finally {
        _isLoading = false;
        _notify();
      }
    });
  }

  /// Clear the signed-in view, never the underlying local or server inventory.
  Future<void> resetSessionView() => _runSerial<void>(() async {
    _ensureActive();
    _data = InventoryData.empty();
    _hasLoaded = false;
    _error = null;
    _notify();
  });

  Future<Product> addProduct(ProductDraft draft) {
    return _mutate<Product>('The product could not be added.', (data) {
      final clean = _validateDraft(draft);
      _ensureUniqueSku(data, clean.sku);
      final now = _clock();
      final receivedAt = _validateStockDate(
        clean.receivedAt ?? now,
        now,
        'Stock arrival date',
      );
      final product = Product(
        id: _newId('prd'),
        name: clean.name,
        sku: clean.sku,
        category: clean.category,
        department: clean.department,
        unit: clean.unit,
        description: clean.description,
        quantity: clean.initialStock,
        unitCostMinor: clean.unitCostMinor,
        salePriceMinor: clean.salePriceMinor,
        lowStockThreshold: clean.lowStockThreshold,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        receivedAt: receivedAt,
      );

      final nextMovements = <StockMovement>[...data.movements];
      if (product.quantity > 0) {
        nextMovements.add(
          StockMovement(
            id: _newId('mov'),
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            type: StockMovementType.opening,
            quantityDelta: product.quantity,
            quantityBefore: 0,
            quantityAfter: product.quantity,
            unitCostMinor: product.unitCostMinor,
            occurredAt: receivedAt,
            recordedAt: now,
            department: product.department,
            note: 'Opening stock',
            actorName: _currentActor,
          ),
        );
      }

      return _MutationPlan<Product>(
        data.copyWith(
          products: <Product>[...data.products, product],
          movements: nextMovements,
        ),
        product,
      );
    });
  }

  Future<Product> updateProduct(String productId, ProductDraft draft) {
    return _mutate<Product>('The product could not be updated.', (data) {
      final index = _productIndex(data, productId);
      final current = data.products[index];
      final clean = _validateDraft(draft);
      _ensureUniqueSku(data, clean.sku, excludingProductId: current.id);

      final updated = current.copyWith(
        name: clean.name,
        sku: clean.sku,
        category: clean.category,
        department: clean.department,
        unit: clean.unit,
        description: clean.description,
        unitCostMinor: clean.unitCostMinor,
        salePriceMinor: clean.salePriceMinor,
        lowStockThreshold: clean.lowStockThreshold,
        // Editing item details must not rewrite its original arrival record.
        receivedAt: current.receivedAt,
        updatedAt: _clock(),
      );
      final products = <Product>[...data.products]..[index] = updated;
      return _MutationPlan<Product>(data.copyWith(products: products), updated);
    });
  }

  Future<Product> restockProduct(
    String productId,
    int quantity,
    int unitCostMinor, {
    String? note,
    DateTime? receivedAt,
    String? supplierName,
    String? invoiceNumber,
    DateTime? expiryDate,
  }) {
    return _mutate<Product>('The stock could not be added.', (data) {
      if (quantity <= 0) {
        throw const InventoryException(
          'Restock quantity must be greater than zero.',
          code: 'invalid_restock_quantity',
        );
      }
      _validateMoney(unitCostMinor, 'Unit cost');
      final cleanNote = _cleanOptional(note, 'Note', maxLength: 300);
      final cleanSupplier = _cleanOptional(
        supplierName,
        'Supplier',
        maxLength: 120,
      );
      final cleanInvoice = _cleanOptional(
        invoiceNumber,
        'Invoice number',
        maxLength: 80,
      );
      final index = _productIndex(data, productId);
      final current = data.products[index];
      final newQuantity = current.quantity + quantity;
      final averageCost = _weightedAverageCost(
        current.quantity,
        current.unitCostMinor,
        quantity,
        unitCostMinor,
      );
      final now = _clock();
      final arrivalDate = _validateStockDate(
        receivedAt ?? now,
        now,
        'Stock arrival date',
      );
      if (expiryDate != null &&
          _localCalendarDay(
            expiryDate,
          ).isBefore(_localCalendarDay(arrivalDate))) {
        throw const InventoryException(
          'Expiry date cannot be before the delivery arrival date.',
          code: 'expiry_before_receipt',
        );
      }
      final updated = current.copyWith(
        quantity: newQuantity,
        unitCostMinor: averageCost,
        updatedAt: now,
      );
      final products = <Product>[...data.products]..[index] = updated;
      final movement = StockMovement(
        id: _newId('mov'),
        productId: current.id,
        productName: current.name,
        productSku: current.sku,
        type: StockMovementType.restock,
        quantityDelta: quantity,
        quantityBefore: current.quantity,
        quantityAfter: newQuantity,
        unitCostMinor: unitCostMinor,
        occurredAt: arrivalDate,
        recordedAt: now,
        department: current.department,
        note: cleanNote,
        supplierName: cleanSupplier,
        invoiceNumber: cleanInvoice,
        expiryDate: expiryDate,
        actorName: _currentActor,
      );
      return _MutationPlan<Product>(
        data.copyWith(
          products: products,
          movements: <StockMovement>[...data.movements, movement],
        ),
        updated,
      );
    });
  }

  Future<Product> restock(
    String productId,
    int quantity,
    int unitCostMinor, {
    String? note,
    DateTime? receivedAt,
    String? supplierName,
    String? invoiceNumber,
    DateTime? expiryDate,
  }) => restockProduct(
    productId,
    quantity,
    unitCostMinor,
    note: note,
    receivedAt: receivedAt,
    supplierName: supplierName,
    invoiceNumber: invoiceNumber,
    expiryDate: expiryDate,
  );

  Future<Product> adjustStock(
    String productId,
    int newQuantity, {
    String? note,
  }) {
    return _mutate<Product>('The stock adjustment could not be saved.', (data) {
      if (newQuantity < 0) {
        throw const InventoryException(
          'Stock quantity cannot be negative.',
          code: 'invalid_stock_quantity',
        );
      }
      final cleanNote = _cleanRequired(
        note ?? '',
        'Adjustment reason',
        maxLength: 300,
      );
      final index = _productIndex(data, productId);
      final current = data.products[index];
      final difference = newQuantity - current.quantity;
      if (difference == 0) {
        throw InventoryException(
          '${current.name} already has $newQuantity units in stock.',
          code: 'unchanged_stock_quantity',
        );
      }
      final now = _clock();
      final updated = current.copyWith(quantity: newQuantity, updatedAt: now);
      final products = <Product>[...data.products]..[index] = updated;
      final movement = StockMovement(
        id: _newId('mov'),
        productId: current.id,
        productName: current.name,
        productSku: current.sku,
        type: StockMovementType.adjustment,
        quantityDelta: difference,
        quantityBefore: current.quantity,
        quantityAfter: newQuantity,
        unitCostMinor: current.unitCostMinor,
        occurredAt: now,
        recordedAt: now,
        department: current.department,
        note: cleanNote,
        actorName: _currentActor,
      );
      return _MutationPlan<Product>(
        data.copyWith(
          products: products,
          movements: <StockMovement>[...data.movements, movement],
        ),
        updated,
      );
    });
  }

  Future<StoreRequisition> createRequisition({
    required HotelDepartment department,
    required String requestedBy,
    required List<SaleItemInput> items,
    String? note,
  }) {
    return _mutate<StoreRequisition>(
      'The store requisition could not be submitted.',
      (data) {
        final requester = _cleanRequired(
          requestedBy,
          'Requester name',
          maxLength: 100,
        );
        if (items.isEmpty) {
          throw const InventoryException(
            'Add at least one item to the requisition.',
            code: 'empty_requisition',
          );
        }
        final quantities = <String, int>{};
        for (final item in items) {
          if (item.quantity <= 0) {
            throw const InventoryException(
              'Each requested quantity must be greater than zero.',
              code: 'invalid_requisition_quantity',
            );
          }
          quantities.update(
            item.productId,
            (quantity) => quantity + item.quantity,
            ifAbsent: () => item.quantity,
          );
        }
        final lines = <RequisitionLine>[];
        for (final entry in quantities.entries) {
          final product = data.products.firstWhere(
            (product) => product.id == entry.key,
            orElse: () => throw const InventoryException(
              'A requested product no longer exists.',
              code: 'product_not_found',
            ),
          );
          if (product.isArchived) {
            throw InventoryException(
              '${product.name} is archived and cannot be requested.',
              code: 'archived_product',
            );
          }
          lines.add(
            RequisitionLine(
              productId: product.id,
              productName: product.name,
              productSku: product.sku,
              quantity: entry.value,
              unitCostMinor: product.unitCostMinor,
              unit: product.unit,
            ),
          );
        }
        final requisition = StoreRequisition(
          id: _newId('req'),
          department: department,
          requestedBy: requester,
          requestedAt: _clock(),
          status: RequisitionStatus.requested,
          lines: lines,
          note: _cleanOptional(note, 'Note', maxLength: 300),
        );
        return _MutationPlan<StoreRequisition>(
          data.copyWith(
            requisitions: <StoreRequisition>[...data.requisitions, requisition],
          ),
          requisition,
        );
      },
    );
  }

  Future<StoreRequisition> approveRequisition(
    String requisitionId, {
    required String approvedBy,
  }) {
    return _mutate<StoreRequisition>('The requisition could not be approved.', (
      data,
    ) {
      final index = _requisitionIndex(data, requisitionId);
      final current = data.requisitions[index];
      if (current.status != RequisitionStatus.requested) {
        throw const InventoryException(
          'Only a pending requisition can be approved.',
          code: 'invalid_requisition_status',
        );
      }
      final approver = _cleanRequired(
        approvedBy,
        'Approver name',
        maxLength: 100,
      );
      final updated = current.copyWith(
        status: RequisitionStatus.approved,
        approvedBy: approver,
        approvedAt: _clock(),
      );
      final requisitions = <StoreRequisition>[...data.requisitions]
        ..[index] = updated;
      return _MutationPlan(data.copyWith(requisitions: requisitions), updated);
    });
  }

  Future<StoreRequisition> rejectRequisition(
    String requisitionId, {
    required String rejectedBy,
    required String reason,
  }) {
    return _mutate<StoreRequisition>('The requisition could not be rejected.', (
      data,
    ) {
      final index = _requisitionIndex(data, requisitionId);
      final current = data.requisitions[index];
      if (current.status != RequisitionStatus.requested) {
        throw const InventoryException(
          'Only a pending requisition can be rejected.',
          code: 'invalid_requisition_status',
        );
      }
      final actor = _cleanRequired(rejectedBy, 'Reviewer name', maxLength: 100);
      final cleanReason = _cleanRequired(
        reason,
        'Rejection reason',
        maxLength: 300,
      );
      final updated = current.copyWith(
        status: RequisitionStatus.rejected,
        approvedBy: actor,
        approvedAt: _clock(),
        note: cleanReason,
      );
      final requisitions = <StoreRequisition>[...data.requisitions]
        ..[index] = updated;
      return _MutationPlan(data.copyWith(requisitions: requisitions), updated);
    });
  }

  Future<StoreRequisition> issueRequisition(
    String requisitionId, {
    required String issuedBy,
  }) {
    return _mutate<
      StoreRequisition
    >('The approved requisition could not be issued.', (data) {
      final index = _requisitionIndex(data, requisitionId);
      final current = data.requisitions[index];
      if (current.status != RequisitionStatus.approved) {
        throw const InventoryException(
          'Only an approved requisition can be issued.',
          code: 'invalid_requisition_status',
        );
      }
      final actor = _cleanRequired(issuedBy, 'Issuer name', maxLength: 100);
      final now = _clock();
      final productsById = <String, Product>{
        for (final product in data.products) product.id: product,
      };
      for (final line in current.lines) {
        final product = productsById[line.productId];
        if (product == null || product.isArchived) {
          throw InventoryException(
            '${line.productName} is unavailable and cannot be issued.',
            code: 'product_not_available',
          );
        }
        if (product.quantity < line.quantity) {
          throw InventoryException(
            '${product.name} has only ${product.quantity} ${product.unit} available.',
            code: 'insufficient_stock',
          );
        }
      }
      final updatedProducts = <String, Product>{};
      final newIssues = <DepartmentIssue>[];
      final newMovements = <StockMovement>[];
      for (final line in current.lines) {
        final product = productsById[line.productId]!;
        final updated = product.copyWith(
          quantity: product.quantity - line.quantity,
          updatedAt: now,
        );
        updatedProducts[product.id] = updated;
        newIssues.add(
          DepartmentIssue(
            id: _newId('issue'),
            department: current.department,
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            quantity: line.quantity,
            unitCostMinor: product.unitCostMinor,
            issuedAt: now,
            note: 'Requisition ${current.id}',
          ),
        );
        newMovements.add(
          StockMovement(
            id: _newId('mov'),
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            type: StockMovementType.departmentIssue,
            quantityDelta: -line.quantity,
            quantityBefore: product.quantity,
            quantityAfter: updated.quantity,
            unitCostMinor: product.unitCostMinor,
            occurredAt: now,
            recordedAt: now,
            department: current.department,
            note: 'Requisition ${current.id}',
            actorName: actor,
          ),
        );
      }
      final issued = current.copyWith(
        status: RequisitionStatus.issued,
        issuedBy: actor,
        issuedAt: now,
      );
      final requisitions = <StoreRequisition>[...data.requisitions]
        ..[index] = issued;
      return _MutationPlan(
        data.copyWith(
          products: data.products
              .map((product) => updatedProducts[product.id] ?? product)
              .toList(growable: false),
          requisitions: requisitions,
          departmentIssues: <DepartmentIssue>[
            ...data.departmentIssues,
            ...newIssues,
          ],
          movements: <StockMovement>[...data.movements, ...newMovements],
        ),
        issued,
      );
    });
  }

  Future<StoreRequisition> confirmRequisitionReceived(
    String requisitionId, {
    required String receivedBy,
  }) {
    return _mutate<StoreRequisition>(
      'The requisition receipt could not be confirmed.',
      (data) {
        final index = _requisitionIndex(data, requisitionId);
        final current = data.requisitions[index];
        if (current.status != RequisitionStatus.issued) {
          throw const InventoryException(
            'Only an issued requisition can be confirmed as received.',
            code: 'invalid_requisition_status',
          );
        }
        final actor = _cleanRequired(
          receivedBy,
          'Receiver name',
          maxLength: 100,
        );
        final received = current.copyWith(
          status: RequisitionStatus.received,
          receivedBy: actor,
          receivedAt: _clock(),
        );
        final requisitions = <StoreRequisition>[...data.requisitions]
          ..[index] = received;
        return _MutationPlan(
          data.copyWith(requisitions: requisitions),
          received,
        );
      },
    );
  }

  List<DepartmentIssue> issuesForDay(DateTime day) {
    return List<DepartmentIssue>.unmodifiable(
      _data.departmentIssues.where(
        (issue) => _isSameDay(issue.issuedAt.toLocal(), day.toLocal()),
      ),
    );
  }

  List<DepartmentIssue> issuesForDepartment(HotelDepartment department) {
    final result =
        _data.departmentIssues
            .where((issue) => issue.department == department)
            .toList()
          ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return List<DepartmentIssue>.unmodifiable(result);
  }

  bool isDailyReportSubmitted(DateTime day) => _data.dailyReports.any(
    (report) => _isSameDay(report.day.toLocal(), day.toLocal()),
  );

  Future<DepartmentIssue> issueStock(
    String productId,
    HotelDepartment department,
    int quantity, {
    String? note,
    DateTime? usedAt,
  }) {
    return _mutate<
      DepartmentIssue
    >('The department issue could not be saved.', (data) {
      if (quantity <= 0) {
        throw const InventoryException(
          'Issue quantity must be greater than zero.',
          code: 'invalid_issue_quantity',
        );
      }
      final cleanNote = _cleanOptional(note, 'Note', maxLength: 300);
      final index = _productIndex(data, productId);
      final current = data.products[index];
      if (current.isArchived) {
        throw const InventoryException(
          'Archived products cannot be issued to a department.',
          code: 'archived_product',
        );
      }
      if (current.department != department) {
        throw InventoryException(
          '${current.name} belongs to ${current.department.label}. Record its usage in that department.',
          code: 'department_mismatch',
        );
      }
      if (current.quantity < quantity) {
        throw InventoryException(
          '${current.name} has only ${current.quantity} units available.',
          code: 'insufficient_stock',
        );
      }
      final now = _clock();
      final usageDate = _validateStockDate(usedAt ?? now, now, 'Usage date');
      DateTime? firstArrival;
      for (final movement in data.movements) {
        if (movement.productId != current.id ||
            (movement.type != StockMovementType.opening &&
                movement.type != StockMovementType.restock)) {
          continue;
        }
        if (firstArrival == null ||
            movement.occurredAt.isBefore(firstArrival)) {
          firstArrival = movement.occurredAt;
        }
      }
      final arrivalDay = _localCalendarDay(firstArrival ?? current.receivedAt);
      if (_localCalendarDay(usageDate).isBefore(arrivalDay)) {
        throw InventoryException(
          '${current.name} cannot be used before its first stock arrival. Choose the arrival day or a later day.',
          code: 'usage_before_stock_arrival',
        );
      }
      // Backdated entries apply current on-hand stock; they do not reconstruct
      // stock balances or unit costs for the historical usage day.
      if (data.dailyReports.any(
        (report) => _isSameDay(report.day.toLocal(), usageDate.toLocal()),
      )) {
        throw const InventoryException(
          'Usage cannot be added to a day whose daily report has already been submitted. Choose an open day.',
          code: 'daily_report_submitted',
        );
      }
      final updated = current.copyWith(
        quantity: current.quantity - quantity,
        updatedAt: now,
      );
      final issue = DepartmentIssue(
        id: _newId('issue'),
        department: department,
        productId: current.id,
        productName: current.name,
        productSku: current.sku,
        quantity: quantity,
        unitCostMinor: current.unitCostMinor,
        issuedAt: usageDate,
        note: cleanNote,
      );
      final movement = StockMovement(
        id: _newId('mov'),
        productId: current.id,
        productName: current.name,
        productSku: current.sku,
        type: StockMovementType.departmentIssue,
        quantityDelta: -quantity,
        quantityBefore: current.quantity,
        quantityAfter: updated.quantity,
        unitCostMinor: current.unitCostMinor,
        occurredAt: usageDate,
        recordedAt: now,
        department: department,
        note:
            '${department.label} issue${cleanNote == null ? '' : ': $cleanNote'}',
        actorName: _currentActor,
      );
      final products = <Product>[...data.products]..[index] = updated;
      return _MutationPlan<DepartmentIssue>(
        data.copyWith(
          products: products,
          movements: <StockMovement>[...data.movements, movement],
          departmentIssues: <DepartmentIssue>[...data.departmentIssues, issue],
        ),
        issue,
      );
    });
  }

  Future<DailyDepartmentReport> submitDailyReport({
    DateTime? day,
    String? note,
  }) {
    return _mutate<DailyDepartmentReport>(
      'The daily department report could not be submitted.',
      (data) {
        final now = _clock();
        final reportDay = _localCalendarDay(
          _validateStockDate(day ?? now, now, 'Report date'),
        );
        if (data.dailyReports.any(
          (report) => _isSameDay(report.day.toLocal(), reportDay),
        )) {
          throw const InventoryException(
            'This daily report has already been submitted.',
            code: 'duplicate_daily_report',
          );
        }
        final issues = data.departmentIssues.where(
          (issue) => _isSameDay(issue.issuedAt.toLocal(), reportDay),
        );
        final report = DailyDepartmentReport(
          id: _newId('report'),
          day: reportDay,
          submittedAt: now,
          totalUnits: issues.fold<int>(0, (sum, issue) => sum + issue.quantity),
          totalValueMinor: issues.fold<int>(
            0,
            (sum, issue) => sum + issue.valueMinor,
          ),
          note: _cleanOptional(note, 'Note', maxLength: 300),
        );
        return _MutationPlan<DailyDepartmentReport>(
          data.copyWith(
            dailyReports: <DailyDepartmentReport>[...data.dailyReports, report],
          ),
          report,
        );
      },
    );
  }

  Future<SaleRecord> recordSale(
    List<SaleItemInput> items, {
    String? reference,
    String? note,
    String? customerName,
    String paymentMethod = 'Cash',
  }) {
    return _mutate<SaleRecord>('The sale could not be recorded.', (data) {
      if (items.isEmpty) {
        throw const InventoryException(
          'Add at least one product to the sale.',
          code: 'empty_sale',
        );
      }

      final cleanReference = _cleanOptional(
        reference,
        'Reference',
        maxLength: 80,
      );
      final cleanCustomer = _cleanOptional(
        customerName,
        'Customer name',
        maxLength: 100,
      );
      final cleanPayment = _cleanRequired(
        paymentMethod,
        'Payment method',
        maxLength: 40,
      );
      final cleanNote = _cleanOptional(note, 'Note', maxLength: 300);

      final combined = <String, SaleItemInput>{};
      for (final input in items) {
        final id = input.productId.trim();
        if (id.isEmpty) {
          throw const InventoryException(
            'One of the sale items has no product.',
            code: 'missing_sale_product',
          );
        }
        if (input.quantity <= 0) {
          throw const InventoryException(
            'Every sale quantity must be greater than zero.',
            code: 'invalid_sale_quantity',
          );
        }
        if (input.unitPriceMinor != null) {
          _validateMoney(input.unitPriceMinor!, 'Selling price');
        }
        final previous = combined[id];
        if (previous == null) {
          combined[id] = SaleItemInput(
            productId: id,
            quantity: input.quantity,
            unitPriceMinor: input.unitPriceMinor,
          );
        } else {
          final previousPrice = previous.unitPriceMinor;
          final incomingPrice = input.unitPriceMinor;
          if (previousPrice != incomingPrice) {
            throw const InventoryException(
              'Duplicate sale items must use the same selling price.',
              code: 'conflicting_sale_prices',
            );
          }
          combined[id] = SaleItemInput(
            productId: id,
            quantity: previous.quantity + input.quantity,
            unitPriceMinor: incomingPrice,
          );
        }
      }

      final productsById = <String, Product>{
        for (final product in data.products) product.id: product,
      };
      for (final input in combined.values) {
        final product = productsById[input.productId];
        if (product == null) {
          throw const InventoryException(
            'One of the selected products no longer exists.',
            code: 'product_not_found',
          );
        }
        if (product.isArchived) {
          throw InventoryException(
            '${product.name} is archived and cannot be sold.',
            code: 'archived_product',
          );
        }
        if (product.quantity < input.quantity) {
          throw InventoryException(
            '${product.name} has only ${product.quantity} units available.',
            code: 'insufficient_stock',
          );
        }
      }

      if (cleanReference != null &&
          data.sales.any(
            (sale) =>
                sale.receiptNumber.toLowerCase() ==
                cleanReference.toLowerCase(),
          )) {
        throw InventoryException(
          'Receipt "$cleanReference" has already been used.',
          code: 'duplicate_receipt',
        );
      }

      final now = _clock();
      final saleId = _newId('sale');
      final receiptNumber = cleanReference ?? _newReceiptNumber(now);
      final updatedProducts = <String, Product>{};
      final lines = <SaleLine>[];
      final saleMovements = <StockMovement>[];

      for (final input in combined.values) {
        final product = productsById[input.productId]!;
        final updated = product.copyWith(
          quantity: product.quantity - input.quantity,
          updatedAt: now,
        );
        updatedProducts[product.id] = updated;
        lines.add(
          SaleLine(
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            quantity: input.quantity,
            unitPriceMinor: input.unitPriceMinor ?? product.salePriceMinor,
            unitCostMinor: product.unitCostMinor,
          ),
        );
        saleMovements.add(
          StockMovement(
            id: _newId('mov'),
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            type: StockMovementType.sale,
            quantityDelta: -input.quantity,
            quantityBefore: product.quantity,
            quantityAfter: updated.quantity,
            unitCostMinor: product.unitCostMinor,
            occurredAt: now,
            recordedAt: now,
            department: product.department,
            relatedSaleId: saleId,
            note: cleanNote ?? 'Sale $receiptNumber',
            actorName: _currentActor,
          ),
        );
      }

      final sale = SaleRecord(
        id: saleId,
        receiptNumber: receiptNumber,
        reference: cleanReference,
        customerName: cleanCustomer,
        paymentMethod: cleanPayment,
        lines: lines,
        createdAt: now,
      );
      final products = data.products
          .map((product) => updatedProducts[product.id] ?? product)
          .toList(growable: false);
      return _MutationPlan<SaleRecord>(
        data.copyWith(
          products: products,
          sales: <SaleRecord>[...data.sales, sale],
          movements: <StockMovement>[...data.movements, ...saleMovements],
        ),
        sale,
      );
    });
  }

  Future<SaleRecord> voidSale(String saleId, {String? reason}) {
    return _mutate<SaleRecord>('The sale could not be voided.', (data) {
      final index = data.sales.indexWhere((sale) => sale.id == saleId.trim());
      if (index < 0) {
        throw const InventoryException(
          'The selected sale could not be found.',
          code: 'sale_not_found',
        );
      }
      final sale = data.sales[index];
      if (sale.isVoided) {
        throw InventoryException(
          'Sale ${sale.receiptNumber} has already been voided.',
          code: 'sale_already_voided',
        );
      }
      final cleanReason =
          _cleanOptional(reason, 'Void reason', maxLength: 300) ??
          'Sale voided';
      final productsById = <String, Product>{
        for (final product in data.products) product.id: product,
      };
      for (final line in sale.lines) {
        if (!productsById.containsKey(line.productId)) {
          throw InventoryException(
            '${line.productName} no longer exists, so this sale cannot be voided.',
            code: 'sale_product_missing',
          );
        }
      }

      final now = _clock();
      final reversals = <StockMovement>[];
      for (final line in sale.lines) {
        final product = productsById[line.productId]!;
        final restoredQuantity = product.quantity + line.quantity;
        final restoredAverageCost = _weightedAverageCost(
          product.quantity,
          product.unitCostMinor,
          line.quantity,
          line.unitCostMinor,
        );
        final restored = product.copyWith(
          quantity: restoredQuantity,
          unitCostMinor: restoredAverageCost,
          updatedAt: now,
        );
        productsById[line.productId] = restored;
        reversals.add(
          StockMovement(
            id: _newId('mov'),
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            type: StockMovementType.reversal,
            quantityDelta: line.quantity,
            quantityBefore: product.quantity,
            quantityAfter: restoredQuantity,
            unitCostMinor: line.unitCostMinor,
            occurredAt: now,
            recordedAt: now,
            department: product.department,
            relatedSaleId: sale.id,
            note: cleanReason,
            actorName: _currentActor,
          ),
        );
      }

      final voidedSale = sale.copyWith(
        isVoided: true,
        voidedAt: now,
        voidReason: cleanReason,
      );
      final sales = <SaleRecord>[...data.sales]..[index] = voidedSale;
      final products = data.products
          .map((product) => productsById[product.id]!)
          .toList(growable: false);
      return _MutationPlan<SaleRecord>(
        data.copyWith(
          products: products,
          sales: sales,
          movements: <StockMovement>[...data.movements, ...reversals],
        ),
        voidedSale,
      );
    });
  }

  Future<Product> setProductArchived(String productId, bool isArchived) {
    return _mutate<Product>('The product status could not be changed.', (data) {
      final index = _productIndex(data, productId);
      final current = data.products[index];
      final updated = current.copyWith(
        isArchived: isArchived,
        updatedAt: _clock(),
      );
      final products = <Product>[...data.products]..[index] = updated;
      return _MutationPlan<Product>(data.copyWith(products: products), updated);
    });
  }

  Future<Product> archiveProduct(String productId) =>
      setProductArchived(productId, true);

  Future<Product> restoreProduct(String productId) =>
      setProductArchived(productId, false);

  Future<StoreSettings> updateSettings(StoreSettings settings) {
    return _mutate<StoreSettings>('The store settings could not be saved.', (
      data,
    ) {
      final clean = _validateSettings(settings);
      return _MutationPlan<StoreSettings>(
        data.copyWith(settings: clean),
        clean,
      );
    });
  }

  Future<void> clearData({bool preserveSettings = false}) {
    return _mutate<void>('The inventory could not be cleared.', (data) {
      final empty = InventoryData.empty(
        settings: preserveSettings ? data.settings : null,
      );
      return _MutationPlan<void>(empty, null, clearStore: !preserveSettings);
    });
  }

  Future<List<Product>> seedDemoData() {
    return _mutate<List<Product>>('Demo inventory could not be created.', (
      data,
    ) {
      if (!data.isEmpty) {
        throw const InventoryException(
          'Demo inventory can only be added to an empty store.',
          code: 'store_not_empty',
        );
      }
      const drafts = <ProductDraft>[
        ProductDraft(
          name: 'Bottled Water 1.5 L',
          sku: 'HOTEL-WATER-15L',
          category: 'Guest supplies',
          department: HotelDepartment.reception,
          description: 'Chilled drinking water for guest rooms and restaurant',
          initialStock: 24,
          unitCostMinor: 13500,
          salePriceMinor: 16500,
          lowStockThreshold: 5,
        ),
        ProductDraft(
          name: 'Beach Towel',
          sku: 'HOTEL-TOWEL-BEACH',
          category: 'Housekeeping',
          department: HotelDepartment.housekeeping,
          description: 'Clean guest beach towel',
          initialStock: 18,
          unitCostMinor: 11800,
          salePriceMinor: 14500,
          lowStockThreshold: 4,
        ),
        ProductDraft(
          name: 'Room Soap Bar',
          sku: 'HOTEL-SOAP-001',
          category: 'Guest supplies',
          department: HotelDepartment.housekeeping,
          description: 'Guest bathroom soap amenity',
          initialStock: 42,
          unitCostMinor: 950,
          salePriceMinor: 1300,
          lowStockThreshold: 10,
        ),
        ProductDraft(
          name: 'Breakfast Juice 1 L',
          sku: 'HOTEL-JUICE-1L',
          category: 'Restaurant',
          department: HotelDepartment.restaurant,
          description: 'Breakfast service juice bottle',
          initialStock: 36,
          unitCostMinor: 700,
          salePriceMinor: 1000,
          lowStockThreshold: 8,
        ),
        ProductDraft(
          name: 'Laundry Detergent 5 kg',
          sku: 'HOTEL-DETERGENT-5KG',
          category: 'Housekeeping',
          department: HotelDepartment.laundry,
          description: 'Professional laundry detergent for hotel linen',
          initialStock: 15,
          unitCostMinor: 1800,
          salePriceMinor: 2500,
          lowStockThreshold: 5,
        ),
      ];

      final now = _clock();
      final products = <Product>[];
      final movements = <StockMovement>[];
      for (final draft in drafts) {
        final product = Product(
          id: _newId('prd'),
          name: draft.name,
          sku: normalizeSku(draft.sku),
          category: draft.category,
          department: draft.department,
          unit: draft.unit,
          description: draft.description,
          quantity: draft.initialStock,
          unitCostMinor: draft.unitCostMinor,
          salePriceMinor: draft.salePriceMinor,
          lowStockThreshold: draft.lowStockThreshold,
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        );
        products.add(product);
        movements.add(
          StockMovement(
            id: _newId('mov'),
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            type: StockMovementType.opening,
            quantityDelta: product.quantity,
            quantityBefore: 0,
            quantityAfter: product.quantity,
            unitCostMinor: product.unitCostMinor,
            occurredAt: now,
            recordedAt: now,
            department: product.department,
            note: 'Demo opening stock',
            actorName: _currentActor,
          ),
        );
      }
      return _MutationPlan<List<Product>>(
        data.copyWith(products: products, movements: movements),
        List<Product>.unmodifiable(products),
      );
    });
  }

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert(_data.toJson());
  }

  Future<void> importJson(String encoded) {
    return _mutate<void>('The backup could not be imported.', (data) {
      if (encoded.trim().isEmpty) {
        throw const InventoryException(
          'Choose a DreamStore backup with content to import.',
          code: 'empty_backup',
        );
      }
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) {
          throw const FormatException('Invalid backup root.');
        }
        final imported = InventoryData.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        _validateInventoryData(imported);
        return _MutationPlan<void>(imported, null);
      } on InventoryException {
        rethrow;
      } catch (error) {
        throw const InventoryException(
          'This is not a valid DreamStore inventory backup.',
          code: 'invalid_backup',
        );
      }
    });
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  Future<T> _mutate<T>(
    String fallbackMessage,
    _MutationPlan<T> Function(InventoryData data) build,
  ) {
    return _runSerial<T>(() async {
      _ensureActive();
      _isSaving = true;
      _error = null;
      _notify();
      try {
        final plan = build(_data);
        _validateInventoryData(plan.data);
        if (plan.clearStore) {
          await _store.clear();
        } else {
          await _store.save(plan.data);
        }
        _data = plan.data;
        return plan.value;
      } catch (error, stackTrace) {
        var exception = _friendlyException(error, fallbackMessage);
        if (exception.code == 'inventory_conflict') {
          try {
            final latest = await _store.load();
            final next = latest ?? InventoryData.empty();
            _validateInventoryData(next);
            _data = next;
            _hasLoaded = true;
            exception = const InventoryException(
              'Another device changed the stock. The latest inventory has been loaded. Check quantities and retry your action.',
              code: 'inventory_conflict',
            );
          } catch (_) {
            // Never replay a stock deduction; report the original conflict.
          }
        }
        _error = exception.message;
        Error.throwWithStackTrace(exception, stackTrace);
      } finally {
        _isSaving = false;
        _notify();
      }
    });
  }

  Future<T> _runSerial<T>(Future<T> Function() action) {
    final operation = _serialQueue.then<T>((_) => action());
    _serialQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  ProductDraft _validateDraft(ProductDraft draft) {
    final name = _cleanRequired(draft.name, 'Product name', maxLength: 100);
    final sku = normalizeSku(draft.sku);
    if (sku.isEmpty) {
      throw const InventoryException(
        'Enter a SKU for the product.',
        code: 'missing_sku',
      );
    }
    if (sku.length > 64) {
      throw const InventoryException(
        'SKU must be 64 characters or fewer.',
        code: 'sku_too_long',
      );
    }
    if (!RegExp(r'^[A-Z0-9][A-Z0-9._/-]*$').hasMatch(sku)) {
      throw const InventoryException(
        'SKU can only contain letters, numbers, dots, dashes, slashes, and underscores.',
        code: 'invalid_sku',
      );
    }
    final category = draft.category.trim().isEmpty
        ? 'General'
        : _cleanRequired(draft.category, 'Category', maxLength: 60);
    final description = draft.description.trim();
    if (description.length > 500) {
      throw const InventoryException(
        'Description must be 500 characters or fewer.',
        code: 'description_too_long',
      );
    }
    if (draft.initialStock < 0) {
      throw const InventoryException(
        'Opening stock cannot be negative.',
        code: 'invalid_opening_stock',
      );
    }
    _validateMoney(draft.unitCostMinor, 'Unit cost');
    _validateMoney(draft.salePriceMinor, 'Selling price');
    if (draft.lowStockThreshold < 0) {
      throw const InventoryException(
        'Low-stock alert level cannot be negative.',
        code: 'invalid_low_stock_threshold',
      );
    }
    return ProductDraft(
      name: name,
      sku: sku,
      category: category,
      department: draft.department,
      unit: _cleanRequired(draft.unit, 'Unit', maxLength: 24),
      description: description,
      initialStock: draft.initialStock,
      unitCostMinor: draft.unitCostMinor,
      salePriceMinor: draft.salePriceMinor,
      lowStockThreshold: draft.lowStockThreshold,
      receivedAt: draft.receivedAt,
    );
  }

  StoreSettings _validateSettings(StoreSettings settings) {
    final storeName = _cleanRequired(
      settings.storeName,
      'Store name',
      maxLength: 100,
    );
    final code = _cleanRequired(
      settings.currencyCode,
      'Currency code',
      maxLength: 8,
    ).toUpperCase();
    final symbol = _cleanRequired(
      settings.currencySymbol,
      'Currency symbol',
      maxLength: 8,
    );
    if (settings.currencyDecimalDigits < 0 ||
        settings.currencyDecimalDigits > 4) {
      throw const InventoryException(
        'Currency decimal digits must be between 0 and 4.',
        code: 'invalid_currency_digits',
      );
    }
    if (settings.defaultLowStockThreshold < 0) {
      throw const InventoryException(
        'Default low-stock alert level cannot be negative.',
        code: 'invalid_low_stock_threshold',
      );
    }
    final themeMode = settings.themeMode.trim().toLowerCase();
    if (!StoreSettings.allowedThemeModes.contains(themeMode)) {
      throw const InventoryException(
        'Theme must be system, light, or dark.',
        code: 'invalid_theme_mode',
      );
    }
    return StoreSettings(
      storeName: storeName,
      currencyCode: code,
      currencySymbol: symbol,
      currencyDecimalDigits: settings.currencyDecimalDigits,
      defaultLowStockThreshold: settings.defaultLowStockThreshold,
      themeMode: themeMode,
    );
  }

  void _ensureUniqueSku(
    InventoryData data,
    String sku, {
    String? excludingProductId,
  }) {
    final duplicate = data.products.any(
      (product) =>
          product.id != excludingProductId &&
          normalizeSku(product.sku) == normalizeSku(sku),
    );
    if (duplicate) {
      throw InventoryException(
        'A product with SKU $sku already exists.',
        code: 'duplicate_sku',
      );
    }
  }

  int _productIndex(InventoryData data, String productId) {
    final id = productId.trim();
    final index = data.products.indexWhere((product) => product.id == id);
    if (index < 0) {
      throw const InventoryException(
        'The selected product could not be found.',
        code: 'product_not_found',
      );
    }
    return index;
  }

  int _requisitionIndex(InventoryData data, String requisitionId) {
    final id = requisitionId.trim();
    final index = data.requisitions.indexWhere(
      (requisition) => requisition.id == id,
    );
    if (index < 0) {
      throw const InventoryException(
        'The selected requisition could not be found.',
        code: 'requisition_not_found',
      );
    }
    return index;
  }

  static void _validateInventoryData(InventoryData data) {
    if (data.schemaVersion != InventoryData.currentSchemaVersion) {
      throw const InventoryException(
        'This inventory uses an unsupported data version.',
        code: 'unsupported_schema',
      );
    }
    final productIds = <String>{};
    final skus = <String>{};
    for (final product in data.products) {
      if (product.id.trim().isEmpty || !productIds.add(product.id)) {
        throw const InventoryException(
          'The inventory contains duplicate or missing product IDs.',
          code: 'invalid_inventory',
        );
      }
      final sku = normalizeSku(product.sku);
      if (sku.isEmpty || !skus.add(sku)) {
        throw const InventoryException(
          'The inventory contains duplicate or missing SKUs.',
          code: 'invalid_inventory',
        );
      }
      if (product.name.trim().isEmpty ||
          product.unit.trim().isEmpty ||
          product.quantity < 0 ||
          product.unitCostMinor < 0 ||
          product.salePriceMinor < 0 ||
          product.lowStockThreshold < 0) {
        throw const InventoryException(
          'The inventory contains an invalid product.',
          code: 'invalid_inventory',
        );
      }
    }

    final saleIds = <String>{};
    final receipts = <String>{};
    for (final sale in data.sales) {
      if (sale.id.trim().isEmpty || !saleIds.add(sale.id)) {
        throw const InventoryException(
          'The inventory contains duplicate or missing sale IDs.',
          code: 'invalid_inventory',
        );
      }
      if (sale.receiptNumber.trim().isEmpty ||
          !receipts.add(sale.receiptNumber.toLowerCase()) ||
          sale.lines.isEmpty ||
          sale.paymentMethod.trim().isEmpty) {
        throw const InventoryException(
          'The inventory contains an invalid sale.',
          code: 'invalid_inventory',
        );
      }
      for (final line in sale.lines) {
        if (line.productId.trim().isEmpty ||
            line.productName.trim().isEmpty ||
            line.quantity <= 0 ||
            line.unitPriceMinor < 0 ||
            line.unitCostMinor < 0) {
          throw const InventoryException(
            'The inventory contains an invalid sale item.',
            code: 'invalid_inventory',
          );
        }
      }
    }

    final movementIds = <String>{};
    for (final movement in data.movements) {
      if (movement.id.trim().isEmpty || !movementIds.add(movement.id)) {
        throw const InventoryException(
          'The inventory contains duplicate or missing movement IDs.',
          code: 'invalid_inventory',
        );
      }
      if (movement.productId.trim().isEmpty ||
          movement.quantityAfter !=
              movement.quantityBefore + movement.quantityDelta ||
          movement.quantityBefore < 0 ||
          movement.quantityAfter < 0 ||
          movement.unitCostMinor < 0) {
        throw const InventoryException(
          'The inventory contains an invalid stock movement.',
          code: 'invalid_inventory',
        );
      }
    }
    final requisitionIds = <String>{};
    for (final requisition in data.requisitions) {
      if (requisition.id.trim().isEmpty ||
          !requisitionIds.add(requisition.id) ||
          requisition.requestedBy.trim().isEmpty ||
          requisition.lines.isEmpty) {
        throw const InventoryException(
          'The inventory contains an invalid store requisition.',
          code: 'invalid_inventory',
        );
      }
      for (final line in requisition.lines) {
        if (line.productId.trim().isEmpty ||
            line.productName.trim().isEmpty ||
            line.quantity <= 0 ||
            line.unitCostMinor < 0 ||
            line.unit.trim().isEmpty) {
          throw const InventoryException(
            'The inventory contains an invalid requisition item.',
            code: 'invalid_inventory',
          );
        }
      }
      if (requisition.status.index >= RequisitionStatus.approved.index &&
          requisition.approvedBy?.trim().isEmpty != false) {
        throw const InventoryException(
          'Reviewed requisitions must record who approved them.',
          code: 'invalid_inventory',
        );
      }
      if (requisition.status.index >= RequisitionStatus.issued.index &&
          requisition.status != RequisitionStatus.rejected &&
          (requisition.issuedBy?.trim().isEmpty != false ||
              requisition.issuedAt == null)) {
        throw const InventoryException(
          'Issued requisitions must record who issued them and when.',
          code: 'invalid_inventory',
        );
      }
      if (requisition.status == RequisitionStatus.received &&
          (requisition.receivedBy?.trim().isEmpty != false ||
              requisition.receivedAt == null)) {
        throw const InventoryException(
          'Received requisitions must record who received them and when.',
          code: 'invalid_inventory',
        );
      }
    }
    if (data.settings.storeName.trim().isEmpty ||
        data.settings.currencyCode.trim().isEmpty ||
        data.settings.currencySymbol.trim().isEmpty ||
        data.settings.currencyDecimalDigits < 0 ||
        data.settings.currencyDecimalDigits > 4 ||
        data.settings.defaultLowStockThreshold < 0 ||
        !StoreSettings.allowedThemeModes.contains(data.settings.themeMode)) {
      throw const InventoryException(
        'The inventory contains invalid store settings.',
        code: 'invalid_inventory',
      );
    }
  }

  static void _validateMoney(int value, String label) {
    if (value < 0) {
      throw InventoryException(
        '$label cannot be negative.',
        code: 'invalid_money_value',
      );
    }
  }

  static String _cleanRequired(
    String value,
    String label, {
    required int maxLength,
  }) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      throw InventoryException('Enter a $label.', code: 'missing_value');
    }
    if (clean.length > maxLength) {
      throw InventoryException(
        '$label must be $maxLength characters or fewer.',
        code: 'value_too_long',
      );
    }
    return clean;
  }

  static String? _cleanOptional(
    String? value,
    String label, {
    required int maxLength,
  }) {
    if (value == null || value.trim().isEmpty) return null;
    return _cleanRequired(value, label, maxLength: maxLength);
  }

  static int _weightedAverageCost(
    int existingQuantity,
    int existingCost,
    int addedQuantity,
    int addedCost,
  ) {
    final totalQuantity = existingQuantity + addedQuantity;
    if (totalQuantity <= 0) return 0;
    final totalValue =
        BigInt.from(existingQuantity) * BigInt.from(existingCost) +
        BigInt.from(addedQuantity) * BigInt.from(addedCost);
    final divisor = BigInt.from(totalQuantity);
    return ((totalValue + (divisor ~/ BigInt.two)) ~/ divisor).toInt();
  }

  static bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static DateTime _validateStockDate(
    DateTime selected,
    DateTime now,
    String label,
  ) {
    final selectedDay = _localCalendarDay(selected);
    final today = _localCalendarDay(now);
    if (selectedDay.isAfter(today)) {
      throw InventoryException(
        '$label cannot be in the future. Choose today or an earlier day.',
        code: 'future_stock_date',
      );
    }
    return selected;
  }

  static DateTime _localCalendarDay(DateTime date) {
    final localDate = date.toLocal();
    return DateTime(localDate.year, localDate.month, localDate.day);
  }

  static final Random _random = Random.secure();
  static int _idCounter = 0;

  static String _newId(String prefix) {
    _idCounter = (_idCounter + 1) & 0x7fffffff;
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final counter = _idCounter.toRadixString(36).padLeft(4, '0');
    final random = List<String>.generate(
      3,
      (_) => _random.nextInt(0x7fffffff).toRadixString(36).padLeft(6, '0'),
    ).join();
    return '${prefix}_$time$counter$random';
  }

  static String _newReceiptNumber(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final datePart =
        '${date.year}${twoDigits(date.month)}${twoDigits(date.day)}';
    final suffix = _newId('r').split('_').last;
    return 'SP-$datePart-${suffix.substring(suffix.length - 6).toUpperCase()}';
  }

  static InventoryException _friendlyException(
    Object error,
    String fallbackMessage,
  ) {
    if (error is InventoryException) return error;
    return InventoryException(fallbackMessage, code: 'unexpected_error');
  }

  void _ensureActive() {
    if (_disposed) {
      throw const InventoryException(
        'Inventory is no longer available.',
        code: 'controller_disposed',
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _MutationPlan<T> {
  const _MutationPlan(this.data, this.value, {this.clearStore = false});

  final InventoryData data;
  final T value;
  final bool clearStore;
}
