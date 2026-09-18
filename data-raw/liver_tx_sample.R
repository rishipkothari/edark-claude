## data-raw/liver_tx_sample.R
##
## Regenerates data/liver_tx.rda — the synthetic liver transplant dataset
## shipped with edark and used as the default for edark().
##
## Run with:
##   Rscript data-raw/liver_tx_sample.R
##
## Design notes (see ?liver_tx):
##   * n = 500, enough events for ~15 candidate predictors at EPV > 10.
##   * Three deliberate collinearity structures for the Analyze module's
##     collinearity screen:
##       1. preop_meld is the real MELD formula applied to preop_bilirubin,
##          preop_inr and preop_creatinine — near-deterministic.
##       2. recipient_bmi is exactly weight / (height/100)^2.
##       3. intraop_rbc_units is driven by intraop_ebl_ml (r ~ 0.85).
##   * A block of six predictors with genuinely zero effect on every outcome,
##     so stepwise and LASSO can be checked for discarding them.
##   * transplant_center carries real random intercepts on both outcomes.
##   * Missingness is injected last, so the causal structure above is built
##     on complete values.

set.seed(20260917)

n <- 500L

logistic <- function(x) 1 / (1 + exp(-x))
clip     <- function(x, lo, hi) pmin(pmax(x, lo), hi)

# ── Clusters ─────────────────────────────────────────────────────────────────
# 12 centers: above the PF_FEW_CLUSTERS threshold (<10) and with a size CV
# below the PF_UNBALANCED_CLUSTERS threshold (>1), so neither fires by default.
centers  <- sprintf("Center %02d", 1:12)
center_w <- c(14, 12, 11, 10, 9, 8, 8, 7, 6, 6, 5, 4)
transplant_center <- factor(sample(centers, n, TRUE, prob = center_w),
                            levels = centers)

u_los <- stats::setNames(stats::rnorm(12, 0, 0.20), centers)
u_ead <- stats::setNames(stats::rnorm(12, 0, 0.40), centers)
ctr   <- as.character(transplant_center)

# ── Recipient anthropometrics (collinearity structure 2) ─────────────────────
recipient_age       <- round(clip(stats::rnorm(n, 54, 11), 18, 76))
recipient_height_cm <- round(clip(stats::rnorm(n, 170, 9.5), 145, 196), 1)
recipient_weight_kg <- round(clip((recipient_height_cm - 100) * 0.92 +
                                    stats::rnorm(n, 0, 11), 42, 145), 1)
recipient_bmi       <- round(recipient_weight_kg / (recipient_height_cm / 100)^2, 1)

# ── Pre-op labs → MELD (collinearity structure 1) ────────────────────────────
# Distributions are deliberately kept mildly skewed and mostly above the 1.0
# MELD floor: heavier skew makes log() strongly non-linear over the observed
# range, which dilutes the linear correlation with preop_meld and weakens the
# collinearity this structure is meant to demonstrate.
preop_bilirubin  <- round(clip(exp(stats::rnorm(n, 1.30, 0.55)), 0.6, 40.0), 1)
preop_inr        <- round(clip(exp(stats::rnorm(n, 0.45, 0.22)), 0.9,  4.5), 2)
preop_creatinine <- round(clip(exp(stats::rnorm(n, 0.15, 0.45)), 0.4,  6.0), 2)

preop_dialysis <- stats::runif(n) < logistic(-3.4 + 1.25 * (preop_creatinine - 1.4))

# Real MELD: labs floored at 1.0, creatinine capped at 4.0 and set to 4.0 on
# dialysis. This makes preop_meld an (almost) exact function of three columns.
creat_meld <- ifelse(preop_dialysis, 4.0, clip(preop_creatinine, 1.0, 4.0))
preop_meld <- as.integer(round(clip(
  3.78 * log(clip(preop_bilirubin, 1.0, Inf)) +
    11.2 * log(clip(preop_inr, 1.0, Inf)) +
    9.57 * log(creat_meld) + 6.43,
  6, 40)))

# MELD-Na is the UNOS sodium adjustment applied to MELD — a *linear* function of
# it, unlike the log-scale lab formula above. Gives a severe (r ~ 0.97)
# collinear pair that a researcher would plausibly put in one model.
preop_sodium <- round(clip(stats::rnorm(n, 136 - 0.09 * (preop_meld - 22), 3.6),
                           120, 145))
