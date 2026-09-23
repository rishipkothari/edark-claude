#' Statistical Inference — Single Source of Truth
#'
#' Every p-value and confidence interval EDARK reports is computed here, so
#' each quantity is defined once and means the same thing on every screen and
#' in every export. See the "Statistical methods registry" in CLAUDE.md and
#' PRD §4.2. Do not compute p-values or CIs anywhere else — call these.
#'
#' \describe{
#'   \item{Regression coefficients}{\code{edark_coef_table()}: Wald-type 95\%
#'     CI = estimate \eqn{\pm} critical value \eqn{\times} SE, where the
#'     critical value comes from the same distribution as the model's native
#'     p-value — t with residual df (\code{lm}), t with Satterthwaite df
#'     (\code{lmerTest::lmer}), standard normal (\code{glm},
#'     \code{lme4::glmer}). So a CI excludes the null exactly when p < 0.05.
#'     Odds ratios are the exponentiated estimate and limits.}
#'   \item{Group comparisons}{\code{edark_group_test()}: numeric by group —
#'     Kruskal-Wallis (any number of groups); categorical by group — Pearson
#'     chi-square without continuity correction, or Fisher's exact test when
#'     any expected count is < 5.}
#'   \item{Correlation}{\code{edark_cor_test()}: Pearson r; t-test p-value
#'     (n - 2 df); 95\% CI by Fisher's z.}
#'   \item{Display}{\code{edark_format_p()}: "< 0.001", else 3 decimals.}
#' }
#'
#' @name stats_inference
NULL


.EDARK_CI_LEVEL <- 0.95

# How each model type's CIs and p-values are computed, in words. The one
# source for every footnote, summary line and methods sentence.
.EDARK_INFERENCE <- list(
  linear = list(
    ci = "Wald-type 95% confidence intervals using the t distribution with residual degrees of freedom",
    p  = "t-tests"),
  logistic = list(
    ci = "Wald 95% confidence intervals (normal distribution), exponentiated to odds ratios",
    p  = "Wald z-tests"),
  linear_mixed = list(
    ci = "Wald-type 95% confidence intervals using the t distribution with Satterthwaite degrees of freedom",
    p  = "t-tests with Satterthwaite degrees of freedom (lmerTest)"),
  logistic_mixed = list(
    ci = "Wald 95% confidence intervals (normal distribution), exponentiated to odds ratios",
    p  = "Wald z-tests",
    caution = "Interpret with caution in small samples or with rare outcomes.")
)


#' Plain-language description of a model's CIs and p-values
#'
#' @param model_type One of \code{"linear"}, \code{"logistic"},
#'   \code{"linear_mixed"}, \code{"logistic_mixed"}.
#' @return A single sentence (or two), e.g. for table footnotes; \code{""}
#'   for an unknown type.
#' @export
edark_inference_note <- function(model_type) {
  inf <- .EDARK_INFERENCE[[model_type %||% ""]]
  if (is.null(inf)) return("")
  paste0(inf$ci, ". P-values from ", inf$p, ".",
         if (!is.null(inf$caution)) paste0(" ", inf$caution) else "")
}


#' Format p-values for display
#'
#' @param p Numeric vector of p-values.
#' @return Character vector: \code{"< 0.001"} below 0.001, otherwise three
#'   decimals; \code{NA} input gives \code{"—"}.
#' @export
edark_format_p <- function(p) {
  p <- suppressWarnings(as.numeric(p))
  out <- ifelse(p < 0.001, "< 0.001", sprintf("%.3f", p))
  out[is.na(p)] <- "-"
  out
}


#' Format estimates and confidence intervals for display
#'
#' One rule for every estimate in the app: 1 decimal from 100, 2 decimals
#' from 0.1, otherwise 3 significant digits (so per-unit effects such as
#' 0.00031 stay readable).
#'
#' @param x Numeric vector.
#' @return Character vector; \code{NA} gives \code{"—"}.
#' @export
edark_format_est <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  out <- ifelse(abs(x) >= 100, sprintf("%.1f", x),
         ifelse(abs(x) >= 0.1, sprintf("%.2f", x),
                formatC(signif(x, 3), format = "fg", digits = 3)))
  out[!is.na(x) & x == 0] <- "0.00"
  out[is.na(x)] <- "-"
  out
}

