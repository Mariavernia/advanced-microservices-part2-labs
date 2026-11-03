package com.advancedorders.orders.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.net.URI;

@ConfigurationProperties(prefix = "inventory.client")
public record InventoryClientProperties(URI baseUrl) {
}
