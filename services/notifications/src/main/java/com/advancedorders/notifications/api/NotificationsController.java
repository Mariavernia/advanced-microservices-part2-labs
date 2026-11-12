package com.advancedorders.notifications.api;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/** Template preview; no email, SMS or notification is sent. */
@RestController
@RequestMapping("/api/notifications")
public class NotificationsController {
    private final boolean credentialConfigured;
    private final String providerMode;
    public NotificationsController(
            @Value("${NOTIFICATION_PROVIDER_TOKEN:}") String token,
            @Value("${NOTIFICATION_PROVIDER_MODE:simulated}") String providerMode) {
        this.credentialConfigured = !token.isBlank();
        this.providerMode = providerMode;
    }
    public record ProviderStatus(String mode, boolean credentialConfigured, boolean deliveryEnabled) {}
    public record TemplatePreview(String template, String channel, String subject, String sampleBody) {}

    @GetMapping("/provider")
    public ProviderStatus provider() {
        return new ProviderStatus(providerMode, credentialConfigured, false);
    }
    @GetMapping("/templates/{template}")
    public TemplatePreview preview(@PathVariable String template) {
        if (!template.equals("order-confirmed")) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown template");
        }
        return new TemplatePreview(template, "EMAIL", "Pedido confirmado",
            "Tu pedido de prueba ha sido registrado (vista previa; no se ha enviado)");
    }
}
