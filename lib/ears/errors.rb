module Ears
  # Error that is raised when the Bunny recovery attempts are exhausted.
  class MaxRecoveryAttemptsExhaustedError < StandardError
  end

  # Base error class for publisher-related errors.
  class PublishError < StandardError
  end

  # Error raised when a publisher confirmation times out.
  class PublishConfirmationTimeout < PublishError
  end

  # Error raised when a message is nacked by the broker.
  class PublishNacked < PublishError
  end
end
