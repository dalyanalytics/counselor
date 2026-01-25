#' Security Module
#'
#' Input validation, command sanitization, and safety checks for voice-driven
#' code operations.
#'
#' @name security
NULL

# Blacklisted commands that should never be executed from voice input
COMMAND_BLACKLIST <- c(

  # Destructive file operations
  "rm -rf",
  "rm -r",
  "rmdir",

  "unlink",
  # System modification
  "sudo",
  "chmod 777",
  "chown",
  # Network/remote execution
  "curl.*\\|.*sh",
  "wget.*\\|.*sh",
  "eval.*\\$\\(",
  # R dangerous operations
  "system\\(",
  "system2\\(",

  "shell\\(",
  # Credential exposure
  "cat.*\\.env",
  "cat.*credentials",
  "echo.*API_KEY",
  "echo.*PASSWORD"
)

# Patterns that warrant confirmation before execution
RISKY_PATTERNS <- c(
  # File deletion
  "delete|remove|rm\\s",
  # Database operations
  "drop\\s+table|truncate|delete\\s+from",
  # Git destructive operations
  "git\\s+reset\\s+--hard",

  "git\\s+push\\s+--force",
  "git\\s+clean\\s+-fd",
  # Overwriting files
  "overwrite|replace\\s+all",
  # Package/dependency changes
  "install\\.packages|pip\\s+install|npm\\s+install"
)

#' Validate Voice Input
#'
#' Checks voice input for potentially dangerous commands or patterns before
#' processing. Returns a sanitized version of the input or raises an error
#' if blacklisted commands are detected.
#'
#' @param input Character string from voice transcription.
#' @param strict Logical. If TRUE, raises error on blacklisted commands.
#'   If FALSE, returns NULL and logs a warning.
#'
#' @return The sanitized input string, or NULL if blocked.
#' @export
#'
#' @examples
#' \dontrun{
#' # Safe input passes through
#' validate_voice_input("please review the authentication changes")
#'
#' # Dangerous input is blocked
#' validate_voice_input("run sudo rm -rf /")  # Error or NULL
#' }
validate_voice_input <- function(input, strict = FALSE) {
  if (is.null(input) || !is.character(input) || length(input) == 0) {
    return(NULL)
  }

  input <- trimws(input)
  input_lower <- tolower(input)

  # Check against blacklist
  for (pattern in COMMAND_BLACKLIST) {
    if (grepl(pattern, input_lower, ignore.case = TRUE)) {
      msg <- paste0("Blocked potentially dangerous command pattern: ", pattern)
      cli::cli_alert_danger(msg)
      log_security_event("blocked_command", input, pattern)

      if (strict) {
        cli::cli_abort(c(
          "Voice input contains blacklisted command pattern.",
          "i" = "Pattern detected: {.val {pattern}}",
          "i" = "This command cannot be executed via voice input."
        ))
      }
      return(NULL)
    }
  }

  input
}

#' Check for Risky Operations
#'
#' Scans input for patterns that warrant user confirmation before proceeding.
#' Does not block the operation, but flags it for confirmation.
#'
#' @param input Character string to check.
#'
#' @return A list with:
#'   - `risky`: Logical indicating if risky patterns were found
#'   - `patterns`: Character vector of matched risky patterns
#'   - `message`: Human-readable warning message
#'
#' @export
#'
#' @examples
#' \dontrun
#' check_risky_operation("please delete the old test files")
#' # Returns list(risky = TRUE, patterns = "delete|remove|rm\\s", ...)
#' }
check_risky_operation <- function(input) {
  if (is.null(input) || !is.character(input)) {
    return(list(risky = FALSE, patterns = character(), message = NULL))
  }

  input_lower <- tolower(input)
  matched <- character()

  for (pattern in RISKY_PATTERNS) {
    if (grepl(pattern, input_lower, ignore.case = TRUE)) {
      matched <- c(matched, pattern)
    }
  }

  if (length(matched) > 0) {
    msg <- paste0(
      "This operation may be risky. Detected: ",
      paste(matched, collapse = ", ")
    )
    return(list(risky = TRUE, patterns = matched, message = msg))
  }

  list(risky = FALSE, patterns = character(), message = NULL)
}

