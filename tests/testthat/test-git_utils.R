# Tests for git utilities
# Tests for pure helper functions and security concern detection

test_that("calculate_diff_stats counts additions and deletions", {
  diff_text <- "--- a/file.R
+++ b/file.R
@@ -1,3 +1,4 @@
 unchanged line
+added line 1
+added line 2
-removed line"

  stats <- counselor:::calculate_diff_stats(diff_text)
  expect_equal(stats$lines_added, 2)
  expect_equal(stats$lines_removed, 1)
})

test_that("calculate_diff_stats handles empty diff", {
  stats <- counselor:::calculate_diff_stats("")
  expect_equal(stats$lines_added, 0)
  expect_equal(stats$lines_removed, 0)
})

test_that("calculate_diff_stats ignores file headers", {
  # File headers start with --- or +++ and should not be counted
  diff_text <- "--- a/file.R
+++ b/file.R
@@ -1,3 +1,3 @@
 context
+real addition
-real deletion"

  stats <- counselor:::calculate_diff_stats(diff_text)
  expect_equal(stats$lines_added, 1)  # Only the real addition
  expect_equal(stats$lines_removed, 1)  # Only the real deletion
})

test_that("build_diff_summary creates readable summary", {
  files <- c("R/app.R", "R/utils.R", "tests/test-app.R")
  stats <- list(lines_added = 50, lines_removed = 10, files_changed = 3)

  summary <- counselor:::build_diff_summary(files, stats)

  expect_true(grepl("3 file", summary))
  expect_true(grepl("\\+50", summary))
  expect_true(grepl("-10", summary))
  expect_true(grepl("R/app.R", summary))
})

test_that("build_diff_summary handles single file", {
  files <- c("README.md")
  stats <- list(lines_added = 5, lines_removed = 0, files_changed = 1)

  summary <- counselor:::build_diff_summary(files, stats)

  expect_true(grepl("1 file", summary))
})

test_that("detect_security_concerns finds eval() usage", {
  diff_text <- "+  result <- eval(parse(text = user_input))"
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  expect_true(any(grepl("eval", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns finds parse() usage", {
  diff_text <- "+  expr <- parse(text = input)"
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  expect_true(any(grepl("parse", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns finds system() usage", {
  diff_text <- "+  system(paste('ls', user_dir))"
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  expect_true(any(grepl("System command", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns finds SQL injection risks", {
  # The pattern detects dbSendQuery/dbExecute with paste
  diff_text <- '+  dbSendQuery(con, paste("SELECT * FROM", table_name))'
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  # Should detect SQL concatenation
  expect_true(length(concerns) > 0)
  expect_true(any(grepl("SQL|Database", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns finds Shiny renderUI", {
  diff_text <- "+  output$dynamic <- renderUI({ HTML(user_content) })"
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  expect_true(any(grepl("Dynamic UI|renderUI", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns finds hardcoded credentials", {
  diff_text <- '+api_key = "sk-1234567890abcdef"'
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  expect_true(any(grepl("credential", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns finds file deletion", {
  diff_text <- "+  unlink(temp_file)"
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  expect_true(any(grepl("File deletion", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns finds download.file", {
  diff_text <- '+  download.file("http://example.com/data.csv", "data.csv")'
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  expect_true(any(grepl("download", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns flags sensitive files", {
  diff_text <- "+ some change"
  files <- c(".env", "config/secrets.yml", "credentials.json")
  concerns <- counselor:::detect_security_concerns(diff_text, files)

  expect_true(any(grepl("\\.env", concerns)))
  expect_true(any(grepl("secrets", concerns, ignore.case = TRUE)))
  expect_true(any(grepl("credentials", concerns, ignore.case = TRUE)))
})

test_that("detect_security_concerns flags key files", {
  diff_text <- "+ some change"
  files <- c("server.pem", "private.key")
  concerns <- counselor:::detect_security_concerns(diff_text, files)

  expect_true(any(grepl("\\.pem", concerns)))
  expect_true(any(grepl("\\.key", concerns)))
})

test_that("detect_security_concerns returns empty for safe code", {
  diff_text <- "+  x <- 1 + 2
+  y <- mean(c(1, 2, 3))
+  print(y)"
  files <- c("R/math.R")
  concerns <- counselor:::detect_security_concerns(diff_text, files)

  expect_equal(length(concerns), 0)
})

test_that("detect_security_concerns deduplicates concerns", {
  # Multiple eval() uses should only show one concern
  diff_text <- "+  eval(a)
+  eval(b)
+  eval(c)"
  concerns <- counselor:::detect_security_concerns(diff_text, character())

  eval_concerns <- concerns[grepl("eval", concerns, ignore.case = TRUE)]
  expect_equal(length(eval_concerns), 1)
})

test_that("format_diff_for_review handles empty diff", {
  diff_info <- list(
    files = character(),
    summary = "",
    diff_text = "",
    stats = list(lines_added = 0, lines_removed = 0, files_changed = 0),
    concerns = character()
  )

  result <- counselor:::format_diff_for_review(diff_info)
  expect_equal(result, "No staged changes.")
})

test_that("format_diff_for_review includes concerns", {
  diff_info <- list(
    files = c("R/app.R"),
    summary = "1 file changed",
    diff_text = "+ eval(x)",
    stats = list(lines_added = 1, lines_removed = 0, files_changed = 1),
    concerns = c("Use of eval() detected - potential code injection risk")
  )

  result <- counselor:::format_diff_for_review(diff_info)
  expect_true(grepl("CONCERNS DETECTED", result))
  expect_true(grepl("eval", result))
})

test_that("format_diff_for_review truncates long diffs", {
  # Create a diff longer than 8000 characters
  long_diff <- paste(rep("+ this is a long line of code\n", 500), collapse = "")

  diff_info <- list(
    files = c("R/app.R"),
    summary = "1 file changed",
    diff_text = long_diff,
    stats = list(lines_added = 500, lines_removed = 0, files_changed = 1),
    concerns = character()
  )

  result <- counselor:::format_diff_for_review(diff_info)
  expect_true(grepl("truncated", result))
})

# Tests that require a git repository
test_that("get_staged_diff requires git2r", {
  skip_if_not_installed("git2r")
  # If we're in a non-git directory, should error appropriately
  # This test just verifies the function exists and has expected signature
  expect_true(is.function(get_staged_diff))
})

test_that("get_staged_diff returns expected structure", {
  skip_if_not_installed("git2r")
  skip_if_not(dir.exists(".git"), "Not in a git repository")

  result <- get_staged_diff()

  expect_type(result, "list")
  expect_true("files" %in% names(result))
  expect_true("summary" %in% names(result))
  expect_true("diff_text" %in% names(result))
  expect_true("stats" %in% names(result))
  expect_true("concerns" %in% names(result))

  expect_type(result$files, "character")
  expect_type(result$stats, "list")
  expect_true("lines_added" %in% names(result$stats))
  expect_true("lines_removed" %in% names(result$stats))
})
