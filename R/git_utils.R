#' Git Utilities
#'
#' Functions for extracting and analyzing git changes.
#'
#' @name git-utils
NULL

#' Get Staged Changes
#'
#' Retrieves the diff of staged changes in the current git repository.
#'
#' @param path Path to the git repository. Default is current directory.
#'
#' @return A list with components:
#'   - `files`: Character vector of changed file paths
#'   - `summary`: Brief text summary of changes
#'   - `diff_text`: Full diff text
#'   - `stats`: List with lines_added, lines_removed, files_changed
#'   - `concerns`: Character vector of detected security concerns
#'
#' @export
#'
#' @examples
#' \dontrun{
#' changes <- get_staged_diff()
#' cat(changes$summary)
#' }
get_staged_diff <- function(path = ".") {
  if (!requireNamespace("git2r", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg git2r} is required. Install with: {.code install.packages('git2r')}")
  }

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  # Get the staged diff (index vs HEAD)
  diff_obj <- git2r::diff(repo, index = TRUE)

  # Extract file information
  files <- extract_changed_files(diff_obj)

  if (length(files) == 0) {
    return(list(
      files = character(),
      summary = "",
      diff_text = "",
      stats = list(lines_added = 0, lines_removed = 0, files_changed = 0),
      concerns = character()
    ))
  }

  # Get diff text
  diff_text <- capture_diff_text(diff_obj)

  # Calculate stats
  stats <- calculate_diff_stats(diff_text)
  stats$files_changed <- length(files)

  # Build summary
  summary <- build_diff_summary(files, stats)

  # Detect concerns
  concerns <- detect_security_concerns(diff_text, files)

  list(
    files = files,
    summary = summary,
    diff_text = diff_text,
    stats = stats,
    concerns = concerns
  )
}

#' Extract Changed File Paths from Diff
#'
#' @param diff_obj A git2r diff object
#' @return Character vector of file paths
#' @keywords internal
extract_changed_files <- function(diff_obj) {
  if (length(diff_obj$files) == 0) {
    return(character())
  }

  vapply(diff_obj$files, function(f) f$new_file, character(1))
}

#' Capture Diff Text
#'
#' @param diff_obj A git2r diff object
#' @return Character string of the full diff
#' @keywords internal
capture_diff_text <- function(diff_obj) {
  # Build diff text from hunks for detailed output
  lines <- character()

  for (file_diff in diff_obj$files) {
    lines <- c(lines, paste0("--- a/", file_diff$old_file))
    lines <- c(lines, paste0("+++ b/", file_diff$new_file))

    for (hunk in file_diff$hunks) {
      lines <- c(lines, hunk$header)
      for (line in hunk$lines) {
        # origin: 32 = context, 43 = addition (+), 45 = deletion (-)
        prefix <- switch(as.character(line$origin),
          "32" = " ",
          "43" = "+",
          "45" = "-",
          " "
        )
        # Remove trailing newline from content since we add our own
        content <- sub("\n$", "", line$content)
        lines <- c(lines, paste0(prefix, content))
      }
    }
    lines <- c(lines, "")  # Blank line between files
  }

  paste(lines, collapse = "\n")
}

#' Calculate Diff Statistics
#'
#' @param diff_text Character string of diff content
#' @return List with lines_added and lines_removed
#' @keywords internal
calculate_diff_stats <- function(diff_text) {
  lines <- strsplit(diff_text, "\n")[[1]]

  # Count lines starting with + or - (excluding file headers)
  added <- sum(grepl("^\\+[^+]", lines))
  removed <- sum(grepl("^-[^-]", lines))

  list(
    lines_added = added,
    lines_removed = removed
  )
}

#' Build Human-Readable Diff Summary
#'
#' @param files Character vector of changed files
#' @param stats List with diff statistics
#' @return Character string summary
#' @keywords internal
build_diff_summary <- function(files, stats) {
  n_files <- length(files)

  # Group by file type
  extensions <- tools::file_ext(files)
  ext_counts <- table(extensions)
  ext_summary <- paste(
    sprintf("%d %s", ext_counts, ifelse(ext_counts == 1, paste0(".", names(ext_counts)), paste0(".", names(ext_counts), " files"))),
    collapse = ", "
  )

  glue::glue(
    "{n_files} file(s) changed ({ext_summary})\n",
    "+{stats$lines_added} lines added, -{stats$lines_removed} lines removed\n",
    "\nFiles:\n",
    "{paste('- ', files, collapse = '\n')}"
  )
}

