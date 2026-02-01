package com.gruzewskidev.api_service;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantLock;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class EnrichmentCacheService {

	private static final Logger log = LoggerFactory.getLogger(EnrichmentCacheService.class);

	private static final Duration PREMIUM_TTL = Duration.ofSeconds(5);
	private static final Duration STANDARD_TTL = Duration.ofSeconds(60);

	private final ConcurrentHashMap<Long, CachedEnrichment> cache = new ConcurrentHashMap<>();
	private final ConcurrentHashMap<Long, ReentrantLock> locks = new ConcurrentHashMap<>();

	private final ExternalEnrichmentClient enrichmentClient;

	private final Counter cacheHitPremium;
	private final Counter cacheHitStandard;
	private final Counter cacheMissPremium;
	private final Counter cacheMissStandard;
	private final Timer lockWaitPremium;
	private final Timer lockWaitStandard;
	private final Timer refreshPremium;
	private final Timer refreshStandard;

	public EnrichmentCacheService(ExternalEnrichmentClient enrichmentClient, MeterRegistry registry) {
		this.enrichmentClient = enrichmentClient;

		this.cacheHitPremium = Counter.builder("demo.enrichment.cache.hit")
				.tag("userType", "premium")
				.register(registry);
		this.cacheHitStandard = Counter.builder("demo.enrichment.cache.hit")
				.tag("userType", "standard")
				.register(registry);
		this.cacheMissPremium = Counter.builder("demo.enrichment.cache.miss")
				.tag("userType", "premium")
				.register(registry);
		this.cacheMissStandard = Counter.builder("demo.enrichment.cache.miss")
				.tag("userType", "standard")
				.register(registry);
		this.lockWaitPremium = Timer.builder("demo.enrichment.lock.wait")
				.tag("userType", "premium")
				.register(registry);
		this.lockWaitStandard = Timer.builder("demo.enrichment.lock.wait")
				.tag("userType", "standard")
				.register(registry);
		this.refreshPremium = Timer.builder("demo.enrichment.refresh")
				.tag("userType", "premium")
				.register(registry);
		this.refreshStandard = Timer.builder("demo.enrichment.refresh")
				.tag("userType", "standard")
				.register(registry);
	}

	public EnrichmentResponse getEnrichment(long userId) {
		boolean isPremium = userId % 20 == 0;

		CachedEnrichment cached = cache.get(userId);
		if (cached != null && !cached.isExpired()) {
			log.info("userId={} cache_hit=true", userId);
			(isPremium ? cacheHitPremium : cacheHitStandard).increment();
			return cached.value();
		}

		(isPremium ? cacheMissPremium : cacheMissStandard).increment();

		ReentrantLock lock = locks.computeIfAbsent(userId, id -> new ReentrantLock());
		long lockWaitStart = System.nanoTime();
		lock.lock();
		try {
			long lockWaitNanos = System.nanoTime() - lockWaitStart;
			long lockWaitMs = TimeUnit.NANOSECONDS.toMillis(lockWaitNanos);
			(isPremium ? lockWaitPremium : lockWaitStandard).record(lockWaitNanos, TimeUnit.NANOSECONDS);
			log.info("userId={} lockWaitMs={}", userId, lockWaitMs);

			// Double-check after acquiring lock
			cached = cache.get(userId);
			if (cached != null && !cached.isExpired()) {
				log.info("userId={} cache_hit=true (after lock)", userId);
				return cached.value();
			}

			long refreshStart = System.nanoTime();
			EnrichmentResponse response = enrichmentClient.getEnrichment(userId);

			Duration ttl = isPremium ? PREMIUM_TTL : STANDARD_TTL;
			cache.put(userId, new CachedEnrichment(response, Instant.now().plus(ttl)));

			long refreshNanos = System.nanoTime() - refreshStart;
			long refreshMs = TimeUnit.NANOSECONDS.toMillis(refreshNanos);
			(isPremium ? refreshPremium : refreshStandard).record(refreshNanos, TimeUnit.NANOSECONDS);

			log.info("userId={} cache_refresh=true refreshMs={} ttl={}", userId, refreshMs, ttl);
			return response;
		} finally {
			lock.unlock();
			// Best-effort cleanup: remove lock entry if cache is fresh
			CachedEnrichment current = cache.get(userId);
			if (current != null && !current.isExpired()) {
				locks.remove(userId, lock);
			}
		}
	}

}
