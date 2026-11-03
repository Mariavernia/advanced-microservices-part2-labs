package com.advancedorders.orders.service;

import com.advancedorders.orders.api.OrderPreviewResponse;
import com.advancedorders.orders.client.InventoryClient;
import com.advancedorders.orders.client.InventorySnapshot;
import com.advancedorders.orders.config.InventoryClientProperties;
import com.advancedorders.orders.support.InstanceMetadata;
import org.junit.jupiter.api.Test;

import java.net.URI;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class OrderPreviewServiceTest {

    @Test
    void reportsFulfillableOrder() {
        InventoryClient client = mock(InventoryClient.class);
        when(client.getInventory("SKU-001"))
                .thenReturn(new InventorySnapshot("SKU-001", 42, 0, "inventory-abc", "0.1.0"));

        OrderPreviewService service = new OrderPreviewService(
                client,
                new InventoryClientProperties(URI.create("http://inventory:8080")),
                new InstanceMetadata("orders-xyz", "0.1.0"));

        OrderPreviewResponse result = service.preview("SKU-001", 2);

        assertThat(result.canBeFulfilled()).isTrue();
        assertThat(result.inventoryAvailable()).isEqualTo(42);
        assertThat(result.servedBy()).isEqualTo("orders-xyz");
        assertThat(result.inventoryServedBy()).isEqualTo("inventory-abc");
    }

    @Test
    void rejectsNonPositiveQuantity() {
        InventoryClient client = mock(InventoryClient.class);
        OrderPreviewService service = new OrderPreviewService(
                client,
                new InventoryClientProperties(URI.create("http://inventory:8080")),
                new InstanceMetadata("orders-xyz", "0.1.0"));

        assertThatThrownBy(() -> service.preview("SKU-001", 0))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("greater than zero");
    }
}
