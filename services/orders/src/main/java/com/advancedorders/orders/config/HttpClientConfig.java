package com.advancedorders.orders.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration
@EnableConfigurationProperties(InventoryClientProperties.class)
public class HttpClientConfig {

    @Bean
    RestClient inventoryRestClient(RestClient.Builder builder, InventoryClientProperties properties) {
        return builder.baseUrl(properties.baseUrl().toString()).build();
    }
}
