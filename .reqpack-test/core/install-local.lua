return {
  name = "homebrew install local unsupported",
  request = {
    action = "install",
    system = "homebrew",
    localPath = "/tmp/homebrew.rb",
  },
  fakeExec = {},
  expect = {
    success = false,
    events = { "failed", "unavailable" },
    eventPayloads = {
      failed = "homebrew local installs are not supported",
      unavailable = "{path=/tmp/homebrew.rb, reason=local-install-unsupported}",
    },
  }
}
