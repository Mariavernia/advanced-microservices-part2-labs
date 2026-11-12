package com.advancedorders.payments.api;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Read-only integration contract. No charge or payment authorization occurs in P01. */
@RestController
@RequestMapping("/api/payments")
public class PaymentsController {
    public record PaymentMethodsResponse(String currency, List<String> methods, boolean chargingEnabled) {}

    @GetMapping("/methods")
    public PaymentMethodsResponse methods() {
        return new PaymentMethodsResponse("EUR", List.of("CARD_TEST", "TRANSFER_TEST"), false);
    }
}