#' Request Voice Confirmation
#'
#' Asks the user to verbally confirm a risky operation.
#'
#' @param operation Description of the operation to confirm.
#' @param timeout_secs Seconds to wait for voice response.
#'
#' @return Logical. TRUE if user confirmed, FALSE otherwise.
#' @export
#'
#' @examples
#' \dontrun{
#' if (request_voice_confirmation("delete all test files")) {
#'   # Proceed with deletion
#' }
#' }
request_voice_confirmation <- function(operation, timeout_secs = 10) {
  prompt <- paste0(
    "This operation may have significant effects: ", operation, ". ",
    "Please say 'yes confirm' or 'confirmed' to proceed, or 'no' to cancel."
  )

  cli::cli_alert_warning(prompt)
  voice_speak(prompt)

  response <- voice_listen(timeout_secs = timeout_secs)

  if (is.null(response)) {
    cli::cli_alert_info("No response received. Operation cancelled for safety.")
    return(FALSE)
  }

  response_lower <- tolower(trimws(response))

  confirmed <- grepl("^(yes|confirm|confirmed|proceed|do it)", response_lower)

  if (confirmed) {
    cli::cli_alert_success("Confirmation received.")
  } else {
    cli::cli_alert_info("Operation cancelled.")
  }

  confirmed
}

#' Sanitize Code for Review
#'
#' Removes or masks potentially sensitive information from code before
#' sending to the LLM for review.
#'
#' @param code Character string containing code to sanitize.
#'
#' @return Sanitized code string with sensitive patterns masked.
#' @export
#'
#' @examples
#' code <- 'api_key <- "sk-1234567890abcdef"'
#' sanitize_code_for_review(code)
#' # Returns: 'api_key <- "[REDACTED_API_KEY]"'
sanitize_code_for_review <- function(code) {
  if (is.null(code) || !is.character(code)) {
    return(code)
  }

  # API key patterns (handles =, :, and <- assignment)
  code <- gsub(
    '(api[_-]?key|apikey|secret[_-]?key|access[_-]?token)\\s*(<-|=|:)\\s*["\'][^"\']+["\']',
    '\\1 \\2 "[REDACTED]"',
    code,
    ignore.case = TRUE
  )

  # Password patterns (handles =, :, and <- assignment)
  code <- gsub(
    '(password|passwd|pwd)\\s*(<-|=|:)\\s*["\'][^"\']+["\']',
    '\\1 \\2 "[REDACTED]"',
    code,
    ignore.case = TRUE
  )

  # Bearer tokens
  code <- gsub(
    'Bearer\\s+[A-Za-z0-9._-]+',
    'Bearer [REDACTED]',
    code,
    ignore.case = TRUE
  )

  # Generic secrets that look like API keys (long alphanumeric strings)
  code <- gsub(
    '["\'][A-Za-z0-9]{32,}["\']',
    '"[REDACTED_SECRET]"',
    code
  )

  code
}

#' Safe Eval Wrapper
#'
#' Wraps eval() with safety checks. Should be used instead of direct eval()
#' when processing any input that could be influenced by voice commands.
#'
#' @param expr Expression to evaluate (as string or expression).
#' @param envir Environment for evaluation.
#' @param allow_list Character vector of allowed function names. If NULL,
#'   uses a default safe list.
#'
#' @return Result of evaluation, or NULL if blocked.
#' @export
#'
#' @examples
#' \dontrun{
#' # Safe operation
#' safe_eval("1 + 1")
#'
#' # Blocked operation
#' safe_eval("system('ls')")  # Returns NULL with warning
#' }
safe_eval <- function(expr, envir = parent.frame(), allow_list = NULL) {
  if (is.character(expr)) {
    # Check against blacklist first
    validated <- validate_voice_input(expr, strict = FALSE
    )
    if (is.null(validated)) {
      return(NULL)
    }

    # Parse the expression
    parsed <- tryCatch(
      parse(text = expr),
      error = function(e) {
        cli::cli_alert_danger("Failed to parse expression: {e$message}")
        return(NULL)
      }
    )

    if (is.null(parsed)) return(NULL)
    expr <- parsed
  }

  # Extract function calls from expression
  calls <- extract_function_calls(expr)

  # Default allow list for safe operations
  if (is.null(allow_list)) {
    allow_list <- c(
      # Math operations
      "+", "-", "*", "/", "^", "%%", "%/%",
      "sum", "mean", "median", "sd", "var", "min", "max",
      "sqrt", "abs", "log", "exp", "round", "floor", "ceiling",
      # Data manipulation
      "c", "list", "data.frame", "matrix", "vector",
      "length", "nrow", "ncol", "dim", "names",
      "head", "tail", "subset", "which",
      # String operations
      "paste", "paste0", "sprintf", "nchar", "substr",
      "toupper", "tolower", "trimws",
      # Logical
      "if", "else", "ifelse", "any", "all",
      # Assignment
      "<-", "=", "->",
      # Comparison
      "<", ">", "<=", ">=", "==", "!=", "&", "|", "!"
    )
  }

  # Check for disallowed function calls
  dangerous <- setdiff(calls, allow_list)
  if (length(dangerous) > 0) {
    cli::cli_alert_danger(
      "Blocked potentially unsafe function calls: {.val {dangerous}}"
    )
    log_security_event("blocked_eval", as.character(expr), dangerous)
    return(NULL)
  }

  # Execute with error handling
  tryCatch(
    eval(expr, envir = envir),
    error = function(e) {
      cli::cli_alert_danger("Evaluation error: {e$message}")
      NULL
    }
  )
}

