package com.gruzewskidev.api_service;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantLock;

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

	public EnrichmentCacheService(ExternalEnrichmentClient enrichmentClient) {
		this.enrichmentClient = enrichmentClient;
	}

	public EnrichmentResponse getEnrichment(long userId) {
		CachedEnrichment cached = cache.get(userId);
		if (cached != null && !cached.isExpired()) {
			log.info("userId={} cache_hit=true", userId);
			return cached.value();
		}

		ReentrantLock lock = locks.computeIfAbsent(userId, id -> new ReentrantLock());
		long lockWaitStart = System.currentTimeMillis();
		lock.lock();
		try {
			long lockWaitMs = System.currentTimeMillis() - lockWaitStart;
			log.info("userId={} lockWaitMs={}", userId, lockWaitMs);

			// Double-check after acquiring lock
			cached = cache.get(userId);
			if (cached != null && !cached.isExpired()) {
				log.info("userId={} cache_hit=true (after lock)", userId);
				return cached.value();
			}

			long refreshStart = System.currentTimeMillis();
			EnrichmentResponse response = enrichmentClient.getEnrichment(userId);
			long refreshMs = System.currentTimeMillis() - refreshStart;

			boolean isPremium = userId % 20 == 0;
			Duration ttl = isPremium ? PREMIUM_TTL : STANDARD_TTL;
			cache.put(userId, new CachedEnrichment(response, Instant.now().plus(ttl)));

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