#' Detect Security Concerns in Diff
#'
#' Scans the diff for potential security issues relevant to R and Shiny code.
#'
#' @param diff_text Character string of diff content
#' @param files Character vector of changed files
#' @return Character vector of concern messages
#' @keywords internal
detect_security_concerns <- function(diff_text, files) {
  concerns <- character()

  # Pattern checks for R-specific concerns
  patterns <- list(
    # Code execution
    list(
      pattern = "\\beval\\s*\\(",
      message = "Use of eval() detected - potential code injection risk"
    ),
    list(
      pattern = "\\bparse\\s*\\(",
      message = "Use of parse() detected - potential code injection risk"
    ),
    list(
      pattern = "\\bsource\\s*\\(",
      message = "Use of source() detected - verify file paths are trusted"
    ),
    list(
      pattern = "\\bsystem\\s*\\(|\\bsystem2\\s*\\(",
      message = "System command execution detected - verify input sanitization"
    ),

    # Database/SQL concerns
    list(
      pattern = "\\bpaste\\s*\\([^)]*SQL|\\bglue\\s*\\([^)]*SELECT|\\bsprintf\\s*\\([^)]*SELECT",
      message = "Possible SQL string concatenation - consider parameterized queries"
    ),
    list(
      pattern = "dbSendQuery.*paste|dbExecute.*paste",
      message = "Database query with string concatenation - SQL injection risk"
    ),

    # Shiny-specific concerns
    list(
      pattern = "\\brenderUI\\s*\\(|\\buiOutput\\s*\\(",
      message = "Dynamic UI detected - verify input sanitization for XSS prevention"
    ),
    list(
      pattern = "\\bHTML\\s*\\(|\\btags\\$script",
      message = "Raw HTML/script injection - verify content is trusted"
    ),

    # Credential exposure
    list(
      pattern = "(api_key|password|secret|token)\\s*[=:]\\s*[\"'][^\"']+[\"']",
      message = "Possible hardcoded credential detected"
    ),

    # File operations
    list(
      pattern = "\\bunlink\\s*\\(|\\bfile\\.remove\\s*\\(",
      message = "File deletion detected - verify paths are safe"
    ),
    list(
      pattern = "\\bdownload\\.file\\s*\\(",
      message = "File download detected - verify URL is trusted"
    )
  )

  for (check in patterns) {
    if (grepl(check$pattern, diff_text, ignore.case = TRUE)) {
      concerns <- c(concerns, check$message)
    }
  }

  # Check for sensitive file modifications
  sensitive_patterns <- c("\\.env$", "credentials", "secrets", "\\.pem$", "\\.key$")
  for (file in files) {
    for (pattern in sensitive_patterns) {
      if (grepl(pattern, file, ignore.case = TRUE)) {
        concerns <- c(concerns, sprintf("Sensitive file modified: %s", file))
      }
    }
  }

  unique(concerns)
}

#' Format Diff for LLM Review
#'
#' Creates a structured representation of the diff suitable for LLM context.
#'
#' @param diff_info List returned by get_staged_diff()
#' @return Character string formatted for LLM review
#' @keywords internal
format_diff_for_review <- function(diff_info) {
  if (length(diff_info$files) == 0) {
    return("No staged changes.")
  }

  concern_text <- if (length(diff_info$concerns) > 0) {
    paste(
      "CONCERNS DETECTED:",
      paste("-", diff_info$concerns, collapse = "\n"),
      sep = "\n"
    )
  } else {
    "No security concerns detected."
  }

  # Truncate very long diffs for LLM context
  diff_text <- diff_info$diff_text
  max_diff_chars <- 8000
  if (nchar(diff_text) > max_diff_chars) {
    diff_text <- paste0(
      substr(diff_text, 1, max_diff_chars),
      "\n\n... [diff truncated, ", nchar(diff_info$diff_text) - max_diff_chars, " more characters]"
    )
  }

  glue::glue(
    "SUMMARY:\n{diff_info$summary}\n\n",
    "{concern_text}\n\n",
    "FULL DIFF:\n```\n{diff_text}\n```"
  )
}
