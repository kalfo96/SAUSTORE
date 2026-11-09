<?php
declare(strict_types=1);

namespace DreamStore;

use DateTimeImmutable;
use InvalidArgumentException;
use stdClass;

/** Strictly validate the Dart InventoryData wire format without dropping fields. */
final class InventoryValidator
{
    public const MAX_SAFE_INTEGER = 9007199254740991;
    private const DEPARTMENTS = [
        'kitchen', 'housekeeping', 'laundry', 'maintenance', 'reception',
        'office', 'publicArea', 'restaurant', 'pool', 'security',
    ];
    private const MOVEMENTS = ['opening', 'restock', 'sale', 'departmentIssue', 'adjustment', 'reversal'];

    public static function validate(mixed $data): stdClass
    {
        $root = self::object($data, 'inventory');
        $schema = self::integer($root, 'schemaVersion', 1, 4);
        $products = self::items($root, 'products');
        $sales = self::items($root, 'sales');
        $movements = self::items($root, 'movements');
        $issues = self::items($root, 'departmentIssues', $schema < 2);
        $reports = self::items($root, 'dailyReports', $schema < 2);
        $requisitions = self::items($root, 'requisitions', $schema < 4);
        $productIds = [];
        $skus = [];
        $saleIds = [];
        $receipts = [];
        $inventoryValue = 0;
        foreach ($products as $value) {
            $p = self::object($value, 'product');
            self::unique(self::text($p, 'id', 160), $productIds, 'product ID');
            $sku = strtoupper(trim(self::text($p, 'sku', 160)));
            $sku = preg_replace('/\s+/', '-', $sku);
            $sku = preg_replace('/-{2,}/', '-', $sku);
            self::unique($sku, $skus, 'SKU');
            self::text($p, 'name', 240);
            self::text($p, 'category', 160);
            if ($schema >= 4) self::text($p, 'unit', 24);
            elseif (isset($p->unit)) self::text($p, 'unit', 24);
            self::text($p, 'description', 8000, true);
            self::department($p, 'department', $schema < 2);
            $quantity = self::integer($p, 'quantity');
            $cost = self::money($p, 'unitCostMinor', 'costPriceMinor');
            self::money($p, 'salePriceMinor', 'sellingPriceMinor');
            self::integer($p, 'lowStockThreshold');
            self::boolean($p, 'isArchived');
            self::date($p, 'createdAt');
            self::date($p, 'updatedAt', $schema < 3);
            self::date($p, 'receivedAt', true);
            $inventoryValue = self::safeAdd($inventoryValue, self::safeMultiply($quantity, $cost));
        }
        foreach ($sales as $value) {
            $sale = self::object($value, 'sale');
            self::unique(self::text($sale, 'id', 160), $saleIds, 'sale ID');
            self::unique(strtolower(self::text($sale, 'receiptNumber', 240)), $receipts, 'receipt number');
            self::text($sale, 'paymentMethod', 160);
            self::optionalText($sale, ['reference', 'customerName', 'voidReason']);
            self::date($sale, 'createdAt');
            self::boolean($sale, 'isVoided');
            self::date($sale, 'voidedAt', true);
            if ($sale->isVoided && !isset($sale->voidedAt)) {
                self::fail('A voided sale needs its reversal date.');
            }
            $lines = self::items($sale, 'lines');
            if ($lines === []) self::fail('A sale needs at least one item.');
            $lineIds = [];
            $total = 0;
            $totalCost = 0;
            foreach ($lines as $value) {
                $line = self::object($value, 'sale item');
                self::reference($line, 'productId', $productIds);
                self::unique($line->productId, $lineIds, 'sale item product');
                self::text($line, 'productName', 240);
                self::text($line, 'productSku', 160, true);
                $quantity = self::integer($line, 'quantity', 1);
                $total = self::safeAdd($total, self::safeMultiply($quantity, self::integer($line, 'unitPriceMinor')));
                $totalCost = self::safeAdd($totalCost, self::safeMultiply($quantity, self::integer($line, 'unitCostMinor')));
            }
        }
        $movementIds = [];
        foreach ($movements as $value) {
            $movement = self::object($value, 'stock movement');
            self::unique(self::text($movement, 'id', 160), $movementIds, 'movement ID');
            self::reference($movement, 'productId', $productIds);
            self::text($movement, 'productName', 240);
            self::text($movement, 'productSku', 160, true);
            $type = self::text($movement, 'type', 40);
            if (!in_array($type, self::MOVEMENTS, true)) self::fail('Unknown stock movement type.');
            $delta = self::integer($movement, 'quantityDelta', -self::MAX_SAFE_INTEGER);
            $before = self::integer($movement, 'quantityBefore');
            $after = self::integer($movement, 'quantityAfter');
            if ($after - $before !== $delta) self::fail('Stock movement quantities do not balance.');
            if (in_array($type, ['opening', 'restock', 'reversal'], true) && $delta <= 0) self::fail('Stock additions must be positive.');
            if (in_array($type, ['sale', 'departmentIssue'], true) && $delta >= 0) self::fail('Stock usage must reduce quantity.');
            if ($type === 'opening' && $before !== 0) self::fail('Opening stock must start at zero.');
            self::safeMultiply(abs($delta), self::integer($movement, 'unitCostMinor'));
            self::date($movement, 'occurredAt');
            self::date($movement, 'recordedAt', true);
            self::department($movement, 'department', true);
            self::optionalText($movement, ['note']);
            self::optionalText($movement, ['supplierName', 'invoiceNumber', 'actorName']);
            self::date($movement, 'expiryDate', true);
            if (isset($movement->relatedSaleId)) self::reference($movement, 'relatedSaleId', $saleIds);
        }
        $issueIds = [];
        foreach ($issues as $value) {
            $issue = self::object($value, 'department usage');
            self::unique(self::text($issue, 'id', 160), $issueIds, 'usage ID');
            self::reference($issue, 'productId', $productIds);
            self::department($issue, 'department');
            self::text($issue, 'productName', 240);
            self::text($issue, 'productSku', 160, true);
            self::safeMultiply(self::integer($issue, 'quantity', 1), self::integer($issue, 'unitCostMinor'));
            self::date($issue, 'issuedAt');
            self::optionalText($issue, ['note']);
        }
        $reportIds = [];
        $reportDays = [];
        foreach ($reports as $value) {
            $report = self::object($value, 'daily report');
            self::unique(self::text($report, 'id', 160), $reportIds, 'report ID');
            self::date($report, 'day');
            self::unique(substr($report->day, 0, 10), $reportDays, 'report day');
            self::date($report, 'submittedAt');
            self::integer($report, 'totalUnits');
            self::integer($report, 'totalValueMinor');
            self::optionalText($report, ['note']);
        }
        $requisitionIds = [];
        foreach ($requisitions as $value) {
            $requisition = self::object($value, 'store requisition');
            self::unique(self::text($requisition, 'id', 160), $requisitionIds, 'requisition ID');
            self::department($requisition, 'department');
            self::text($requisition, 'requestedBy', 100);
            self::date($requisition, 'requestedAt');
            $status = self::text($requisition, 'status', 20);
            if (!in_array($status, ['requested', 'approved', 'issued', 'received', 'rejected'], true)) self::fail('Unknown requisition status.');
            self::optionalText($requisition, ['approvedBy', 'issuedBy', 'receivedBy', 'note']);
            self::date($requisition, 'approvedAt', true);
            self::date($requisition, 'issuedAt', true);
            self::date($requisition, 'receivedAt', true);
            $lines = self::items($requisition, 'lines');
            if ($lines === []) self::fail('A requisition needs at least one item.');
            $lineProducts = [];
            foreach ($lines as $value) {
                $line = self::object($value, 'requisition item');
                self::reference($line, 'productId', $productIds);
                self::unique($line->productId, $lineProducts, 'requisition item product');
                self::text($line, 'productName', 240);
                self::text($line, 'productSku', 160, true);
                $quantity = self::integer($line, 'quantity', 1);
                $cost = self::integer($line, 'unitCostMinor');
                if (isset($line->unit)) self::text($line, 'unit', 24);
                self::safeMultiply($quantity, $cost);
            }
            if (in_array($status, ['approved', 'issued', 'received', 'rejected'], true)) {
                self::text($requisition, 'approvedBy', 100);
                self::date($requisition, 'approvedAt');
            }
            if (in_array($status, ['issued', 'received'], true)) {
                self::text($requisition, 'issuedBy', 100);
                self::date($requisition, 'issuedAt');
            }
            if ($status === 'received') {
                self::text($requisition, 'receivedBy', 100);
                self::date($requisition, 'receivedAt');
            }
        }
        $settings = self::object($root->settings ?? null, 'settings');
        self::text($settings, 'storeName', 240);
        self::text($settings, 'currencyCode', 12);
        self::text($settings, 'currencySymbol', 24);
        self::integer($settings, 'currencyDecimalDigits', 0, 4);
        self::integer($settings, 'defaultLowStockThreshold');
        if (isset($settings->themeMode) && !in_array($settings->themeMode, ['system', 'light', 'dark'], true)) self::fail('Invalid display theme.');
        return $root;
    }

