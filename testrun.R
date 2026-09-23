options(repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"))
options(pkgType="binary")
options(install.packages.compile.from.source = "never")
devtools::load_all(".", quiet = TRUE)
shiny::runApp(
  edark(liver_tx),
  host = "127.0.0.1",
  port = 4321,
  launch.browser = FALSE
)
