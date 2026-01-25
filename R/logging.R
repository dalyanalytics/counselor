#' Session Logging
#'
#' Functions for logging review sessions and tracking costs.
#'
#' @name logging
NULL

#' Log a Review Session
#'
#' Records session details to the counselor log file.
#'
#' @param chat ellmer chat object
#' @param result Review result list
#' @param diff_info Diff information that was reviewed
#' @return Invisible path to log file
#' @keywords internal
log_session <- function(chat, result, diff_info) {
  log_dir <- get_log_dir()
  dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)

  log_entry <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    project = basename(getwd()),
    project_path = getwd(),
    approved = result$approved,
    files_reviewed = diff_info$files,
    stats = diff_info$stats,
    concerns = diff_info$concerns,
    turns = count_turns(chat),
    cost = extract_cost(chat),
    transcript = result$transcript
  )

  # Append to JSONL file (one JSON object per line)
  log_file <- file.path(log_dir, format(Sys.Date(), "%Y-%m.jsonl"))
  log_line <- jsonlite::toJSON(log_entry, auto_unbox = TRUE)

  cat(log_line, "\n", file = log_file, append = TRUE)

  invisible(log_file)
}

#' Get Log Directory
#'
#' @return Path to counselor log directory
#' @keywords internal
get_log_dir <- function() {
  # Use XDG-style config if available, otherwise ~/.counselor
  base_dir <- Sys.getenv("XDG_DATA_HOME", file.path(Sys.getenv("HOME"), ".local", "share"))
  file.path(base_dir, "counselor", "logs")
}

#' Count Conversation Turns
#'
#' @param chat ellmer chat object
#' @return Integer count of turns
#' @keywords internal
count_turns <- function(chat) {
  if (is.null(chat)) return(0L)

  # ellmer stores turns in the chat object
  tryCatch({
    length(chat$turns)
  }, error = function(e) {
    0L
  })
}

#' Extract Cost from Chat
#'
#' Extracts cost information from an ellmer chat object.
#'
#' @param chat ellmer chat object
#' @return List with input_tokens, output_tokens, and cost_usd
#' @keywords internal
extract_cost <- function(chat) {
  if (is.null(chat)) {
    return(list(input_tokens = 0, output_tokens = 0, cost_usd = 0))
  }

  # ellmer tracks token usage and cost
  tryCatch({
    list(
      input_tokens = chat$tokens[["input"]] %||% 0,
      output_tokens = chat$tokens[["output"]] %||% 0,
      cost_usd = chat$cost %||% 0
    )
  }, error = function(e) {
    list(input_tokens = 0, output_tokens = 0, cost_usd = 0)
  })
}

#' Read Session Logs
#'
#' Reads and parses counselor session logs.
#'
#' @param months Number of months of logs to read. Default is 1 (current month).
#' @param project Optional project name to filter by.
#'
#' @return A data frame of log entries.
#' @export
#'
#' @examples
#' \dontrun{
#' # Read current month's logs
#' logs <- read_logs()
#'
#' # Read last 3 months
#' logs <- read_logs(months = 3)
#'
#' # Filter by project
#' logs <- read_logs(project = "my-project")
#' }
read_logs <- function(months = 1, project = NULL) {
  log_dir <- get_log_dir()

  if (!dir.exists(log_dir)) {
    cli::cli_alert_info("No log directory found at {.path {log_dir}}")
    return(data.frame())
  }

  # Generate month patterns
  dates <- seq(Sys.Date(), by = "-1 month", length.out = months)
  patterns <- format(dates, "%Y-%m.jsonl")
  log_files <- file.path(log_dir, patterns)
  log_files <- log_files[file.exists(log_files)]

  if (length(log_files) == 0) {
    cli::cli_alert_info("No log files found")
    return(data.frame())
  }

  # Read and parse all logs
  entries <- lapply(log_files, function(f) {
    lines <- readLines(f, warn = FALSE)
    lapply(lines, function(line) {
      tryCatch(
        jsonlite::fromJSON(line),
        error = function(e) NULL
      )
    })
  })

  entries <- unlist(entries, recursive = FALSE)
  entries <- entries[!vapply(entries, is.null, logical(1))]

  if (length(entries) == 0) {
    return(data.frame())
  }

  # Convert to data frame
  df <- data.frame(
    timestamp = vapply(entries, function(e) e$timestamp %||% NA_character_, character(1)),
    project = vapply(entries, function(e) e$project %||% NA_character_, character(1)),
    approved = vapply(entries, function(e) e$approved %||% NA, logical(1)),
    files_changed = vapply(entries, function(e) length(e$files_reviewed %||% list()), integer(1)),
    lines_added = vapply(entries, function(e) e$stats$lines_added %||% 0L, integer(1)),
    lines_removed = vapply(entries, function(e) e$stats$lines_removed %||% 0L, integer(1)),
    turns = vapply(entries, function(e) e$turns %||% 0L, integer(1)),
    cost_usd = vapply(entries, function(e) e$cost$cost_usd %||% 0, numeric(1)),
    concerns = vapply(entries, function(e) length(e$concerns %||% list()), integer(1)),
    stringsAsFactors = FALSE
  )

  # Filter by project if specified
  if (!is.null(project)) {
    df <- df[df$project == project, ]
  }

  # Sort by timestamp descending
  df <- df[order(df$timestamp, decreasing = TRUE), ]
  rownames(df) <- NULL

  df
}

