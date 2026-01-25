#' Python Environment Setup
#'
#' Functions for managing Python dependencies required by counselor.
#'
#' @name python-setup
NULL

.onLoad <- function(libname, pkgname) {
  # Declare Python dependencies - will be provisioned when Python initializes
  reticulate::py_require(c(
    "pipecat-ai[cartesia,deepgram]",
    "pyaudio",
    "python-dotenv",
    "numpy"
  ))
}

#' Check Python Dependencies
#'
#' Verifies that all required Python packages are available. Call this before
#' using voice features to get a helpful error message if setup is incomplete.
#'
#' @return Invisible `TRUE` if all dependencies are available.
#' @export
#'
#' @examples
#' \dontrun{
#' ensure_python()
#' }
ensure_python <- function() {
  required <- c("pipecat", "pyaudio", "deepgram", "cartesia")
  missing <- character()

  for (pkg in required) {
    if (!reticulate::py_module_available(pkg)) {
      missing <- c(missing, pkg)
    }
  }

  if (length(missing) > 0) {
    cli::cli_abort(c(
      "Missing Python dependencies: {.pkg {missing}}",
      "i" = "Run {.code reticulate::py_config()} to check your Python setup.",
      "i" = "Dependencies should auto-install on first use.",
      "i" = "If issues persist, try: {.code reticulate::py_install(c('pipecat-ai[cartesia,deepgram]', 'pyaudio'))}"
    ))
  }

  invisible(TRUE)
}

#' Check API Keys
#'
#' Verifies that required API keys are set in environment variables.
#'
#' @param services Character vector of services to check. Options: "anthropic",
#'   "deepgram", "cartesia".
#' @return Invisible `TRUE` if all keys are present.
#' @export
#'
#' @examples
#' \dontrun{
#' check_api_keys()
#' }
check_api_keys <- function(services = c("anthropic", "deepgram", "cartesia")) {
  key_map <- list(
    anthropic = "ANTHROPIC_API_KEY",
    deepgram = "DEEPGRAM_API_KEY",
    cartesia = "CARTESIA_API_KEY"
  )

  missing <- character()

  for (service in services) {
    key_name <- key_map[[service]]
    if (is.null(key_name)) next

    if (nchar(Sys.getenv(key_name)) == 0) {
      missing <- c(missing, key_name)
    }
  }

  if (length(missing) > 0) {
    cli::cli_abort(c(
      "Missing API keys: {.envvar {missing}}",
      "i" = "Set these in your {.file .Renviron} file or export them in your shell.",
      "i" = "Example: {.code Sys.setenv(ANTHROPIC_API_KEY = 'your-key-here')}"
    ))
  }

  invisible(TRUE)
}
