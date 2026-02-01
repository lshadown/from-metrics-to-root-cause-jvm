package com.gruzewskidev.api_service;

import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public class ErrorResponse {

	private String error;
	private String details;

}