na_adj       <- 137 - clip(preop_sodium, 125, 137)
preop_meld_na <- as.integer(round(clip(
  preop_meld + 1.32 * na_adj - 0.033 * preop_meld * na_adj, 6, 40)))

preop_albumin <- round(clip(stats::rnorm(n, 3.3 - 0.022 * (preop_meld - 22), 0.55),
                            1.4, 5.2), 1)
preop_hb <- round(clip(stats::rnorm(n, 11.4 - 0.10 * (preop_meld - 22) +
                                      0.80 * (preop_albumin - 3.3), 1.7), 5.0, 16.5), 1)

preop_icu        <- stats::runif(n) < logistic(-2.6 + 0.10 * (preop_meld - 22) +
                                                 0.90 * preop_dialysis)
preop_intubation <- preop_icu &
  (stats::runif(n) < logistic(-1.1 + 0.07 * (preop_meld - 22)))

# ── Donor / graft ────────────────────────────────────────────────────────────
liver_donor_type <- factor(
  sample(c("dbd", "dcd", "living donor"), n, TRUE, prob = c(0.55, 0.30, 0.15)),
  levels = c("dbd", "dcd", "living donor")
)
is_living <- liver_donor_type == "living donor"
is_dcd    <- liver_donor_type == "dcd"

donor_age <- round(clip(stats::rnorm(n, 45, 15), 14, 80))
donor_age[is_living] <- round(clip(stats::rnorm(sum(is_living), 37, 9), 19, 60))

cold_ischemia_time_hours <- round(clip(
  ifelse(is_living, stats::rnorm(n, 2.1, 0.6), stats::rnorm(n, 6.6, 1.8)),
  0.8, 14.0), 1)

# ── Intra-operative (collinearity structure 3) ───────────────────────────────
ivc_clamp_type <- factor(ifelse(stats::runif(n) < 0.70, "piggyback", "full clamp"),
                         levels = c("full clamp", "piggyback"))

intraop_ebl_ml <- round(clip(exp(stats::rnorm(
  n,
  7.00 + 0.020 * (preop_meld - 22) + 0.30 * (preop_inr - 1.4) +
    0.18 * (ivc_clamp_type == "full clamp"),
  0.50)), 150, 12000), -1)

intraop_rbc_units <- as.integer(round(clip(
  intraop_ebl_ml / 380 + stats::rnorm(n, 0, 0.9), 0, 30)))

intraop_max_lactate <- round(clip(stats::rnorm(
  n,
  4.40 + 0.00035 * (intraop_ebl_ml - 1200) +
    0.22 * (cold_ischemia_time_hours - 6) + 0.90 * is_dcd,
  1.40), 0.8, 18.0), 1)

# ── Primary binary outcome: early allograft dysfunction ──────────────────────
eta_ead <- -0.95 +
  0.95 * is_dcd - 0.75 * is_living +
  0.13 * (cold_ischemia_time_hours - 6) +
  0.022 * (donor_age - 45) +
  0.20 * (intraop_max_lactate - 5) +
  0.025 * (preop_meld - 22) +
  u_ead[ctr]
ead <- as.logical(stats::runif(n) < logistic(eta_ead))

# ── Post-operative ───────────────────────────────────────────────────────────
p_aki <- logistic(-0.70 + 0.045 * (preop_meld - 22) + 0.85 * ead +
                    1.10 * preop_dialysis + 0.00022 * (intraop_ebl_ml - 1200))
has_aki <- stats::runif(n) < p_aki

# Stage escalates with the same drivers, conditional on having AKI at all.
p_severe <- logistic(-0.70 + 0.60 * ead + 0.90 * preop_dialysis)
stage_raw <- ifelse(stats::runif(n) < p_severe,
                    ifelse(stats::runif(n) < 0.45, 3L, 2L),
                    1L)
postop_aki_stage <- factor(ifelse(has_aki, stage_raw, NA),
                           levels = 1:3, labels = c("1", "2", "3"), ordered = TRUE)
aki_num <- ifelse(is.na(postop_aki_stage), 0L, as.integer(postop_aki_stage))

postop_intubation <- stats::runif(n) < logistic(
  -1.90 + 0.30 * (intraop_max_lactate - 5) + 0.90 * ead + 0.030 * (preop_meld - 22))

postop_mechanical_ventilation_hours <- integer(n)
vent_idx <- which(postop_intubation)
postop_mechanical_ventilation_hours[vent_idx] <- as.integer(round(clip(
  stats::rgamma(length(vent_idx), shape = 1.7, scale = 14) *
    (1 + 0.35 * ead[vent_idx]), 1, 600)))

