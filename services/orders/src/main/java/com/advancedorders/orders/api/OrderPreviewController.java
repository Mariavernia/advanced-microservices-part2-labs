package com.advancedorders.orders.api;

import com.advancedorders.orders.service.OrderPreviewService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/orders")
public class OrderPreviewController {
    private final OrderPreviewService orderPreviewService;

    public OrderPreviewController(OrderPreviewService orderPreviewService) {
        this.orderPreviewService = orderPreviewService;
    }

    @GetMapping("/preview")
    public OrderPreviewResponse preview(
            @RequestParam String sku,
            @RequestParam int quantity) {
        return orderPreviewService.preview(sku, quantity);
    }
}
