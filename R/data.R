#' Synthetic liver transplant dataset
#'
#' A synthetic dataset of 120 simulated liver transplant cases, designed for
#' testing and demonstrating the EDARK GUI. Clinical correlations are baked in
#' (EAD risk elevated for DCD donors and high intraoperative lactate; AKI risk
#' scales with MELD and EAD) so the distributions are interesting to explore.
#'
#' `case_date` is stored as `Date` and will be auto-cast to `POSIXct` by
#' `edark()` at launch.
#'
#' @format A data frame with 120 rows and 13 columns:
#' \describe{
#'   \item{patient_mrn}{Integer. 7-digit medical record number.}
#'   \item{case_date}{Date. Transplant date (2019-06-01 to 2023-06-01).}
#'   \item{preop_meld}{Integer. Pre-operative MELD score (5–40).}
#'   \item{preop_hb}{Numeric. Pre-operative haemoglobin in g/dL (5–15).}
#'   \item{liver_donor_type}{Factor. Donor category: `dbd`, `dcd`, `living donor`.}
#'   \item{intraop_max_lactate}{Numeric. Intraoperative peak lactate in mmol/L (2–10).}
#'   \item{ivc_clamp_type}{Factor. IVC technique: `full clamp` or `piggyback`.}
#'   \item{ead}{Logical. Early allograft dysfunction.}
#'   \item{postop_aki_stage}{Ordered factor (1–3). Post-operative AKI stage; `NA` if no AKI.}
#'   \item{preop_intubation}{Logical. Intubated pre-operatively.}
#'   \item{preop_icu}{Logical. In ICU pre-operatively.}
#'   \item{postop_intubation}{Logical. Intubated post-operatively.}
#'   \item{postop_mechanical_ventilation_hours}{Integer. Hours on mechanical ventilation post-op; `0` if not intubated.}
#' }
#' @source Synthetically generated via \code{liver_tx_sample.R}.
"liver_tx"
