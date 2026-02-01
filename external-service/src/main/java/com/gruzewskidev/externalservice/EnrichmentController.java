package com.gruzewskidev.externalservice;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class EnrichmentController {

	private static final Logger log = LoggerFactory.getLogger(EnrichmentController.class);

	@GetMapping("/enrichment")
	public EnrichmentResponse enrich(@RequestParam long userId) {
		boolean isPremium = userId % 20 == 0;
		long sleepMs = isPremium ? 2500 : 80;
		String segment = isPremium ? "premium" : "standard";
		int riskScore = (int) ((userId % 7) * 13);

		try {
			Thread.sleep(sleepMs);
		} catch (InterruptedException e) {
			Thread.currentThread().interrupt();
		}

		log.info("userId={} segment={} sleepMs={}", userId, segment, sleepMs);

		return new EnrichmentResponse(userId, segment, riskScore);
	}

}
