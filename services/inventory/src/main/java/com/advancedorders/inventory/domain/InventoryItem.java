package com.advancedorders.inventory.domain;

public record InventoryItem(String sku, int available, int reserved) {
}
