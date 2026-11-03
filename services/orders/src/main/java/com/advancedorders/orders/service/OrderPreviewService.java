package com.advancedorders.orders.service;

import com.advancedorders.orders.api.OrderPreviewResponse;
import com.advancedorders.orders.client.InventoryClient;
import com.advancedorders.orders.client.InventorySnapshot;
import com.advancedorders.orders.config.InventoryClientProperties;
import com.advancedorders.orders.support.InstanceMetadata;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class OrderPreviewService {
    private static final Logger log = LoggerFactory.getLogger(OrderPreviewService.class);

    private final InventoryClient inventoryClient;
    private final InventoryClientProperties inventoryProperties;
    private final InstanceMetadata instanceMetadata;

    public OrderPreviewService(
            InventoryClient inventoryClient,
            InventoryClientProperties inventoryProperties,
            InstanceMetadata instanceMetadata) {
        this.inventoryClient = inventoryClient;
        this.inventoryProperties = inventoryProperties;
        this.instanceMetadata = instanceMetadata;
    }

    public OrderPreviewResponse preview(String sku, int quantity) {
        if (quantity < 1) {
            throw new IllegalArgumentException("quantity must be greater than zero");
        }

        log.info("Calling Inventory baseUrl={} sku={} quantity={}",
                inventoryProperties.baseUrl(), sku, quantity);

        InventorySnapshot inventory = inventoryClient.getInventory(sku);
        boolean canBeFulfilled = inventory.available() >= quantity;

        log.info("Order preview sku={} quantity={} inventoryAvailable={} canBeFulfilled={}",
                inventory.sku(), quantity, inventory.available(), canBeFulfilled);

        return new OrderPreviewResponse(
                inventory.sku(),
                quantity,
                canBeFulfilled,
                inventory.available(),
                instanceMetadata.instanceName(),
                inventory.servedBy(),
                instanceMetadata.serviceVersion());
    }
}
