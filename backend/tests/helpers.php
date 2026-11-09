<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/private/lib/App.php';

function inventory_fixture(): stdClass
{
    return json_decode(<<<'JSON'
{
  "schemaVersion": 3,
  "products": [{
    "id": "p1", "name": "Rice", "sku": "KIT-RICE", "category": "Dry goods",
    "department": "kitchen", "description": "", "quantity": 17,
    "unitCostMinor": 2000, "salePriceMinor": 2500, "lowStockThreshold": 5,
    "isArchived": false, "createdAt": "2026-09-13T08:00:00.000",
    "updatedAt": "2026-09-13T09:00:00.000", "receivedAt": "2026-09-12T00:00:00.000"
  }],
  "sales": [],
  "movements": [{
    "id": "m1", "productId": "p1", "productName": "Rice", "productSku": "KIT-RICE",
    "department": "kitchen", "type": "opening", "quantityDelta": 20,
    "quantityBefore": 0, "quantityAfter": 20, "unitCostMinor": 2000,
    "occurredAt": "2026-09-12T00:00:00.000", "recordedAt": "2026-09-13T08:00:00.000"
  }, {
    "id": "m2", "productId": "p1", "productName": "Rice", "productSku": "KIT-RICE",
    "department": "kitchen", "type": "departmentIssue", "quantityDelta": -3,
    "quantityBefore": 20, "quantityAfter": 17, "unitCostMinor": 2000,
    "occurredAt": "2026-09-12T00:00:00.000", "recordedAt": "2026-09-13T09:00:00.000"
  }],
  "departmentIssues": [{
    "id": "i1", "productId": "p1", "productName": "Rice", "productSku": "KIT-RICE",
    "department": "kitchen", "quantity": 3, "unitCostMinor": 2000,
    "issuedAt": "2026-09-12T00:00:00.000", "note": "Lunch preparation"
  }],
  "dailyReports": [{
    "id": "r1", "day": "2026-09-12T00:00:00.000", "submittedAt": "2026-09-13T10:00:00.000",
    "totalUnits": 3, "totalValueMinor": 6000
  }],
  "settings": {
    "storeName": "Sau Inn", "currencyCode": "TZS", "currencySymbol": "TSh",
    "currencyDecimalDigits": 0, "defaultLowStockThreshold": 5, "themeMode": "system"
  }
}
JSON, false, 64, JSON_THROW_ON_ERROR);
}

function test_assert(bool $condition, string $message): void
{
    if (!$condition) throw new RuntimeException($message);
}

function expect_invalid(callable $call, string $label): void
{
    try {
        $call();
    } catch (InvalidArgumentException) {
        return;
    }
    throw new RuntimeException("Expected invalid input: $label");
}
