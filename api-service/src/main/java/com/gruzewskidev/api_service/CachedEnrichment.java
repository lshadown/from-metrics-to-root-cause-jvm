package com.gruzewskidev.api_service;

import java.time.Instant;

public record CachedEnrichment(EnrichmentResponse value, Instant expiresAt) {

	public boolean isExpired() {
		return Instant.now().isAfter(expiresAt);
	}

}
