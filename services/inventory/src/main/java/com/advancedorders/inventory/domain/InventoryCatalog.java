package com.advancedorders.inventory.domain;

import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Optional;

@Component
public class InventoryCatalog {
    private final Map<String, InventoryItem> items = Map.of(
            "SKU-001", new InventoryItem("SKU-001", 42, 0),
            "SKU-002", new InventoryItem("SKU-002", 7, 1),
            "SKU-003", new InventoryItem("SKU-003", 0, 0)
    );

    public Optional<InventoryItem> findBySku(String sku) {
        if (sku == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(items.get(sku.trim().toUpperCase()));
    }
}
