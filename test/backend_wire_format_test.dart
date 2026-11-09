import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockpilot/models/inventory_models.dart';

import '../tool/ui_preview.dart';

bool get hasPhp {
  try {
    return Process.runSync('php', ['-n', '-v']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PHP accepts actual Flutter receipts, requisitions, usage and report JSON',
    () async {
      final controller = await createPreviewController();
      final water = controller.products.firstWhere(
        (product) => product.sku == 'REST-WATER',
      );
      await controller.restockProduct(
        water.id,
        2,
        2800,
        supplierName: 'Interop Supplier',
        invoiceNumber: 'GRN-TEST-1',
        expiryDate: DateTime.now().add(const Duration(days: 60)),
      );
      final requisition = await controller.createRequisition(
        department: HotelDepartment.housekeeping,
        requestedBy: 'Interop requester',
        items: [SaleItemInput(productId: water.id, quantity: 1)],
      );
      await controller.approveRequisition(
        requisition.id,
        approvedBy: 'Interop manager',
      );
      await controller.issueRequisition(
        requisition.id,
        issuedBy: 'Interop store keeper',
      );
      await controller.confirmRequisitionReceived(
        requisition.id,
        receivedBy: 'Interop receiver',
      );
      final sale = await controller.recordSale([
        SaleItemInput(productId: water.id, quantity: 1, unitPriceMinor: 3200),
        SaleItemInput(productId: water.id, quantity: 2, unitPriceMinor: 3200),
      ]);
      await controller.voidSale(sale.id, reason: 'Interop test reversal');
      await controller.submitDailyReport(day: DateTime.now());
      final validator = File(
        'backend/private/lib/Validation.php',
      ).absolute.path;
      final process = await Process.start('php', [
        '-n',
        '-r',
        r'require $argv[1]; $data = json_decode(stream_get_contents(STDIN), false, 64, JSON_THROW_ON_ERROR); DreamStore\InventoryValidator::validate($data); echo "valid";',
        validator,
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      process.stdin.write(controller.exportJson());
      await process.stdin.close();
      final exitCode = await process.exitCode;
      final stdout = await output;
      final stderr = await errors;
      expect(exitCode, 0, reason: '$stdout\n$stderr');
      expect(stdout, 'valid');
    },
    skip: hasPhp ? false : 'PHP CLI unavailable; run on a PHP-enabled machine.',
  );
}
