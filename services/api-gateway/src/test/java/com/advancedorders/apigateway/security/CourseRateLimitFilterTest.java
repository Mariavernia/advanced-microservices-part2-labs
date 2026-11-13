package com.advancedorders.apigateway.security;

import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;
import static org.assertj.core.api.Assertions.assertThat;

class CourseRateLimitFilterTest {
    private ServerWebExchange request(String subject, String path) {
        var exchange = MockServerWebExchange.from(MockServerHttpRequest.get(path).build());
        var jwt = Jwt.withTokenValue("synthetic").header("alg", "RS256")
                .subject(subject).build();
        return exchange.mutate().principal(Mono.just(new JwtAuthenticationToken(jwt, List.of()))).build();
    }

    @Test
    void limitsOnlyOrdersAndSeparatesAuthenticatedSubjects() {
        var filter = new CourseRateLimitFilter(1, 60);
        var calls = new AtomicInteger();
        var first = request("reader", "/api/orders/preview");
        filter.filter(first, ex -> { calls.incrementAndGet(); return Mono.empty(); }).block();
        var second = request("reader", "/api/orders/preview");
        filter.filter(second, ex -> { calls.incrementAndGet(); return Mono.empty(); }).block();
        assertThat(second.getResponse().getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        assertThat(second.getResponse().getHeaders().getFirst("Retry-After")).isNotBlank();
        var admin = request("admin", "/api/orders/preview");
        filter.filter(admin, ex -> { calls.incrementAndGet(); return Mono.empty(); }).block();
        var other = request("reader", "/api/payments/methods");
        filter.filter(other, ex -> { calls.incrementAndGet(); return Mono.empty(); }).block();
        assertThat(calls.get()).isEqualTo(3);
    }

    @Test
    void missingPrincipalCannotReachProtectedRoute() {
        var filter = new CourseRateLimitFilter(3, 10);
        var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/orders/preview").build());
        filter.filter(exchange, ex -> Mono.error(new AssertionError("unexpected upstream"))).block();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }
}
