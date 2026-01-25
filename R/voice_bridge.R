#' Voice Bridge Functions
#'
#' R wrappers for Python voice I/O functionality.
#'
#' @name voice-bridge
NULL

#' Get or Create Voice I/O Module
#'
#' Returns the cached VoiceIO Python object, creating it if necessary.
#'
#' @param voice_id Cartesia voice ID for text-to-speech.
#' @return A Python VoiceIO object.
#' @keywords internal
get_voice_io <- function(voice_id = NULL) {
  ensure_python()
  check_api_keys(c("deepgram", "cartesia"))

  # Return cached instance if available and voice_id matches
  if (!is.null(pkg_env$voice_io)) {
    if (is.null(voice_id) || identical(pkg_env$voice_id, voice_id)) {
      return(pkg_env$voice_io)
    }
  }

  # Source Python module
  # Try installed package location first, then dev location
 py_path <- system.file("python", "voice_io.py", package = "counselor")
  if (!nzchar(py_path) || !file.exists(py_path)) {
    # Try development location (for devtools::load_all)
    py_path <- file.path("inst", "python", "voice_io.py")
  }
  if (!file.exists(py_path)) {
    cli::cli_abort("Python voice module not found. Are you in the package directory?")
  }

  reticulate::source_python(py_path, envir = globalenv())

  # Create VoiceIO instance
  voice_id <- voice_id %||% "a0e99841-438c-4a64-b679-ae501e7d6091"
  pkg_env$voice_io <- create_voice_io(
    deepgram_key = Sys.getenv("DEEPGRAM_API_KEY"),
    cartesia_key = Sys.getenv("CARTESIA_API_KEY"),
    voice_id = voice_id
  )
  pkg_env$voice_id <- voice_id

  pkg_env$voice_io
}

#' Listen for Speech
#'
#' Records audio from the microphone and transcribes it to text using Deepgram.
#'
#' @param timeout_secs Maximum recording duration in seconds. Default is 10.
#' @param voice_id Optional Cartesia voice ID (used for subsequent speak calls).
#'
#' @return A character string containing the transcribed speech.
#' @export
#'
#' @examples
#' \dontrun{
#' # Listen for up to 10 seconds
#' text <- voice_listen()
#'
#' # Listen for up to 30 seconds
#' text <- voice_listen(timeout_secs = 30)
#' }
voice_listen <- function(timeout_secs = 10, voice_id = NULL) {
  voice_io <- get_voice_io(voice_id)
  transcript <- listen_once(voice_io, as.numeric(timeout_secs))

  if (nchar(transcript) == 0) {
    cli::cli_alert_warning("No speech detected")
  } else {
    cli::cli_alert_info("Heard: {.val {transcript}}")
  }

  transcript
}

#' Speak Text
#'
#' Converts text to speech using Cartesia and plays it through the speakers.
#'
#' @param text The text to speak.
#' @param voice_id Optional Cartesia voice ID. If not provided, uses the
#'   previously set voice or the default.
#'
#' @return Invisible NULL.
#' @export
#'
#' @examples
#' \dontrun{
#' voice_speak("Hello! I'm ready to review your code changes.")
#' }
voice_speak <- function(text, voice_id = NULL) {
  if (is.null(text) || nchar(text) == 0) {
    return(invisible(NULL))
  }

  voice_io <- get_voice_io(voice_id)
  speak_text(voice_io, as.character(text))

  invisible(NULL)
}

#' Test Voice Setup
#'
#' Performs a quick test of the voice I/O system by speaking a test message
#' and optionally listening for a response.
#'
#' @param test_listen Logical. If TRUE, also tests speech recognition.
#'
#' @return Invisible TRUE if successful.
#' @export
#'
#' @examples
#' \dontrun{
#' test_voice()
#' test_voice(test_listen = TRUE)
#' }
test_voice <- function(test_listen = FALSE) {
  cli::cli_alert_info("Testing voice output...")
  voice_speak("Hello! Voice output is working correctly.")

  if (test_listen) {
    cli::cli_alert_info("Testing voice input - please say something...")
    text <- voice_listen(timeout_secs = 5)
    cli::cli_alert_success("Voice input test complete. You said: {.val {text}}")
  }

  cli::cli_alert_success("Voice setup verified")
  invisible(TRUE)
}

# Null coalescing operator for convenience
`%||%` <- function(x, y) if (is.null(x)) y else x
