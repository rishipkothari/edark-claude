# app.R sits next to an R/ directory, so Shiny's autoloader would source every
# file in R/ into a shared environment before app.R even runs - on top of the
# pkgload::load_all() that app.R does itself. Shiny warns about this ("this
# directory appears to contain an R package"). The option has to be set before
# the app loads, which means here rather than inside app.R.
options(shiny.autoload.r = FALSE)
