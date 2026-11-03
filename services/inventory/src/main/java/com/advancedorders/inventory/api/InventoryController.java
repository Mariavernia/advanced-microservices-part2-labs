package com.advancedorders.inventory.api;

import com.advancedorders.inventory.domain.InventoryCatalog;
import com.advancedorders.inventory.domain.InventoryItem;
import com.advancedorders.inventory.support.InstanceMetadata;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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
