# Tests for review session phrase detection
# These test the pure R functions that don't require API calls

test_that("is_approval detects approval phrases", {

  # Direct approvals

  expect_true(counselor:::is_approval("approve"))

  expect_true(counselor:::is_approval("Approve"))

  expect_true(counselor:::is_approval("APPROVE"))
  expect_true(counselor:::is_approval("approved"))
  expect_true(counselor:::is_approval("Approved!"))

 # Casual approvals
  expect_true(counselor:::is_approval("looks good"))
  expect_true(counselor:::is_approval("Looks good to me"))
  expect_true(counselor:::is_approval("LGTM"))
  expect_true(counselor:::is_approval("lgtm"))
  expect_true(counselor:::is_approval("ship it"))
  expect_true(counselor:::is_approval("Ship it!"))

  # Action approvals
 expect_true(counselor:::is_approval("go ahead"))
  expect_true(counselor:::is_approval("Go ahead and commit"))
  expect_true(counselor:::is_approval("commit"))
  expect_true(counselor:::is_approval("yes commit"))
  expect_true(counselor:::is_approval("yes, commit"))
  expect_true(counselor:::is_approval("proceed"))
  expect_true(counselor:::is_approval("do it"))

  # Other approvals
  expect_true(counselor:::is_approval("good to go"))
  expect_true(counselor:::is_approval("all good"))
  expect_true(counselor:::is_approval("sounds good"))
})

test_that("is_approval rejects non-approval phrases", {
  expect_false(counselor:::is_approval("what does this function do"))
  expect_false(counselor:::is_approval("can you explain the changes"))
  expect_false(counselor:::is_approval("I have a question"))
  expect_false(counselor:::is_approval("wait"))
  expect_false(counselor:::is_approval("abort"))
  expect_false(counselor:::is_approval("not sure about this"))
  expect_false(counselor:::is_approval("goodbye"))

  # Edge cases - approval words not at start
  expect_false(counselor:::is_approval("I don't approve of this"))
  expect_false(counselor:::is_approval("does this look good"))
})

test_that("is_rejection detects rejection phrases", {
  # Direct rejections
  expect_true(counselor:::is_rejection("abort"))
  expect_true(counselor:::is_rejection("Abort"))
  expect_true(counselor:::is_rejection("ABORT"))
  expect_true(counselor:::is_rejection("reject"))
  expect_true(counselor:::is_rejection("cancel"))

  # Pause/hold rejections
  expect_true(counselor:::is_rejection("stop"))
  expect_true(counselor:::is_rejection("wait"))
  expect_true(counselor:::is_rejection("hold"))
  expect_true(counselor:::is_rejection("hold on"))

  # Explicit rejections
  expect_true(counselor:::is_rejection("don't commit"))
  expect_true(counselor:::is_rejection("do not commit"))
  expect_true(counselor:::is_rejection("no abort"))
  expect_true(counselor:::is_rejection("no, abort"))
  expect_true(counselor:::is_rejection("no cancel"))
  expect_true(counselor:::is_rejection("no, cancel"))

  # Nevermind variations
  expect_true(counselor:::is_rejection("nevermind"))
  expect_true(counselor:::is_rejection("never mind"))
})

test_that("is_rejection rejects non-rejection phrases", {
  expect_false(counselor:::is_rejection("approve"))
  expect_false(counselor:::is_rejection("looks good"))
  expect_false(counselor:::is_rejection("what is this"))
  expect_false(counselor:::is_rejection("can you explain"))
  expect_false(counselor:::is_rejection("goodbye"))

  # Edge cases - rejection words not at start
  expect_false(counselor:::is_rejection("I want to abort later maybe"))
  expect_false(counselor:::is_rejection("should we cancel this"))
})

test_that("is_exit detects exit phrases", {
  # Goodbye variations
  expect_true(counselor:::is_exit("goodbye"))
  expect_true(counselor:::is_exit("Goodbye"))
  expect_true(counselor:::is_exit("good bye"))
  expect_true(counselor:::is_exit("bye"))
  expect_true(counselor:::is_exit("Bye!"))

  # Exit/quit
  expect_true(counselor:::is_exit("exit"))
  expect_true(counselor:::is_exit("quit"))
  expect_true(counselor:::is_exit("end session"))

  # Completion phrases
  expect_true(counselor:::is_exit("I'm done"))
  expect_true(counselor:::is_exit("that's all"))
  expect_true(counselor:::is_exit("thanks that's all"))
  expect_true(counselor:::is_exit("thanks, that's all"))
  expect_true(counselor:::is_exit("no more questions"))
})

test_that("is_exit rejects non-exit phrases", {
  expect_false(counselor:::is_exit("approve"))
  expect_false(counselor:::is_exit("abort"))
  expect_false(counselor:::is_exit("what does this do"))
  expect_false(counselor:::is_exit("tell me more"))

  # Edge cases
  expect_false(counselor:::is_exit("say goodbye to the old code"))
  expect_false(counselor:::is_exit("we should exit this function"))
})

test_that("phrase detection handles edge cases", {
  # Empty/null input
  expect_false(counselor:::is_approval(""))
  expect_false(counselor:::is_approval("   "))
  expect_false(counselor:::is_rejection(""))
  expect_false(counselor:::is_exit(""))

  # Whitespace handling
  expect_true(counselor:::is_approval("  approve  "))
  expect_true(counselor:::is_rejection("  abort  "))
  expect_true(counselor:::is_exit("  goodbye  "))

  # Mixed case
  expect_true(counselor:::is_approval("ApPrOvE"))
  expect_true(counselor:::is_rejection("AbOrT"))
  expect_true(counselor:::is_exit("GoOdByE"))
})

test_that("approval, rejection, and exit are mutually exclusive for clear inputs", {
  # An approval phrase should not be detected as rejection or exit
  expect_true(counselor:::is_approval("approve"))
  expect_false(counselor:::is_rejection("approve"))
  expect_false(counselor:::is_exit("approve"))

  # A rejection phrase should not be detected as approval or exit
  expect_false(counselor:::is_approval("abort"))
  expect_true(counselor:::is_rejection("abort"))
  expect_false(counselor:::is_exit("abort"))

  # An exit phrase should not be detected as approval or rejection
  expect_false(counselor:::is_approval("goodbye"))
  expect_false(counselor:::is_rejection("goodbye"))
  expect_true(counselor:::is_exit("goodbye"))
})
