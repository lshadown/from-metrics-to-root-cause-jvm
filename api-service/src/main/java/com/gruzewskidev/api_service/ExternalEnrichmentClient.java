package com.gruzewskidev.api_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Service
public class ExternalEnrichmentClient {

	private static final Logger log = LoggerFactory.getLogger(ExternalEnrichmentClient.class);

	private final RestClient restClient;

	public ExternalEnrichmentClient(@Value("${external.base-url}") String baseUrl) {
		this.restClient = RestClient.builder().baseUrl(baseUrl).build();
	}

	public EnrichmentResponse getEnrichment(long userId) {
		long start = System.currentTimeMillis();
		try {
			EnrichmentResponse response = restClient.get()
					.uri("/enrichment?userId={userId}", userId)
					.retrieve()
					.body(EnrichmentResponse.class);
			long duration = System.currentTimeMillis() - start;
			log.info("Downstream enrichment call userId={} durationMs={}", userId, duration);
			return response;
		} catch (RestClientException e) {
			long duration = System.currentTimeMillis() - start;
			log.error("Downstream enrichment call failed userId={} durationMs={}", userId, duration, e);
			throw new DownstreamException("Enrichment service unavailable", e);
		}
	}

}