#' @rdname edark_format_est
#' @param est,low,high Numeric vectors: estimate and CI limits.
#' @return \code{edark_format_ci()}: \code{"est (low–high)"}, or
#'   \code{"est (low to high)"} when a limit is negative.
#' @export
edark_format_ci <- function(est, low, high) {
  sep <- ifelse(!is.na(low) & !is.na(high) & (low < 0 | high < 0), " to ", "\u2013")
  out <- sprintf("%s (%s%s%s)", edark_format_est(est), edark_format_est(low), sep,
                 edark_format_est(high))
  out[is.na(est)] <- "-"
  out
}


# Levels of a categorical predictor as a model sees them: factor levels,
# sorted unique values for character, FALSE/TRUE for logical. NULL when the
# variable is numeric.
.edark_var_levels <- function(x) {
  if (is.factor(x)) return(levels(x))
  if (is.character(x)) return(sort(unique(x[!is.na(x)])))
  if (is.logical(x)) return(c("FALSE", "TRUE"))
  NULL
}


# The reference distribution of a model's coefficient tests: list(dist, df),
# where df is per coefficient (Satterthwaite) or a single residual df.
.edark_test_distribution <- function(model, sm) {
  if (inherits(model, "lmerModLmerTest")) {
    return(list(dist = "t", df = unname(sm[, "df"]), label = "t (Satterthwaite df)"))
  }
  if (inherits(model, "merMod") || inherits(model, "glm")) {
    return(list(dist = "z", df = Inf, label = "z"))
  }
  if (inherits(model, "lm")) {
    return(list(dist = "t", df = stats::df.residual(model), label = "t (residual df)"))
  }
  stop("edark_coef_table: unsupported model class ", class(model)[1L])
}


