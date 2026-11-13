package com.advancedorders.apigateway.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.context.annotation.Profile;
import org.springframework.core.Ordered;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

/** Runs in the gateway route chain after the security WebFilter chain. */
@Component
@Profile("p05-security & p05-rate-limit")
public final class CourseRateLimitFilter implements GlobalFilter, Ordered {
    private final CourseRateLimiter limiter;

    public CourseRateLimitFilter(
            @Value("${P05_RATE_LIMIT_REQUESTS:3}") int requests,
            @Value("${P05_RATE_LIMIT_WINDOW_SECONDS:10}") int seconds) {
        this.limiter = new CourseRateLimiter(requests, seconds, System::nanoTime);
    }

    @Override
    public int getOrder() {
        return -1;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        if (!HttpMethod.GET.equals(exchange.getRequest().getMethod())
                || !"/api/orders/preview".equals(exchange.getRequest().getPath().value())) {
            return chain.filter(exchange);
        }
        // Never key a limit by an untrusted header, a raw token or a caller IP.
        return exchange.getPrincipal()
                .ofType(JwtAuthenticationToken.class)
                .filter(JwtAuthenticationToken::isAuthenticated)
                .map(auth -> {
                    String subject = auth.getToken().getSubject();
                    return subject == null ? "" : subject;
                })
                .defaultIfEmpty("")
                .flatMap(subject -> {
                    if (subject.isBlank()) {
                        exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
                        return exchange.getResponse().setComplete();
                    }
                    var decision = limiter.acquire(subject);
                    if (!decision.allowed()) {
                        exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                        exchange.getResponse().getHeaders().set("Retry-After",
                                Long.toString(decision.retryAfterSeconds()));
                        return exchange.getResponse().setComplete();
                    }
                    return chain.filter(exchange);
                });
    }
}
