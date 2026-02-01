package com.gruzewskidev.externalservice;

import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public class EnrichmentResponse {

	private long userId;
	private String segment;
	private int riskScore;

}
