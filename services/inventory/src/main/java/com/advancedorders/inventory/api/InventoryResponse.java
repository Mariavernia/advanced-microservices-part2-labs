package com.advancedorders.inventory.api;

public record InventoryResponse(
        String sku,
        int available,
        int reserved,
        String servedBy,
        String serviceVersion) {
}
