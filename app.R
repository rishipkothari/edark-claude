# Posit Connect Cloud entrypoint.
#
# edark is an R package, not a standalone app: edark(dataset) *returns* a
# shinyApp object rather than running one, and Connect Cloud does not install
# the package. So load the source tree in place. pkgload::load_all() builds the
# namespace from R/, lazy-loads data/, and shims system.file() - which
# R/edark.R (inst/www/edark.css) and R/generate_report.R (inst/report_template.Rmd,
# inst/templates/) both rely on.
#
# Hosted, there is no console to pass a dataset from, so this serves the
# built-in liver_tx demo data.

pkgload::load_all(
  ".",
  export_all      = FALSE,
  helpers         = FALSE,
  attach_testthat = FALSE,
  quiet           = TRUE
)

edark(liver_tx)
