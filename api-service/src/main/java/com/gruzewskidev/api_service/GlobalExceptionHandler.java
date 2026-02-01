package com.gruzewskidev.api_service;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice
public class GlobalExceptionHandler {

	@ExceptionHandler(MissingServletRequestParameterException.class)
	public ResponseEntity<ErrorResponse> handleMissingParam(MissingServletRequestParameterException ex) {
		ErrorResponse error = new ErrorResponse(
				"Missing required parameter",
				"Parameter '" + ex.getParameterName() + "' is required");
		return ResponseEntity.badRequest().body(error);
	}

	@ExceptionHandler(MethodArgumentTypeMismatchException.class)
	public ResponseEntity<ErrorResponse> handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
		ErrorResponse error = new ErrorResponse(
				"Invalid parameter type",
				"Parameter '" + ex.getName() + "' must be a valid number");
		return ResponseEntity.badRequest().body(error);
	}

	@ExceptionHandler(DownstreamException.class)
	public ResponseEntity<ErrorResponse> handleDownstream(DownstreamException ex) {
		ErrorResponse error = new ErrorResponse(
				"Downstream service error",
				ex.getMessage());
		return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(error);
	}

}
