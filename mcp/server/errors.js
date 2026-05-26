export class SafeMcpError extends Error {
  constructor(errorType, message, retryable = false) {
    super(message);
    this.name = "SafeMcpError";
    this.errorType = errorType;
    this.retryable = retryable;
  }
}

export class ConfigError extends SafeMcpError {
  constructor(message) {
    super("config_error", message, false);
    this.name = "ConfigError";
  }
}

export class ValidationError extends SafeMcpError {
  constructor(message) {
    super("validation_error", message, false);
    this.name = "ValidationError";
  }
}

export function safeErrorResult(error) {
  if (error instanceof SafeMcpError) {
    return {
      status: "error",
      errorType: error.errorType,
      message: error.message,
      retryable: error.retryable
    };
  }

  return {
    status: "error",
    errorType: "bridge_error",
    message: "dispatcher bridge request failed",
    retryable: false
  };
}

export function toToolResult(value) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}
