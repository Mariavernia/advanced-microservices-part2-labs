package com.advancedorders.inventory.domain;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class InventoryCatalogTest {
    private final InventoryCatalog catalog = new InventoryCatalog();

    @Test
    void returnsKnownSku() {
        InventoryItem item = catalog.findBySku("sku-001").orElseThrow();

        assertThat(item.sku()).isEqualTo("SKU-001");
        assertThat(item.available()).isEqualTo(42);
    }

    @Test
    void returnsEmptyForUnknownSku() {
        assertThat(catalog.findBySku("DOES-NOT-EXIST")).isEmpty();
    }
}