    public static function validDate(string $value): bool
    {
        if (!preg_match('/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](\d{2}):?(\d{2}))?$/D', $value, $m)) return false;
        if (!checkdate((int) $m[2], (int) $m[3], (int) $m[1])) return false;
        if ((int) $m[4] > 23 || (int) $m[5] > 59 || (int) $m[6] > 59) return false;
        if (isset($m[7]) && ((int) $m[7] > 14 || (int) $m[8] > 59 || ((int) $m[7] === 14 && (int) $m[8] !== 0))) return false;
        try {
            new DateTimeImmutable($value);
            return true;
        } catch (\Exception) {
            return false;
        }
    }

    public static function object(mixed $value, string $label): stdClass
    {
        if (!$value instanceof stdClass) self::fail("The $label must be a JSON object.");
        return $value;
    }

    public static function integer(stdClass $object, string $field, int $minimum = 0, int $maximum = self::MAX_SAFE_INTEGER): int
    {
        $value = $object->{$field} ?? null;
        if (!is_int($value) || $value < $minimum || $value > $maximum) self::fail("Invalid integer field: $field.");
        return $value;
    }

    private static function items(stdClass $object, string $field, bool $optional = false): array
    {
        if ($optional && !property_exists($object, $field)) return [];
        $value = $object->{$field} ?? null;
        if (!is_array($value) || !array_is_list($value) || count($value) > 100000) self::fail("The $field must be a JSON array.");
        return $value;
    }

