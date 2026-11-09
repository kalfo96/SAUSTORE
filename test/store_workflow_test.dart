import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/data/inventory_store.dart';
import 'package:stockpilot/models/inventory_models.dart';
import 'package:stockpilot/state/inventory_controller.dart';

void main() {
  final today = DateTime(2026, 11, 9);
  late InventoryController controller;
  late Product product;

  setUp(() async {
    controller = InventoryController(
      MemoryInventoryStore(),
      clock: () => today,
    )..setCurrentActor('Store keeper');
    await controller.load();
    product = await controller.addProduct(
      const ProductDraft(
        name: 'Rice',
        sku: 'RICE-001',
        category: 'Kitchen',
        unit: 'kg',
        initialStock: 10,
        unitCostMinor: 1200,
      ),
    );
  });

  tearDown(() => controller.dispose());

  test('requisition follows request, approval, issue and receipt', () async {
    final requisition = await controller.createRequisition(
      department: HotelDepartment.housekeeping,
      requestedBy: 'Amina',
      items: [SaleItemInput(productId: product.id, quantity: 4)],
      note: 'Guest room supplies',
    );
    expect(requisition.status, RequisitionStatus.requested);
    expect(controller.productById(product.id)!.quantity, 10);

    final approved = await controller.approveRequisition(
      requisition.id,
      approvedBy: 'Manager',
    );
    expect(approved.approvedBy, 'Manager');
    expect(approved.status, RequisitionStatus.approved);

    final issued = await controller.issueRequisition(
      requisition.id,
      issuedBy: 'Store keeper',
    );
    expect(issued.status, RequisitionStatus.issued);
    expect(controller.productById(product.id)!.quantity, 6);
    expect(controller.departmentIssues.single.department,
        HotelDepartment.housekeeping);
    expect(controller.movements.last.actorName, 'Store keeper');

    final received = await controller.confirmRequisitionReceived(
      requisition.id,
      receivedBy: 'Amina',
    );
    expect(received.status, RequisitionStatus.received);
    expect(received.receivedBy, 'Amina');
    expect(controller.snapshot.requisitions, hasLength(1));
  });

  test('insufficient stock leaves an approved requisition unchanged', () async {
    final requisition = await controller.createRequisition(
      department: HotelDepartment.kitchen,
      requestedBy: 'Chef',
      items: [SaleItemInput(productId: product.id, quantity: 11)],
    );
    await controller.approveRequisition(
      requisition.id,
      approvedBy: 'Manager',
    );

    await expectLater(
      controller.issueRequisition(requisition.id, issuedBy: 'Store keeper'),
      throwsA(
        isA<InventoryException>().having(
          (error) => error.code,
          'code',
          'insufficient_stock',
        ),
      ),
    );
    expect(controller.productById(product.id)!.quantity, 10);
    expect(controller.requisitions.single.status, RequisitionStatus.approved);
    expect(controller.departmentIssues, isEmpty);
  });

  test('GRN metadata and mandatory adjustment reasons are kept in audit', () async {
    await controller.restockProduct(
      product.id,
      5,
      1500,
      supplierName: 'Hotel Supplies Ltd',
      invoiceNumber: 'INV-204',
      receivedAt: today,
      expiryDate: DateTime(2027, 4, 1),
    );
    final receipt = controller.movements.last;
    expect(receipt.supplierName, 'Hotel Supplies Ltd');
    expect(receipt.invoiceNumber, 'INV-204');
    expect(receipt.expiryDate, DateTime(2027, 4, 1));

    await expectLater(
      controller.adjustStock(product.id, 14),
      throwsA(
        isA<InventoryException>().having(
          (error) => error.code,
          'code',
          'missing_value',
        ),
      ),
    );
    await controller.adjustStock(
      product.id,
      14,
      note: 'Damaged: one bag torn',
    );
    expect(controller.movements.last.note, 'Damaged: one bag torn');
    expect(controller.movements.last.actorName, 'Store keeper');
  });
}
