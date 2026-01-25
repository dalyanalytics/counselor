#' Git Hook Management
#'
#' Functions for installing and managing git hooks that trigger code reviews.
#'
#' @name git-hooks
NULL

#' Install Git Hooks
#'
#' Installs git hooks that trigger counselor review sessions. The pre-commit
#' hook will start a voice review of staged changes before allowing the commit.
#'
#' @param path Path to the git repository. Default is current directory.
#' @param types Character vector of hook types to install. Currently supports
#'   "pre-commit".
#' @param force Logical. If TRUE, overwrite existing hooks without prompting.
#'   If FALSE (default), existing hooks are backed up.
#'
#' @return Invisible character vector of installed hook paths.
#' @export
#'
#' @examples
#' \dontrun{
#' # Install pre-commit hook in current repo
#' install_hooks()
#'
#' # Install in a specific repo
#' install_hooks(path = "~/my-project")
#'
#' # Force overwrite existing hooks
#' install_hooks(force = TRUE)
#' }
install_hooks <- function(path = ".", types = "pre-commit", force = FALSE) {
  path <- normalizePath(path, mustWork = TRUE)
  hook_dir <- file.path(path, ".git", "hooks")

  if (!dir.exists(hook_dir)) {
    cli::cli_abort(c(
      "Not a git repository: {.path {path}}",
      "i" = "Run {.code git init} first to create a repository."
    ))
  }

  installed <- character()

  for (hook_type in types) {
    hook_path <- install_single_hook(hook_dir, hook_type, force)
    if (!is.null(hook_path)) {
      installed <- c(installed, hook_path)
    }
  }

  if (length(installed) > 0) {
    cli::cli_alert_success("Installed {length(installed)} git hook(s)")
    cli::cli_bullets(setNames(installed, rep("*", length(installed))))
  }

  invisible(installed)
}

#' Install a Single Git Hook
#'
#' @param hook_dir Path to .git/hooks directory
#' @param hook_type Type of hook (e.g., "pre-commit")
#' @param force Whether to force overwrite
#' @return Path to installed hook or NULL
#' @keywords internal
install_single_hook <- function(hook_dir, hook_type, force) {
  hook_path <- file.path(hook_dir, hook_type)

  # Check for existing hook
  if (file.exists(hook_path) && !force) {
    backup_path <- paste0(hook_path, ".backup.", format(Sys.time(), "%Y%m%d%H%M%S"))
    file.copy(hook_path, backup_path)
    cli::cli_alert_info("Backed up existing {hook_type} hook to {.path {basename(backup_path)}}")
  }

  # Generate hook content
  hook_content <- generate_hook_content(hook_type)

  # Write hook
  writeLines(hook_content, hook_path)

  # Make executable (Unix-like systems)
  if (.Platform$OS.type != "windows") {
    Sys.chmod(hook_path, mode = "0755")
  } else {
    # Create Windows batch file companion
    bat_content <- sprintf('@echo off\nRscript "%s" %%*', hook_path)
    writeLines(bat_content, paste0(hook_path, ".bat"))
  }

  hook_path
}

#' Generate Hook Script Content
#'
#' @param hook_type Type of hook
#' @return Character vector of hook script lines
#' @keywords internal
generate_hook_content <- function(hook_type) {
  switch(hook_type,
    "pre-commit" = generate_precommit_hook(),
    cli::cli_abort("Unknown hook type: {.val {hook_type}}")
  )
}

#' Generate Pre-commit Hook Script
#'
#' @return Character vector of script lines
#' @keywords internal
generate_precommit_hook <- function() {
  c(
    "#!/usr/bin/env Rscript",
    "",
    "# counselor pre-commit hook",
    "# Triggers voice code review before allowing commits",
    "",
    "# Check if counselor is available",
    "if (!requireNamespace('counselor', quietly = TRUE)) {",
    "  message('counselor package not found, skipping review')",
    "  quit(status = 0)",
    "}",
    "",
    "# Check for COUNSELOR_SKIP environment variable",
    "if (nchar(Sys.getenv('COUNSELOR_SKIP')) > 0) {",
    "  message('COUNSELOR_SKIP set, skipping review')",
    "  quit(status = 0)",
    "}",
    "",
    "# Run the review",
    "result <- tryCatch({",
    "  counselor::review_commit()",
    "}, error = function(e) {",
    "  message('Error during review: ', e$message)",
    "  message('Allowing commit to proceed')",
    "  list(approved = TRUE)",
    "})",
    "",
    "# Check result",
    "if (is.null(result$approved)) {",
    "  # No staged changes",
    "  quit(status = 0)",
    "} else if (isTRUE(result$approved)) {",
    "  message('Commit approved')",
    "  quit(status = 0)",
    "} else {",
    "  message('Commit rejected by reviewer')",
    "  quit(status = 1)",
    "}"
  )
}