# ── Primary continuous outcome: length of stay ───────────────────────────────
log_los <- 1.85 +
  0.020 * (preop_meld - 22) +
  0.42 * ead +
  0.00022 * (intraop_ebl_ml - 1200) +
  0.33 * preop_dialysis +
  0.009 * (recipient_age - 54) +
  0.014 * (136 - preop_sodium) +   # weak but real: tests univariable p-thresholds
  0.14 * is_dcd +
  0.18 * aki_num +
  u_los[ctr] +
  stats::rnorm(n, 0, 0.30)
postop_los_days <- as.integer(round(clip(exp(log_los), 3, 120)))

# ── Noise block — zero effect on every outcome above ─────────────────────────
donor_blood_type <- factor(sample(c("A", "B", "AB", "O"), n, TRUE,
                                  prob = c(0.40, 0.12, 0.05, 0.43)),
                           levels = c("A", "B", "AB", "O"))
or_room_number     <- factor(sample(sprintf("OR-%d", 1:6), n, TRUE),
                             levels = sprintf("OR-%d", 1:6))
surgery_start_hour <- as.integer(sample(6:21, n, TRUE))
preop_ferritin     <- round(clip(exp(stats::rnorm(n, 5.4, 0.9)), 8, 4000))
donor_height_cm    <- round(clip(stats::rnorm(n, 172, 10), 145, 200), 1)
referral_source    <- factor(sample(c("internal", "external", "transfer"), n, TRUE,
                                    prob = c(0.50, 0.32, 0.18)),
                             levels = c("internal", "external", "transfer"))

# ── Identifiers ──────────────────────────────────────────────────────────────
patient_mrn <- sample(1000000:9999999, n)
case_date   <- as.Date("2019-06-01") + sample(0:1460, n, TRUE)

liver_tx <- data.frame(
  patient_mrn                         = patient_mrn,
  case_date                           = case_date,
  transplant_center                   = transplant_center,

  recipient_age                       = recipient_age,
  recipient_height_cm                 = recipient_height_cm,
  recipient_weight_kg                 = recipient_weight_kg,
  recipient_bmi                       = recipient_bmi,

  preop_meld                          = preop_meld,
  preop_meld_na                       = preop_meld_na,
  preop_bilirubin                     = preop_bilirubin,
  preop_inr                           = preop_inr,
  preop_creatinine                    = preop_creatinine,
  preop_sodium                        = preop_sodium,
  preop_albumin                       = preop_albumin,
  preop_hb                            = preop_hb,
  preop_dialysis                      = preop_dialysis,
  preop_icu                           = preop_icu,
  preop_intubation                    = preop_intubation,

  liver_donor_type                    = liver_donor_type,
  donor_age                           = donor_age,
  cold_ischemia_time_hours            = cold_ischemia_time_hours,

  ivc_clamp_type                      = ivc_clamp_type,
  intraop_ebl_ml                      = intraop_ebl_ml,
  intraop_rbc_units                   = intraop_rbc_units,
  intraop_max_lactate                 = intraop_max_lactate,

  ead                                 = ead,
  postop_aki_stage                    = postop_aki_stage,
  postop_intubation                   = postop_intubation,
  postop_mechanical_ventilation_hours = postop_mechanical_ventilation_hours,
  postop_los_days                     = postop_los_days,

  donor_blood_type                    = donor_blood_type,
  donor_height_cm                     = donor_height_cm,
  or_room_number                      = or_room_number,
  surgery_start_hour                  = surgery_start_hour,
  preop_ferritin                      = preop_ferritin,
  referral_source                     = referral_source,

  stringsAsFactors = FALSE
)

# ── Missingness (injected last) ──────────────────────────────────────────────
# postop_aki_stage keeps its existing semantics: NA means "no AKI", not missing.
miss <- list(
  preop_ferritin      = 0.35,   # trips PF_MISSING_GT20 when included
  donor_age           = 0.12,
  preop_albumin       = 0.08,
  intraop_max_lactate = 0.05,
  preop_inr           = 0.03
)
for (v in names(miss)) {
  liver_tx[[v]][sample.int(n, floor(n * miss[[v]]))] <- NA
}

save(liver_tx, file = "data/liver_tx.rda", version = 2, compress = "xz")

cat("wrote data/liver_tx.rda -", nrow(liver_tx), "rows x", ncol(liver_tx), "cols\n")
