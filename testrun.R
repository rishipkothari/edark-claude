devtools::load_all(".", quiet = TRUE)
shiny::runApp(
  edark(liver_tx),
  host = "127.0.0.1",
  port = 4321,
  launch.browser = FALSE
)
