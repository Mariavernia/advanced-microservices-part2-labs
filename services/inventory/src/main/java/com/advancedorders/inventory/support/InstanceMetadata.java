package com.advancedorders.inventory.support;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class InstanceMetadata {
    private final String instanceName;
    private final String serviceVersion;

    public InstanceMetadata(
            @Value("${HOSTNAME:inventory-local}") String instanceName,
            @Value("${app.version:dev}") String serviceVersion) {
        this.instanceName = instanceName;
        this.serviceVersion = serviceVersion;
    }

    public String instanceName() {
        return instanceName;
    }

    public String serviceVersion() {
        return serviceVersion;
    }
}
