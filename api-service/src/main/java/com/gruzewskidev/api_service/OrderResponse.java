package com.gruzewskidev.api_service;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public class OrderResponse {

	private long userId;
	private List<Order> orders;

	@JsonInclude(JsonInclude.Include.NON_NULL)
	private EnrichmentResponse enrichment;

}
