return {
  name = "real info smoke",
  request = {
    action = "info",
    system = "homebrew",
    prompt = "wget",
  },
  expect = {
    success = true,
  }
}