#' Summarize Session Costs
#'
#' Provides a summary of costs across review sessions.
#'
#' @param months Number of months to summarize.
#'
#' @return A list with cost summary statistics.
#' @export
#'
#' @examples
#' \dontrun{
#' cost_summary()
#' }
cost_summary <- function(months = 1) {
  logs <- read_logs(months = months)

  if (nrow(logs) == 0) {
    cli::cli_alert_info("No sessions logged yet")
    return(invisible(NULL))
  }

  summary_data <- list(
    total_sessions = nrow(logs),
    approved_sessions = sum(logs$approved, na.rm = TRUE),
    rejected_sessions = sum(!logs$approved, na.rm = TRUE),
    total_cost_usd = sum(logs$cost_usd, na.rm = TRUE),
    avg_cost_per_session = mean(logs$cost_usd, na.rm = TRUE),
    total_files_reviewed = sum(logs$files_changed, na.rm = TRUE),
    avg_turns_per_session = mean(logs$turns, na.rm = TRUE),
    projects = unique(logs$project)
  )

  cli::cli_h3("Counselor Usage Summary ({months} month{?s})")

  cli::cli_bullets(c(
    "*" = "Total sessions: {summary_data$total_sessions}",
    "*" = "Approved: {summary_data$approved_sessions} | Rejected: {summary_data$rejected_sessions}",
    "*" = "Total cost: ${format(summary_data$total_cost_usd, nsmall = 2)}",
    "*" = "Avg cost/session: ${format(summary_data$avg_cost_per_session, nsmall = 3)}",
    "*" = "Files reviewed: {summary_data$total_files_reviewed}",
    "*" = "Avg turns/session: {format(summary_data$avg_turns_per_session, digits = 1)}",
    "*" = "Projects: {paste(summary_data$projects, collapse = ', ')}"
  ))

  invisible(summary_data)
}

#' Clear Old Logs
#'
#' Removes log files older than a specified number of months.
#'
#' @param keep_months Number of months of logs to keep.
#'
#' @return Invisible count of files removed.
#' @export
#'
#' @examples
#' \dontrun{
#' # Keep only last 3 months
#' clear_old_logs(keep_months = 3)
#' }
clear_old_logs <- function(keep_months = 6) {
  log_dir <- get_log_dir()

  if (!dir.exists(log_dir)) {
    return(invisible(0L))
  }

  log_files <- list.files(log_dir, pattern = "\\.jsonl$", full.names = TRUE)

  if (length(log_files) == 0) {
    return(invisible(0L))
  }

  # Calculate cutoff date
  cutoff <- Sys.Date() - (keep_months * 30)

  removed <- 0L
  for (f in log_files) {
    # Extract date from filename (YYYY-MM.jsonl)
    date_str <- sub("\\.jsonl$", "", basename(f))
    file_date <- tryCatch(
      as.Date(paste0(date_str, "-01")),
      error = function(e) Sys.Date()
    )

    if (file_date < cutoff) {
      file.remove(f)
      removed <- removed + 1L
      cli::cli_alert_info("Removed old log: {.path {basename(f)}}")
    }
  }

  if (removed > 0) {
    cli::cli_alert_success("Removed {removed} old log file{?s}")
  }

  invisible(removed)
}
