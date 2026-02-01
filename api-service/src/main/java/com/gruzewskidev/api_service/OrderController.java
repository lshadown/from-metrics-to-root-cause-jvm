package com.gruzewskidev.api_service;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class OrderController {

	private static final Logger log = LoggerFactory.getLogger(OrderController.class);

	private static final List<Order> STUB_ORDERS = List.of(new Order("A1"), new Order("B2"));

	private final EnrichmentCacheService enrichmentCacheService;

	public OrderController(EnrichmentCacheService enrichmentCacheService) {
		this.enrichmentCacheService = enrichmentCacheService;
	}

	@GetMapping("/orders")
	public OrderResponse getOrders(@RequestParam long userId,
								   @RequestParam(defaultValue = "false") boolean details) {
		log.info("userId={} details={}", userId, details);

		EnrichmentResponse enrichment = null;
		if (details) {
			enrichment = enrichmentCacheService.getEnrichment(userId);
		}

		return new OrderResponse(userId, STUB_ORDERS, enrichment);
	}

}
