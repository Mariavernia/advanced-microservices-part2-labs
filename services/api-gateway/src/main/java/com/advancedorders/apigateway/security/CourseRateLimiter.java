package com.advancedorders.apigateway.security;

import java.util.HashMap;
import java.util.Map;
import java.util.function.LongSupplier;

/**
 * Bounded, per-process fixed-window limiter for the training lab.
 * One window for all subjects; no distributed state or production DDoS guarantees.
 */
final class CourseRateLimiter {
    record Decision(boolean allowed, long retryAfterSeconds) {}
    private static final int MAX_SUBJECTS = 128;
    private final int limit;
    private final long windowNanos;
    private final LongSupplier clock;
    private final Map<String, Integer> counts = new HashMap<>();
    private long windowStart;

    CourseRateLimiter(int limit, int seconds, LongSupplier clock) {
        if (limit < 1 || limit > 100 || seconds < 1 || seconds > 60) {
            throw new IllegalArgumentException("rate limit: requests 1..100, window seconds 1..60");
        }
        this.limit = limit;
        this.windowNanos = seconds * 1_000_000_000L;
        this.clock = clock;
        this.windowStart = clock.getAsLong();
    }

    synchronized Decision acquire(String subject) {
        long now = clock.getAsLong();
        long elapsed = now - windowStart;
        if (elapsed >= windowNanos) {
            windowStart = now;
            counts.clear();
            elapsed = 0;
        }
        int count = counts.getOrDefault(subject, 0);
        if (count >= limit || (!counts.containsKey(subject) && counts.size() >= MAX_SUBJECTS)) {
            long remaining = Math.max(1, windowNanos - elapsed);
            return new Decision(false, (remaining + 999_999_999L) / 1_000_000_000L);
        }
        counts.put(subject, count + 1);
        return new Decision(true, 0);
    }
}
