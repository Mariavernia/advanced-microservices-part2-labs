package com.advancedorders.inventory.api;

import com.advancedorders.inventory.domain.InventoryCatalog;
import com.advancedorders.inventory.domain.InventoryItem;
import com.advancedorders.inventory.support.InstanceMetadata;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/inventory")
public class InventoryController {
    private static final Logger log = LoggerFactory.getLogger(InventoryController.class);

    // P07 training-only fault: disabled by default, bounded to 3 seconds.
    @Value("${training.inventory.delay-ms:0}")
    private long trainingDelayMs;

    private final InventoryCatalog catalog;
    private final InstanceMetadata instanceMetadata;

    public InventoryController(InventoryCatalog catalog, InstanceMetadata instanceMetadata) {
        this.catalog = catalog;
        this.instanceMetadata = instanceMetadata;
    }

    @GetMapping("/{sku}")
    public InventoryResponse getInventory(@PathVariable String sku) {
        InventoryItem item = catalog.findBySku(sku)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Unknown SKU: " + sku));

        long delay = Math.max(0, Math.min(3000, trainingDelayMs));
        if (delay > 0) {
            log.warn("P07 simulated dependency latency sku={} delayMs={}", sku, delay);
            try {
                Thread.sleep(delay);
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                        "Training delay interrupted", ex);
            }
        }

        log.info("Inventory lookup sku={} available={} reserved={}",
                item.sku(), item.available(), item.reserved());

        return new InventoryResponse(
                item.sku(),
                item.available(),
                item.reserved(),
                instanceMetadata.instanceName(),
                instanceMetadata.serviceVersion());
    }
}
