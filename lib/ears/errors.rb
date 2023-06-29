module Ears
  # Error that is raised when the Bunny recovery attempts are exhausted.
  class MaxRecoveryAttemptsExhaustedError < StandardError
  end
end
