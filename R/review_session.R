#' Code Review Session
#'
#' Voice-powered code review using ellmer for conversation intelligence.
#'
#' @name review-session
NULL

#' Review Staged Commit
#'
#' Starts a voice conversation to review staged git changes. The AI will
#' summarize the changes, highlight any concerns, and guide the developer
#' through an approval process.
#'
#' @param path Path to the git repository. Default is current directory.
#' @param voice Logical. If TRUE (default), use voice I/O. If FALSE, use
#'   console text input/output for testing.
#' @param model Character. The Claude model to use. Default is "claude-sonnet-4-20250514".
#' @param timeout_secs Numeric. Maximum seconds to wait for voice input.
#'
#' @return A list with:
#'   - `approved`: Logical indicating whether the commit was approved
#'   - `transcript`: The full conversation transcript
#'   - `diff_info`: The diff information that was reviewed
#'   - `chat`: The ellmer chat object (for inspection/logging)
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Review staged changes with voice
#' result <- review_commit()
#'
#' # Review without voice (for testing)
#' result <- review_commit(voice = FALSE)
#'
#' # Check if approved
#' if (result$approved) {
#'   message("Commit approved!")
#' }
#' }
review_commit <- function(path = ".",
                          voice = TRUE,
                          model = "claude-sonnet-4-20250514",
                          timeout_secs = 15) {
  # Check dependencies
  check_api_keys("anthropic")
  if (voice) {
    check_api_keys(c("deepgram", "cartesia"))
    ensure_python()
  }

  # Get staged changes
  cli::cli_alert_info("Analyzing staged changes...")
  diff_info <- get_staged_diff(path)

  if (length(diff_info$files) == 0) {
    cli::cli_alert_warning("No staged changes to review.")
    return(invisible(list(
      approved = NULL,
      transcript = NULL,
      diff_info = diff_info,
      chat = NULL
    )))
  }

  cli::cli_alert_success("Found {length(diff_info$files)} file(s) to review")

  # Build system prompt with diff context
  system_prompt <- build_review_prompt(diff_info)

  # Create ellmer chat
  chat <- ellmer::chat_anthropic(
    model = model,
    system_prompt = system_prompt
  )

  # Start the review conversation
  cli::cli_rule("Code Review Session")

  # Get initial response from AI
  intro_prompt <- "Please briefly introduce the changes you see and any concerns."
  intro_response <- chat$chat(intro_prompt, echo = FALSE)

  output_response(intro_response, voice)

  # Enter conversation loop
  result <- conversation_loop(chat, voice, timeout_secs)

  # Log the session
  log_session(chat, result, diff_info)

  cli::cli_rule()

  list(
    approved = result$approved,
    transcript = result$transcript,
    diff_info = diff_info,
    chat = chat
  )
}

#' Build Review System Prompt
#'
#' @param diff_info List from get_staged_diff()
#' @return Character string with system prompt
#' @keywords internal
build_review_prompt <- function(diff_info) {
  # Load template - try installed location first, then dev location
  template_path <- system.file("prompts", "review_system.txt", package = "counselor")

  if (!nzchar(template_path) || !file.exists(template_path)) {
    # Try development location
    template_path <- file.path("inst", "prompts", "review_system.txt")
  }

  if (!file.exists(template_path)) {
    # Fallback if template not found
    template <- "You are reviewing code changes. Context:\n{diff_context}\n\nBe concise and helpful."
  } else {
    template <- paste(readLines(template_path), collapse = "\n")
  }

  # Format diff context
  diff_context <- format_diff_for_review(diff_info)

  # Substitute into template
  glue::glue(template, diff_context = diff_context, .open = "{", .close = "}")
}

#' Conversation Loop
#'
#' @param chat ellmer chat object
#' @param voice Logical for voice mode
#' @param timeout_secs Voice input timeout
#' @return List with approved status and transcript
#' @keywords internal
conversation_loop <- function(chat, voice, timeout_secs) {
  transcript <- list()
  max_turns <- 20  # Safety limit

  for (turn in seq_len(max_turns)) {
    # Get user input
    user_input <- get_user_input(voice, timeout_secs)

    if (is.null(user_input) || nchar(trimws(user_input)) == 0) {
      output_response("I didn't catch that. Could you repeat?", voice)
      next
    }

    transcript[[length(transcript) + 1]] <- list(role = "user", content = user_input)

    # Check for approval/rejection/exit
    if (is_approval(user_input)) {
      farewell <- "Approved. Proceeding with the commit. Good luck!"
      output_response(farewell, voice)
      transcript[[length(transcript) + 1]] <- list(role = "assistant", content = farewell)
      return(list(approved = TRUE, transcript = transcript))
    }

    if (is_rejection(user_input)) {
      farewell <- "Understood. Aborting the commit so you can make changes. Let me know when you're ready to review again."
      output_response(farewell, voice)
      transcript[[length(transcript) + 1]] <- list(role = "assistant", content = farewell)
      return(list(approved = FALSE, transcript = transcript))
    }

    if (is_exit(user_input)) {
      farewell <- "Goodbye! The commit is still staged whenever you're ready to review again."
      output_response(farewell, voice)
      transcript[[length(transcript) + 1]] <- list(role = "assistant", content = farewell)
      return(list(approved = NULL, exited = TRUE, transcript = transcript))
    }

    # Continue conversation with AI
    response <- chat$chat(user_input, echo = FALSE)
    transcript[[length(transcript) + 1]] <- list(role = "assistant", content = response)
    output_response(response, voice)
  }

  # Max turns reached
  cli::cli_alert_warning("Maximum conversation turns reached")
  return(list(approved = FALSE, transcript = transcript))
}

