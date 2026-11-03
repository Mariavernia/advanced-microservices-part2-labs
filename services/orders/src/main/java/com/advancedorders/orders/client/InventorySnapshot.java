package com.advancedorders.orders.client;

public record InventorySnapshot(
        String sku,
        int available,
        int reserved,
        String servedBy,
        String serviceVersion) {
}
