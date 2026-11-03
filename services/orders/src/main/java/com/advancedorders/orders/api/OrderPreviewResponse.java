package com.advancedorders.orders.api;

public record OrderPreviewResponse(
        String sku,
        int quantity,
        boolean canBeFulfilled,
        int inventoryAvailable,
        String servedBy,
        String inventoryServedBy,
        String serviceVersion) {
}
