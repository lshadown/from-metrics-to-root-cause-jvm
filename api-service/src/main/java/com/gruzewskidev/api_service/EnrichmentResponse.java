package com.gruzewskidev.api_service;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
public class EnrichmentResponse {

	private long userId;
	private String segment;
	private int riskScore;

}