#' Extract Function Calls from Expression
#'
#' Recursively extracts all function names called in an expression.
#'
#' @param expr An R expression.
#' @return Character vector of function names.
#' @keywords internal
extract_function_calls <- function(expr) {
  if (is.null(expr) || length(expr) == 0) {
    return(character())
  }

  calls <- character()

  walk_expr <- function(e) {
    if (is.call(e)) {
      fn <- as.character(e[[1]])
      calls <<- c(calls, fn)
      for (i in seq_along(e)[-1]) {
        walk_expr(e[[i]])
      }
    } else if (is.expression(e)) {
      for (sub_e in e) {
        walk_expr(sub_e)
      }
    }
  }

  walk_expr(expr)
  unique(calls)
}

#' Log Security Event
#'
#' Records security-related events for auditing.
#'
#' @param event_type Type of security event.
#' @param input The input that triggered the event.
#' @param details Additional details about the event.
#'
#' @keywords internal
log_security_event <- function(event_type, input, details = NULL) {
  log_dir <- file.path(Sys.getenv("HOME"), ".counselor", "security_logs")
  dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)

  entry <- list(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    event_type = event_type,
    input = substr(input, 1, 500),  # Truncate for safety
    details = details,
    session_id = Sys.getpid()
  )

  log_file <- file.path(log_dir, paste0(format(Sys.Date(), "%Y-%m"), ".jsonl"))

  tryCatch(
    {
      cat(jsonlite::toJSON(entry, auto_unbox = TRUE), "\n",
          file = log_file, append = TRUE)
    },
    error = function(e) {
      # Silent fail - don't let logging errors disrupt the session
    }
  )
}

#' Audit Security Logs
#'
#' Retrieves and summarizes recent security events.
#'
#' @param days Number of days of logs to review.
#'
#' @return A data frame of security events, or NULL if no logs exist.
#' @export
#'
#' @examples
#' \dontrun{
#' # Review last 7 days of security events
#' audit_security_logs(days = 7)
#' }
audit_security_logs <- function(days = 30) {
  log_dir <- file.path(Sys.getenv("HOME"), ".counselor", "security_logs")

  if (!dir.exists(log_dir)) {
    cli::cli_alert_info("No security logs found.")
    return(NULL)
  }

  log_files <- list.files(log_dir, pattern = "\\.jsonl$", full.names = TRUE)

  if (length(log_files) == 0) {
    cli::cli_alert_info("No security logs found.")
    return(NULL)
  }

  # Read and combine logs
  entries <- list()
  for (f in log_files) {
    lines <- readLines(f, warn = FALSE)
    for (line in lines) {
      if (nchar(trimws(line)) > 0) {
        entry <- tryCatch(
          jsonlite::fromJSON(line),
          error = function(e) NULL
        )
        if (!is.null(entry)) {
          entries <- c(entries, list(entry))
        }
      }
    }
  }

  if (length(entries) == 0) {
    cli::cli_alert_info("No security events recorded.")
    return(NULL)
  }

  # Convert to data frame
  df <- do.call(rbind, lapply(entries, function(e) {
    data.frame(
      timestamp = e$timestamp,
      event_type = e$event_type,
      input = e$input,
      details = if (is.null(e$details)) NA else paste(e$details, collapse = ", "),
      stringsAsFactors = FALSE
    )
  }))

  # Filter by date
  df$timestamp <- as.POSIXct(df$timestamp)
  cutoff <- Sys.time() - (days * 24 * 60 * 60)
  df <- df[df$timestamp >= cutoff, ]

  if (nrow(df) == 0) {
    cli::cli_alert_info("No security events in the last {days} days.")
    return(NULL)
  }

  cli::cli_alert_success("Found {nrow(df)} security event(s) in the last {days} days.")
  df
}