#' Coefficient table with Wald-type confidence intervals
#'
#' The one place regression estimates, CIs and p-values are extracted
#' (Step 3 univariable screen, Step 5 model, Model › Results). Works for
#' \code{lm}, binomial \code{glm}, \code{lmerTest::lmer} and
#' \code{lme4::glmer} fits. Estimates, SEs, test statistics and p-values come
#' from \code{summary(model)$coefficients} (fixed effects only); terms are
#' mapped to variables through the model matrix \code{assign} attribute.
#'
#' @param model A fitted model.
#' @param data The data the model was fitted on (to recognise factor terms).
#'
#' @return A data.frame: variable, term, level, estimate, std.error,
#'   statistic, df, p.value, conf.low, conf.high, effect, effect.low,
#'   effect.high, effect_measure (\code{"odds_ratio"} for logistic models,
#'   else \code{"coefficient"}); \code{effect*} are on the reporting scale.
#' @export
edark_coef_table <- function(model, data) {
  sm <- summary(model)$coefficients
  stat_col <- grep("value$", colnames(sm))[1L]
  p_col    <- grep("^Pr", colnames(sm))[1L]
  is_mixed <- inherits(model, "merMod")
  is_logit <- (inherits(model, "glm") || inherits(model, "glmerMod")) &&
    identical(stats::family(model)$family, "binomial")

  if (is_mixed) {
    X      <- lme4::getME(model, "X")
    labels <- attr(stats::terms(model, fixed.only = TRUE), "term.labels")
  } else {
    X      <- stats::model.matrix(model)
    labels <- attr(stats::terms(model), "term.labels")
  }
  col_var <- c("(Intercept)", labels)[attr(X, "assign") + 1L]
  names(col_var) <- colnames(X)

  terms <- rownames(sm)
  var   <- unname(col_var[terms])
  level <- vapply(seq_along(terms), function(i) {
    v <- var[i]
    if (is.na(v) || !v %in% names(data) || is.null(.edark_var_levels(data[[v]]))) return(NA_character_)
    sub(paste0("^", .regex_escape(v)), "", terms[i])
  }, character(1))

  tdist <- .edark_test_distribution(model, sm)
  q     <- (1 + .EDARK_CI_LEVEL) / 2
  crit  <- if (tdist$dist == "t") stats::qt(q, df = tdist$df) else stats::qnorm(q)
  est   <- unname(sm[, 1L])
  se    <- unname(sm[, 2L])
  lo    <- est - crit * se
  hi    <- est + crit * se

  data.frame(
    variable       = var,
    term           = terms,
    level          = level,
    estimate       = est,
    std.error      = se,
    statistic      = if (!is.na(stat_col)) unname(sm[, stat_col]) else NA_real_,
    df             = if (tdist$dist == "t") rep_len(tdist$df, length(est)) else NA_real_,
    p.value        = if (!is.na(p_col)) unname(sm[, p_col]) else NA_real_,
    conf.low       = lo,
    conf.high      = hi,
    effect         = if (is_logit) exp(est) else est,
    effect.low     = if (is_logit) exp(lo) else lo,
    effect.high    = if (is_logit) exp(hi) else hi,
    effect_measure = if (is_logit) "odds_ratio" else "coefficient",
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

.regex_escape <- function(x) gsub("([.|()\\^{}+$*?\\[\\]\\\\])", "\\\\\\1", x)


#' Compare a variable across groups
#'
#' @param x The variable (numeric, factor, character or logical).
#' @param g The grouping variable.
#' @return \code{list(p.value, method)}; \code{p.value} is \code{NA} when
#'   fewer than two groups have data.
#' @export
edark_group_test <- function(x, g) {
  ok <- !is.na(x) & !is.na(g)
  x <- x[ok]
  g <- droplevels(factor(g[ok]))
  na <- list(p.value = NA_real_, method = NA_character_)
  if (nlevels(g) < 2L) return(na)

  if (is.numeric(x)) {
    kt <- stats::kruskal.test(x, g)
    return(list(p.value = unname(kt$p.value), method = "Kruskal-Wallis test"))
  }
  .edark_categorical_test(table(droplevels(factor(x)), g))
}

# Chi-square without continuity correction; Fisher's exact when any expected
# count is < 5. Fisher falls back to a Monte Carlo p-value (fixed seed, so it
# is reproducible) only if the exact network algorithm runs out of workspace.
.edark_categorical_test <- function(tb) {
  if (nrow(tb) < 2L || ncol(tb) < 2L) return(list(p.value = NA_real_, method = NA_character_))
  expected <- outer(rowSums(tb), colSums(tb)) / sum(tb)
  if (all(expected >= 5)) {
    ct <- suppressWarnings(stats::chisq.test(tb, correct = FALSE))
    return(list(p.value = unname(ct$p.value), method = "Pearson's chi-squared test"))
  }
  p <- tryCatch(stats::fisher.test(tb, workspace = 2e7)$p.value, error = function(e) NULL)
  if (!is.null(p)) return(list(p.value = p, method = "Fisher's exact test"))
  .with_seed(20260918L, {
    p <- stats::fisher.test(tb, simulate.p.value = TRUE, B = 10000)$p.value
  })
  list(p.value = p, method = "Fisher's exact test (Monte Carlo, 10,000 replicates)")
}

.with_seed <- function(seed, expr) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had) old <- get(".Random.seed", envir = globalenv())
  on.exit(if (had) assign(".Random.seed", old, envir = globalenv())
          else rm(".Random.seed", envir = globalenv()))
  set.seed(seed)
  force(expr)
}

# gtsummary custom test for categorical variables (Table 1), so Table 1 uses
# exactly the same rule as every other group comparison.
.gts_categorical_test <- function(data, variable, by, ...) {
  r <- .edark_categorical_test(table(droplevels(factor(data[[variable]])),
                                     droplevels(factor(data[[by]]))))
  data.frame(p.value = r$p.value, method = r$method)
}


#' Pearson correlation with CI
#'
#' @param x,y Numeric vectors (incomplete pairs are dropped).
#' @return \code{list(r, p.value, conf.low, conf.high, n)}; \code{NA} values
#'   when fewer than 4 complete pairs (Fisher's z CI needs n > 3).
#' @export
edark_cor_test <- function(x, y) {
  ok <- !is.na(x) & !is.na(y)
  n  <- sum(ok)
  if (n < 4L) return(list(r = NA_real_, p.value = NA_real_, conf.low = NA_real_,
                          conf.high = NA_real_, n = n))
  ct <- stats::cor.test(x[ok], y[ok], method = "pearson", conf.level = .EDARK_CI_LEVEL)
  list(r = unname(ct$estimate), p.value = ct$p.value,
       conf.low = ct$conf.int[1L], conf.high = ct$conf.int[2L], n = n)
}