#' Remove Git Hooks
#'
#' Removes counselor git hooks from a repository.
#'
#' @param path Path to the git repository.
#' @param types Character vector of hook types to remove.
#' @param restore_backup Logical. If TRUE and a backup exists, restore it.
#'
#' @return Invisible logical indicating success.
#' @export
#'
#' @examples
#' \dontrun{
#' # Remove hooks
#' remove_hooks()
#'
#' # Remove and restore backup
#' remove_hooks(restore_backup = TRUE)
#' }
remove_hooks <- function(path = ".", types = "pre-commit", restore_backup = FALSE) {
  path <- normalizePath(path, mustWork = TRUE)
  hook_dir <- file.path(path, ".git", "hooks")

  if (!dir.exists(hook_dir)) {
    cli::cli_abort("Not a git repository: {.path {path}}")
  }

  for (hook_type in types) {
    hook_path <- file.path(hook_dir, hook_type)

    if (!file.exists(hook_path)) {
      cli::cli_alert_info("No {hook_type} hook found")
      next
    }

    # Check if it's a counselor hook
    content <- readLines(hook_path, n = 5)
    if (!any(grepl("counselor", content))) {
      cli::cli_alert_warning("{hook_type} hook doesn't appear to be from counselor, skipping")
      next
    }

    # Remove the hook
    file.remove(hook_path)
    cli::cli_alert_success("Removed {hook_type} hook")

    # Also remove Windows companion if present
    bat_path <- paste0(hook_path, ".bat")
    if (file.exists(bat_path)) {
      file.remove(bat_path)
    }

    # Restore backup if requested
    if (restore_backup) {
      backups <- list.files(hook_dir, pattern = paste0("^", hook_type, "\\.backup\\."), full.names = TRUE)
      if (length(backups) > 0) {
        # Use most recent backup
        newest <- backups[order(file.info(backups)$mtime, decreasing = TRUE)[1]]
        file.copy(newest, hook_path)
        Sys.chmod(hook_path, mode = "0755")
        cli::cli_alert_info("Restored backup: {.path {basename(newest)}}")
      }
    }
  }

  invisible(TRUE)
}

#' Check Hook Status
#'
#' Reports on the status of counselor hooks in a repository.
#'
#' @param path Path to the git repository.
#'
#' @return A data frame with hook status information.
#' @export
#'
#' @examples
#' \dontrun{
#' hook_status()
#' }
hook_status <- function(path = ".") {
  path <- normalizePath(path, mustWork = TRUE)
  hook_dir <- file.path(path, ".git", "hooks")

  if (!dir.exists(hook_dir)) {
    cli::cli_abort("Not a git repository: {.path {path}}")
  }

  hook_types <- c("pre-commit", "pre-push", "commit-msg")

  status <- lapply(hook_types, function(hook_type) {
    hook_path <- file.path(hook_dir, hook_type)

    if (!file.exists(hook_path)) {
      return(data.frame(
        hook = hook_type,
        installed = FALSE,
        counselor = FALSE,
        executable = FALSE,
        stringsAsFactors = FALSE
      ))
    }

    content <- readLines(hook_path, warn = FALSE)
    is_counselor <- any(grepl("counselor", content))
    is_executable <- file.access(hook_path, 1) == 0

    data.frame(
      hook = hook_type,
      installed = TRUE,
      counselor = is_counselor,
      executable = is_executable,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, status)

  # Print nice summary
  cli::cli_h3("Git Hook Status")
  for (i in seq_len(nrow(result))) {
    row <- result[i, ]
    if (!row$installed) {
      cli::cli_bullets(setNames(
        paste0(row$hook, ": not installed"),
        " "
      ))
    } else if (row$counselor) {
      cli::cli_bullets(setNames(
        paste0(row$hook, ": counselor hook installed"),
        "v"
      ))
    } else {
      cli::cli_bullets(setNames(
        paste0(row$hook, ": other hook present"),
        "!"
      ))
    }
  }

  invisible(result)
}
