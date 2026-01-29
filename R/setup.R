#' Interactive Setup Wizard for counselor
#'
#' Guides you through configuring API keys for counselor. Keys are stored
#' globally in `~/.Renviron` so they work across all your R projects.
#'
#' @param use_1password Logical. If TRUE, shows instructions for 1Password CLI
#'   integration instead of storing keys directly. Default is FALSE.
#' @param check_only Logical. If TRUE, only checks current configuration without
#'   making changes. Default is FALSE.
#'
#' @return Invisibly returns a list with configuration status.
#'
#' @examples
#' \dontrun{
#' # Interactive setup
#' counselor_setup()
#'
#' # Check what's configured
#' counselor_setup(check_only = TRUE)
#'
#' # Setup with 1Password integration
#' counselor_setup(use_1password = TRUE)
#' }
#'
#' @export
counselor_setup <- function(use_1password = FALSE, check_only = FALSE) {
  cli::cli_h1("counselor Setup")

  # Check current status
  status <- check_api_keys(verbose = !check_only)

  if (check_only) {
    return(invisible(status))
  }

  if (status$all_configured) {
    cli::cli_alert_success("All API keys are already configured!")
    cli::cli_text("")

    if (cli_confirm("Would you like to reconfigure anyway?")) {
      # Continue to setup
    } else {
      cli::cli_text("Run {.fn check_api_keys} anytime to verify your configuration.")
      return(invisible(status))
    }
  }

  cli::cli_text("")

  if (use_1password) {
    setup_with_1password()
  } else {
    setup_interactive()
  }

  # Re-check after setup
  cli::cli_text("")
  cli::cli_h2("Verifying Configuration")
  new_status <- check_api_keys(verbose = TRUE)

  if (new_status$all_configured) {
    cli::cli_text("")
    cli::cli_alert_success("Setup complete! You're ready to use counselor.")
    cli::cli_text("Run {.fn counselor::install_hooks} in any project to enable voice reviews.")
  } else {
    cli::cli_text("")
    cli::cli_alert_warning("Some keys are still missing. Run {.fn counselor_setup} again to continue.")
  }

  invisible(new_status)
}


#' Check API Key Configuration
#'
#' Checks which API keys are configured for counselor.
#'
#' @param verbose Logical. If TRUE, prints status messages. Default is TRUE.
#'
#' @return A list with:
#'   - `all_configured`: TRUE if all required keys are set
#'   - `anthropic`: TRUE if ANTHROPIC_API_KEY is set
#'   - `deepgram`: TRUE if DEEPGRAM_API_KEY is set
#'   - `cartesia`: TRUE if CARTESIA_API_KEY is set
#'
#' @examples
#' check_api_keys()
#'
#' @export
check_api_keys <- function(verbose = TRUE) {
  keys <- list(
    anthropic = list(
      env_var = "ANTHROPIC_API_KEY",
      name = "Anthropic (Claude)",
      purpose = "Conversation intelligence",
      url = "https://console.anthropic.com/"
    ),
    deepgram = list(
      env_var = "DEEPGRAM_API_KEY",
      name = "Deepgram",
      purpose = "Speech-to-text",
      url = "https://console.deepgram.com/"
    ),
    cartesia = list(
      env_var = "CARTESIA_API_KEY",
      name = "Cartesia",
      purpose = "Text-to-speech",
      url = "https://cartesia.ai/"
    )
  )

  status <- list()

  if (verbose) {
    cli::cli_h2("API Key Status")
  }

  for (key_id in names(keys)) {
    key_info <- keys[[key_id]]
    value <- Sys.getenv(key_info$env_var, unset = "")
    is_set <- nzchar(value)
    status[[key_id]] <- is_set

    if (verbose) {
      if (is_set) {
        # Show masked preview
        preview <- mask_key(value)
        cli::cli_alert_success("{key_info$name}: {.val {preview}}")
      } else {
        cli::cli_alert_danger("{key_info$name}: {.emph not configured}")
      }
    }
  }

  status$all_configured <- all(unlist(status))
  status
}


#' @noRd
setup_interactive <- function() {
  cli::cli_h2("Setting Up API Keys")
  cli::cli_text("Keys will be saved to {.path ~/.Renviron} (global configuration).")
  cli::cli_text("")

  keys_to_set <- list()

  # Anthropic
  if (!nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
    cli::cli_h3("Anthropic API Key")
    cli::cli_text("Get your key at: {.url https://console.anthropic.com/}")
    cli::cli_text("Used for: Claude conversation intelligence")
    cli::cli_text("")

    key <- prompt_for_key("ANTHROPIC_API_KEY")
    if (nzchar(key)) keys_to_set$ANTHROPIC_API_KEY <- key
  }

  # Deepgram
  if (!nzchar(Sys.getenv("DEEPGRAM_API_KEY"))) {
    cli::cli_h3("Deepgram API Key")
    cli::cli_text("Get your key at: {.url https://console.deepgram.com/}")
    cli::cli_text("Used for: Speech-to-text (Nova-2 model)")
    cli::cli_text("")

    key <- prompt_for_key("DEEPGRAM_API_KEY")
    if (nzchar(key)) keys_to_set$DEEPGRAM_API_KEY <- key
  }

  # Cartesia
  if (!nzchar(Sys.getenv("CARTESIA_API_KEY"))) {
    cli::cli_h3("Cartesia API Key")
    cli::cli_text("Get your key at: {.url https://cartesia.ai/}")
    cli::cli_text("Used for: Text-to-speech (Sonic-2 model)")
    cli::cli_text("")

    key <- prompt_for_key("CARTESIA_API_KEY")
    if (nzchar(key)) keys_to_set$CARTESIA_API_KEY <- key
  }

  if (length(keys_to_set) > 0) {
    write_to_renviron(keys_to_set)

    # Reload environment
    cli::cli_text("")
    cli::cli_alert_info("Reloading environment variables...")
    readRenviron("~/.Renviron")
  } else {
    cli::cli_alert_info("No new keys to configure.")
  }
}