#' Get User Input
#'
#' @param voice Logical for voice mode
#' @param timeout_secs Voice timeout
#' @return Character string of user input
#' @keywords internal
get_user_input <- function(voice, timeout_secs) {
  if (voice) {
    voice_listen(timeout_secs = timeout_secs)
  } else {
    readline(prompt = "You: ")
  }
}

#' Output Response
#'
#' @param text Response text
#' @param voice Logical for voice mode
#' @keywords internal
output_response <- function(text, voice) {
  # Always print to console
  cli::cli_alert_info("Counselor: {text}")

  if (voice) {
    voice_speak(text)
  }
}

#' Check for Approval Phrases
#'
#' @param text User input text
#' @return Logical
#' @keywords internal
is_approval <- function(text) {
  text <- tolower(trimws(text))
  approval_patterns <- c(
    "^approve",
    "^approved",
    "looks good",
    "lgtm",
    "^ship it",
    "^go ahead",
    "^commit",
    "^yes,? commit",
    "^proceed",
    "^do it",
    "^good to go",
    "^all good",
    "sounds good"
  )

  any(vapply(approval_patterns, function(p) grepl(p, text), logical(1)))
}

#' Check for Rejection Phrases
#'
#' @param text User input text
#' @return Logical
#' @keywords internal
is_rejection <- function(text) {

  text <- tolower(trimws(text))
  rejection_patterns <- c(
    "^abort",
    "^reject",
    "^cancel",
    "^stop",
    "^wait",
    "^hold",
    "^don't commit",
    "^do not commit",
    "^no,? abort",
    "^no,? cancel",
    "^nevermind",
    "^never mind"
  )

  any(vapply(rejection_patterns, function(p) grepl(p, text), logical(1)))
}

#' Check for Exit Phrases
#'
#' Detects when user wants to gracefully end the session without
#' making a decision about the commit.
#'
#' @param text User input text
#' @return Logical
#' @keywords internal
is_exit <- function(text) {
  text <- tolower(trimws(text))
  exit_patterns <- c(
    "^goodbye",
    "^good bye",
    "^bye",
    "^exit",
    "^quit",
    "^end session",
    "^i'm done",
    "^that's all",
    "^thanks,? that's all",
    "^no more questions"
  )

  any(vapply(exit_patterns, function(p) grepl(p, text), logical(1)))
}

#' Start Manual Voice Session
#'
#' Starts a general-purpose voice conversation session without git context.
#' Useful for testing or having freeform discussions about code.
#'
#' @param system_prompt Optional custom system prompt.
#' @param model Character. The Claude model to use.
#' @param timeout_secs Voice input timeout.
#'
#' @return The ellmer chat object for further interaction.
#' @export
#'
#' @examples
#' \dontrun{
#' # Start a general session
#' chat <- start_session()
#'
#' # Custom system prompt
#' chat <- start_session(system_prompt = "You are a helpful R programming assistant.")
#' }
start_session <- function(system_prompt = NULL,
                          model = "claude-sonnet-4-20250514",
                          timeout_secs = 15) {
  check_api_keys(c("anthropic", "deepgram", "cartesia"))
  ensure_python()

  if (is.null(system_prompt)) {
    system_prompt <- "You are a helpful voice assistant for R developers. Keep responses concise (under 30 seconds of speech). Be friendly and helpful."
  }

  chat <- ellmer::chat_anthropic(
    model = model,
    system_prompt = system_prompt
  )

  cli::cli_rule("Voice Session Started")
  cli::cli_alert_info("Say 'goodbye' or 'exit' to end the session.")

  repeat {
    user_input <- voice_listen(timeout_secs = timeout_secs)

    if (is.null(user_input) || nchar(trimws(user_input)) == 0) {
      voice_speak("I didn't catch that. Could you repeat?")
      next
    }

    # Check for exit
    if (grepl("^(goodbye|exit|quit|end session|stop)", tolower(user_input))) {
      voice_speak("Goodbye! Have a great coding session.")
      break
    }

    response <- chat$chat(user_input, echo = FALSE)
    cli::cli_alert_info("Counselor: {response}")
    voice_speak(response)
  }

  cli::cli_rule()
  invisible(chat)
}
