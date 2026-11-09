package com.advancedorders.shipping.api;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/** Deterministic quote simulator. Real carrier integration is introduced later. */
@RestController
@RequestMapping("/api/shipping")
public class ShippingController {
    public record ShippingQuote(String destination, int weightGrams, long priceCents,
                                String currency, int estimatedDays, String provider) {}

    @GetMapping("/quote")
    public ShippingQuote quote(@RequestParam(defaultValue = "ES") String destination,
                                @RequestParam(defaultValue = "500") int weightGrams) {
        if (!destination.matches("[A-Z]{2}") || weightGrams < 1 || weightGrams > 10000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid destination or weightGrams");
        }
        boolean domestic = destination.equals("ES");
        long price = domestic ? (weightGrams <= 2000 ? 499 : 899) : 1499;
        return new ShippingQuote(destination, weightGrams, price, "EUR", domestic ? 3 : 7, "SIMULATED");
    }
}
