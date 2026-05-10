return {
  name = "real info smoke",
  request = {
    action = "info",
    system = "homebrew",
    prompt = "wget",
  },
  expect = {
    success = true,
    events = { "informed" },
    resultCount = 1,
    resultName = "wget",
  }
}