    private static function text(stdClass $object, string $field, int $max, bool $allowEmpty = false): string
    {
        $value = $object->{$field} ?? null;
        if (!is_string($value) || strlen($value) > $max || (!$allowEmpty && trim($value) === '') || str_contains($value, "\0")) self::fail("Invalid text field: $field.");
        return $value;
    }

    private static function optionalText(stdClass $object, array $fields): void
    {
        foreach ($fields as $field) if (isset($object->{$field})) self::text($object, $field, 8000, true);
    }

    private static function boolean(stdClass $object, string $field): void
    {
        if (!isset($object->{$field}) || !is_bool($object->{$field})) self::fail("Invalid boolean field: $field.");
    }

    private static function date(stdClass $object, string $field, bool $optional = false): void
    {
        if ($optional && !isset($object->{$field})) return;
        if (!isset($object->{$field}) || !is_string($object->{$field}) || !self::validDate($object->{$field})) self::fail("Invalid date field: $field.");
    }

    private static function department(stdClass $object, string $field, bool $optional = false): void
    {
        if ($optional && !isset($object->{$field})) return;
        if (!isset($object->{$field}) || !in_array($object->{$field}, self::DEPARTMENTS, true)) self::fail('Invalid department.');
    }

    private static function money(stdClass $object, string $field, string $legacy): int
    {
        return self::integer($object, property_exists($object, $field) ? $field : $legacy);
    }

    private static function unique(string $key, array &$seen, string $label): void
    {
        if (isset($seen[$key])) self::fail("Duplicate $label.");
        $seen[$key] = true;
    }

    private static function reference(stdClass $object, string $field, array $ids): void
    {
        $id = self::text($object, $field, 160);
        if (!isset($ids[$id])) self::fail("An inventory record references an unknown $field.");
    }

    private static function safeMultiply(int $quantity, int $money): int
    {
        if ($quantity > 0 && $money > intdiv(self::MAX_SAFE_INTEGER, $quantity)) self::fail('Inventory values exceed safe integer precision.');
        return $quantity * $money;
    }

    private static function safeAdd(int $left, int $right): int
    {
        if ($right > self::MAX_SAFE_INTEGER - $left) self::fail('Inventory totals exceed safe integer precision.');
        return $left + $right;
    }

    private static function fail(string $message): never
    {
        throw new InvalidArgumentException($message);
    }
}
