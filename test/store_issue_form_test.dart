import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/models/inventory_models.dart';
import 'package:stockpilot/services/store_issue_form.dart';

void main() {
  test('blank store issue form generates a printable PDF', () async {
    final bytes = await buildStoreIssueFormPdf();
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test(
    'requisition form includes requested items and approval names',
    () async {
      final requisition = StoreRequisition(
        id: 'REQ-2026-001',
        department: HotelDepartment.housekeeping,
        requestedBy: 'Amina',
        requestedAt: DateTime(2026, 11, 9),
        status: RequisitionStatus.received,
        lines: const [
          RequisitionLine(
            productId: 'item-1',
            productName: 'Laundry detergent',
            productSku: 'DET-001',
            quantity: 3,
            unitCostMinor: 1200,
            unit: 'kg',
          ),
        ],
        approvedBy: 'Manager',
        issuedBy: 'Storekeeper',
        receivedBy: 'Amina',
      );
      final bytes = await buildStoreIssueFormPdf(requisition: requisition);
      expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes, isNot(equals(await buildStoreIssueFormPdf())));
    },
  );
}