#' @noRd
setup_with_1password <- function() {
  cli::cli_h2("1Password CLI Integration")
  cli::cli_text("")

  # Check if op CLI is available
  op_available <- tryCatch({
    result <- system2("op", "--version", stdout = TRUE, stderr = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(e) FALSE)

  if (!op_available) {
    cli::cli_alert_danger("1Password CLI (op) not found.")
    cli::cli_text("")
    cli::cli_text("Install it from: {.url https://developer.1password.com/docs/cli/get-started/}")
    cli::cli_text("")
    cli::cli_text("After installing, run:")
    cli::cli_code("op signin")
    cli::cli_text("")

    if (cli_confirm("Would you like to set up keys manually instead?")) {
      setup_interactive()
    }
    return(invisible(NULL))
  }

  cli::cli_alert_success("1Password CLI detected!")
  cli::cli_text("")

  cli::cli_h3("Option 1: Store references in .Renviron")
  cli::cli_text("Add these lines to {.path ~/.Renviron}:")
  cli::cli_text("")
  cli::cli_code(c(
    "# counselor API keys (loaded via 1Password at session start)",
    "# Run: source(\"~/.Rprofile_1password\") in your .Rprofile",
    ""
  ))

  cli::cli_text("")
  cli::cli_h3("Option 2: Load dynamically via .Rprofile")
  cli::cli_text("Add this to {.path ~/.Rprofile}:")
  cli::cli_text("")
  cli::cli_code(c(
    "# Load API keys from 1Password (if op is signed in)",
    "if (Sys.which(\"op\") != \"\") {",
    "  tryCatch({",
    "    Sys.setenv(",
    "      ANTHROPIC_API_KEY = system2(\"op\", c(\"read\", \"op://Vault/Anthropic/api-key\"), stdout = TRUE),",
    "      DEEPGRAM_API_KEY = system2(\"op\", c(\"read\", \"op://Vault/Deepgram/api-key\"), stdout = TRUE),",
    "      CARTESIA_API_KEY = system2(\"op\", c(\"read\", \"op://Vault/Cartesia/api-key\"), stdout = TRUE)",
    "    )",
    "  }, error = function(e) message(\"1Password: \", e$message))",
    "}"
  ))

  cli::cli_text("")
  cli::cli_alert_info("Replace {.val Vault} with your vault name and adjust item paths as needed.")
  cli::cli_text("")

  cli::cli_h3("Finding your 1Password paths")
  cli::cli_text("List your vaults:")
  cli::cli_code("op vault list")
  cli::cli_text("")
  cli::cli_text("List items in a vault:")
  cli::cli_code("op item list --vault=\"Your Vault\"")
  cli::cli_text("")
  cli::cli_text("Get item details:")
  cli::cli_code("op item get \"Item Name\" --vault=\"Your Vault\"")

  cli::cli_text("")

  if (cli_confirm("Would you like me to help create .Rprofile entries interactively?")) {
    setup_1password_interactive()
  }
}


#' @noRd
setup_1password_interactive <- function() {
  cli::cli_h3("1Password Interactive Setup")
  cli::cli_text("")

  vault <- readline_trim("Enter your 1Password vault name: ")
  if (!nzchar(vault)) {
    cli::cli_alert_warning("No vault specified. Aborting.")
    return(invisible(NULL))
  }

  cli::cli_text("")
  cli::cli_text("For each service, enter the item name and field name in your 1Password vault.")
  cli::cli_text("Format: {.val item-name/field-name} (e.g., {.val Anthropic/api-key})")
  cli::cli_text("")

  refs <- list()

  # Anthropic
  cli::cli_alert_info("Anthropic API Key:")
  ref <- readline_trim("  Item/field path (or press Enter to skip): ")
  if (nzchar(ref)) refs$ANTHROPIC_API_KEY <- paste0("op://", vault, "/", ref)

  # Deepgram
  cli::cli_alert_info("Deepgram API Key:")
  ref <- readline_trim("  Item/field path (or press Enter to skip): ")
  if (nzchar(ref)) refs$DEEPGRAM_API_KEY <- paste0("op://", vault, "/", ref)

  # Cartesia
  cli::cli_alert_info("Cartesia API Key:")
  ref <- readline_trim("  Item/field path (or press Enter to skip): ")
  if (nzchar(ref)) refs$CARTESIA_API_KEY <- paste0("op://", vault, "/", ref)

  if (length(refs) == 0) {
    cli::cli_alert_warning("No paths specified.")
    return(invisible(NULL))
  }

  cli::cli_text("")
  cli::cli_h3("Generated .Rprofile code")
  cli::cli_text("Add this to {.path ~/.Rprofile}:")
  cli::cli_text("")

  code_lines <- c(
    "# Load counselor API keys from 1Password",
    "if (Sys.which(\"op\") != \"\") {",
    "  tryCatch({"
  )

  setenv_parts <- character()
  for (key in names(refs)) {
    setenv_parts <- c(setenv_parts, sprintf(
      "      %s = system2(\"op\", c(\"read\", \"%s\"), stdout = TRUE)",
      key, refs[[key]]
    ))
  }

  code_lines <- c(
    code_lines,
    "    Sys.setenv(",
    paste(setenv_parts, collapse = ",\n"),
    "    )",
    "  }, error = function(e) message(\"1Password: \", e$message))",
    "}"
  )

  cli::cli_code(code_lines)

  cli::cli_text("")

  if (cli_confirm("Would you like to append this to ~/.Rprofile now?")) {
    write_1password_rprofile(refs)
    cli::cli_alert_success("Added to ~/.Rprofile")
    cli::cli_alert_info("Restart R to load your keys from 1Password.")
  }
}


#' @noRd
write_1password_rprofile <- function(refs) {
  rprofile_path <- path.expand("~/.Rprofile")

  # Create backup if exists
  if (file.exists(rprofile_path)) {
    backup_path <- paste0(rprofile_path, ".backup_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    file.copy(rprofile_path, backup_path)
    cli::cli_alert_info("Backed up existing .Rprofile to {.path {backup_path}}")
  }

  setenv_parts <- character()
  for (key in names(refs)) {
    setenv_parts <- c(setenv_parts, sprintf(
      '      %s = system2("op", c("read", "%s"), stdout = TRUE)',
      key, refs[[key]]
    ))
  }

  code_block <- paste(c(
    "",
    "# Load counselor API keys from 1Password",
    "# Added by counselor_setup() on " %+% format(Sys.time(), "%Y-%m-%d"),
    'if (Sys.which("op") != "") {',
    "  tryCatch({",
    "    Sys.setenv(",
    paste(setenv_parts, collapse = ",\n"),
    "    )",
    '  }, error = function(e) message("1Password: ", e$message))',
    "}"
  ), collapse = "\n")

  cat(code_block, file = rprofile_path, append = TRUE)
}


#' @noRd
prompt_for_key <- function(key_name) {
  # Try to use askpass for masked input if available
  if (requireNamespace("askpass", quietly = TRUE)) {
    key <- tryCatch(
      askpass::askpass(paste0("Enter ", key_name, ": ")),
      error = function(e) NULL
    )
    if (!is.null(key)) return(key)
  }

  # Fall back to readline (visible input)
  cli::cli_alert_info("(Tip: Install {.pkg askpass} for masked input)")
  readline_trim(paste0("Enter ", key_name, " (or press Enter to skip): "))
}


#' @noRd
readline_trim <- function(prompt) {
  trimws(readline(prompt))
}


#' @noRd
cli_confirm <- function(question) {
  response <- tolower(readline_trim(paste0(question, " (y/n): ")))
  response %in% c("y", "yes")
}


#' @noRd
write_to_renviron <- function(keys) {
  renviron_path <- path.expand("~/.Renviron")

  # Create backup if exists
  if (file.exists(renviron_path)) {
    backup_path <- paste0(renviron_path, ".backup_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    file.copy(renviron_path, backup_path)
    cli::cli_alert_info("Backed up existing .Renviron to {.path {backup_path}}")
  }

  # Read existing content
  existing <- if (file.exists(renviron_path)) {
    readLines(renviron_path, warn = FALSE)
  } else {
    character()
  }

  # Remove any existing counselor keys (to avoid duplicates)
  key_names <- names(keys)
  pattern <- paste0("^(", paste(key_names, collapse = "|"), ")=")
  existing <- existing[!grepl(pattern, existing)]

  # Add new keys with comment header
  new_lines <- c(
    "",
    "# counselor API keys",
    paste0("# Added by counselor_setup() on ", format(Sys.time(), "%Y-%m-%d"))
  )

  for (key_name in names(keys)) {
    new_lines <- c(new_lines, paste0(key_name, "=", keys[[key_name]]))
  }

  # Write back
  writeLines(c(existing, new_lines), renviron_path)
  cli::cli_alert_success("Saved to {.path {renviron_path}}")
}


#' @noRd
mask_key <- function(key) {
  if (nchar(key) <= 8) {
    return(paste(rep("*", nchar(key)), collapse = ""))
  }
  paste0(substr(key, 1, 4), "...", substr(key, nchar(key) - 3, nchar(key)))
}


#' @noRd
`%+%` <- function(a, b) paste0(a, b)
