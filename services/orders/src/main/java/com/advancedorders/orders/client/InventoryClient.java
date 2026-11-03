package com.advancedorders.orders.client;

import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Component
public class InventoryClient {
    private final RestClient restClient;

    public InventoryClient(RestClient inventoryRestClient) {
        this.restClient = inventoryRestClient;
    }

    public InventorySnapshot getInventory(String sku) {
        try {
            InventorySnapshot snapshot = restClient.get()
                    .uri("/api/inventory/{sku}", sku)
                    .retrieve()
                    .body(InventorySnapshot.class);

            if (snapshot == null) {
                throw new InventoryUnavailableException("Inventory returned an empty response", null);
            }
            return snapshot;
        } catch (InventoryUnavailableException ex) {
            throw ex;
        } catch (RestClientException ex) {
            throw new InventoryUnavailableException("Inventory call failed for sku=" + sku, ex);
        }
    }
}
