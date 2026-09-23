#' Analysis Preflight Validation Service
#'
#' Provides \code{validate_analysis()}, a pure function that checks an
#' \code{analysis_spec} + dataset pair for validity before running any
#' analysis operation. Implements all Tier 1 and Tier 2 checks from PRD §8.2.
#'
#' @name service_analysis_validation
NULL


# Plain-language description of each check when it passes — used by the
# Step 5 Summary, which lists every check that ran. Codes that share one
# outcome (e.g. PF_LOW_EPV_5 is a stricter PF_LOW_EPV_10) are folded onto a
# single head code via .PF_GROUP_HEAD.
.PF_PASS_LABELS <- c(
  PF_NO_OUTCOME                     = "Outcome variable assigned",
  PF_ZERO_COMPLETE                  = "Complete cases remain",
  PF_OUTCOME_NO_VARIANCE_BINARY     = "Outcome has events and non-events",
  PF_OUTCOME_NO_VARIANCE_CONTINUOUS = "Outcome has more than one value",
  PF_OUTCOME_UNSUPPORTED            = "Outcome is numeric or a two-level factor",
  PF_FACTOR_SINGLE_LEVEL            = "Every factor keeps two or more levels in the complete rows",
  PF_NO_PREDICTORS                  = "At least one predictor in the model",
  PF_PREDICTOR_TYPE                 = "Every predictor is numeric or a factor",
  PF_OUTCOME_MODEL_MISMATCH         = "Outcome type matches the model",
  PF_CLUSTERS_UNUSED                = "No cluster variables left unused",
  PF_MIXED_NO_CLUSTER               = "Mixed model has a cluster variable",
  PF_MIXED_SINGLE_CLUSTER           = "Every cluster variable has more than one cluster",
  PF_FEW_CLUSTERS                   = "At least 10 clusters per cluster variable",
  PF_UNBALANCED_CLUSTERS            = "Cluster sizes reasonably balanced",
  PF_CLUSTER_IDS_SHARED             = "Cluster IDs are not shared across groupings",
  PF_MISSING_ANY                    = "No rows excluded for missing data",
  PF_LOW_EPV_10                     = "At least 10 events per parameter",
  PF_RARE_OUTCOME                   = "Outcome prevalence between 5% and 95%",
  PF_RARE_FACTOR_LEVEL              = "Every factor level has at least 5 observations",
  PF_EXPOSURE_NOT_IN_MODEL          = "Exposure is in the model",
  PF_HIGH_CORRELATION               = "No numeric predictor pair correlated above 0.7",
  PF_LOOKS_CATEGORICAL              = "No numeric variable looks categorical",
  PF_SPLIT_INVALID                  = "Train/test variable and training level are valid",
  PF_SPLIT_NO_TEST                  = "The test set has rows",
  PF_SPLIT_MISSING                  = "Every row is in the training or the test set",
  PF_SMALL_TEST_SET                 = "The test set is large enough for precise performance estimates"
)

.PF_GROUP_HEAD <- c(
  PF_LOW_EPV_5    = "PF_LOW_EPV_10",
  PF_MISSING_GT20 = "PF_MISSING_ANY",
  PF_MISSING_GT50 = "PF_MISSING_ANY"
)

# Numeric variables with at most this many distinct whole-number values are
# flagged as possibly categorical (PF_LOOKS_CATEGORICAL).
.PF_CATEGORICAL_MAX_VALUES <- 10L


#' Validate an analysis specification against its dataset
#'
#' Runs all applicable preflight checks and returns a structured result. This
#' function is pure (no side effects, no Shiny dependencies) and may be called
#' from any context.
#'
#' @param spec A named list conforming to the \code{analysis_spec} structure
#'   (see PRD §3.5). May be \code{NULL} — treated as missing outcome.
#' @param data A \code{data.frame} (the frozen analysis dataset). May be
#'   \code{NULL}.
#' @param tier Character. \code{"tier1"} runs only core data validity checks;
#'   \code{"full"} (default) adds model specification checks.
#' @param verbose Logical. When \code{TRUE}, note-level messages (sample
#'   summary, reference levels, etc.) are included in \code{display_messages}.
#'
#' @return A named list:
#'   \describe{
#'     \item{validity_flag}{Character: \code{"valid"}, \code{"warnings"}, or
#'       \code{"invalid"}.}
#'     \item{messages}{All messages (errors + warnings + notes).}
#'     \item{display_messages}{Filtered messages suitable for UI display:
#'       errors and warnings always; notes only when \code{verbose = TRUE}.}
#'     \item{checks_run}{Character. Codes of the checks that were evaluated.}
#'     \item{passed}{Messages (level \code{"pass"}) for checks that ran and
#'       raised nothing.}
#'   }
#'   Each message is a list with fields \code{code}, \code{level}, and
#'   \code{message}.
#' @export
validate_analysis <- function(spec, data, tier = "full", verbose = FALSE) {

  msgs <- list()
  ran  <- character(0)

  .add <- function(code, level, txt) {
    msgs[[length(msgs) + 1L]] <<- list(code = code, level = level, message = txt)
  }
  .ran  <- function(...) ran <<- c(ran, ...)
  .done <- function() .finalize(msgs, verbose, ran)

  .ran("PF_NO_OUTCOME")
  roles      <- if (!is.null(spec$variable_roles)) spec$variable_roles else list()
  outcome    <- roles$outcome_variable
  exposure   <- roles$exposure_variable
  clusters   <- roles$cluster_variables
  covariates <- roles$final_model_covariates
  model_type <- spec$model_design$model_type
  is_mixed   <- !is.null(model_type) && model_type %in% c("linear_mixed", "logistic_mixed")

  # ── Tier 1: Core Data Validity ──────────────────────────────────────────────

  if (is.null(spec) || is.null(outcome) || !nzchar(outcome)) {
    .add("PF_NO_OUTCOME", "error", "No outcome variable assigned.")
    return(.done())
  }

  if (is.null(data) || !outcome %in% names(data)) {
    return(.done())
  }

  # Train/test split (prediction purpose only). Every later check runs on the
  # training rows — the rows the model is built from.
  split <- analysis_split(spec)
  if (!is.null(split)) {
    .ran("PF_SPLIT_INVALID", "PF_SPLIT_NO_TEST", "PF_SPLIT_MISSING")
    sv    <- split$variable
    roled <- c(outcome, exposure, covariates, clusters, roles$candidate_covariates)
    bad <- if (!sv %in% names(data)) {
      paste0("Train/test variable '", sv, "' is not in the analysis dataset.")
    } else if (!is.factor(data[[sv]])) {
      paste0("Train/test variable '", sv, "' must be a factor.")
    } else if (sv %in% roled) {
      paste0("'", sv, "' is the train/test variable and also has a role in Step 1. ",
             "Remove the role or choose another train/test variable.")
    } else if (!split$training_level %in% as.character(data[[sv]])) {
      paste0("No rows have the training level '", split$training_level, "' of '", sv, "'.")
    }
    if (!is.null(bad)) {
      .add("PF_SPLIT_INVALID", "error", bad)
      return(.done())
    }
    sr <- analysis_split_rows(spec, data)
    if (sum(sr$test) == 0L) {
      .add("PF_SPLIT_NO_TEST", "warning",
           paste0("Every row of '", sv, "' is the training level, so there is no test set. ",
                  "Only apparent (in-sample) performance can be measured."))
    }
    if (sr$n_missing > 0L) {
      .add("PF_SPLIT_MISSING", "warning",
           paste0(sr$n_missing, " row", if (sr$n_missing != 1L) "s have" else " has",
                  " no value for '", sv, "' and belong to neither the training nor the test set."))
    }
    test_data <- data[sr$test, , drop = FALSE]
    data      <- data[sr$training, , drop = FALSE]
  }

  # Complete cases over outcome + exposure for Tier 1
  .ran("PF_ZERO_COMPLETE")
  t1_vars <- .safe_vars(c(outcome, exposure), data)
  cc1     <- stats::complete.cases(data[, t1_vars, drop = FALSE])
  data_t1 <- data[cc1, , drop = FALSE]
  n_t1    <- nrow(data_t1)

  if (n_t1 == 0L) {
    .add("PF_ZERO_COMPLETE", "error", "No complete cases remain.")
    return(.done())
  }

  out_t1            <- data_t1[[outcome]]
  out_is_binary     <- is.factor(out_t1) && length(levels(droplevels(out_t1))) == 2L
  out_is_continuous <- is.numeric(out_t1)

  if (out_is_binary) {
    .ran("PF_OUTCOME_NO_VARIANCE_BINARY")
    if (length(unique(as.integer(out_t1))) < 2L) {
      .add("PF_OUTCOME_NO_VARIANCE_BINARY", "error", "Outcome has no events.")
    }
  }

  if (out_is_continuous) {
    .ran("PF_OUTCOME_NO_VARIANCE_CONTINUOUS")
    if (length(unique(out_t1)) < 2L) {
      .add("PF_OUTCOME_NO_VARIANCE_CONTINUOUS", "error",
           "Outcome has only one unique value.")
    }
  }

  # PF_FACTOR_SINGLE_LEVEL (Tier 1) — exposure only. Covariates are checked in
  # Tier 2 against the full-model complete cases; at Step 3 a single-level
  # candidate is excluded by the selection service rather than blocking the step.
  if (length(.safe_vars(exposure, data)) > 0L) .ran("PF_FACTOR_SINGLE_LEVEL")
  .check_single_level(exposure, data_t1, .add)

  if (tier == "tier1") return(.done())

  # ── Tier 2: Model Specification ─────────────────────────────────────────────

  .ran("PF_OUTCOME_UNSUPPORTED")
  if (!out_is_binary && !out_is_continuous) {
    n_lv <- if (is.factor(out_t1)) nlevels(droplevels(out_t1)) else NA_integer_
    .add("PF_OUTCOME_UNSUPPORTED", "error",
         paste0("Outcome '", outcome, "' is ",
                if (!is.na(n_lv)) paste0("a factor with ", n_lv, " levels") else
                  paste0("of type ", class(out_t1)[1L]),
                ". Models need a numeric outcome (linear) or a two-level factor (logistic)."))
  }

  predictors <- .safe_preds(exposure, covariates)

  .ran("PF_NO_PREDICTORS")
  if (length(predictors) == 0L) {
    .add("PF_NO_PREDICTORS", "error", "No predictor variables assigned.")
  }

  # PF_PREDICTOR_TYPE — a timestamp would enter as seconds since 1970, free
  # text as one dummy per string. Step 1 blocks both; this catches specs
  # built programmatically.
  .ran("PF_PREDICTOR_TYPE")
  for (v in .safe_vars(predictors, data)) {
    x <- data[[v]]
    if (is.numeric(x) || is.factor(x)) next
    kind <- if (inherits(x, c("POSIXt", "Date"))) "a date/time" else "a free-text"
    .add("PF_PREDICTOR_TYPE", "error",
         paste0("'", v, "' is ", kind, " column and cannot be a model term. ",
                "Derive a numeric or factor variable from it instead (e.g. a year, ",
                "era or duration)."))
  }

  # Full complete-case subset over all model variables (clusters only enter
  # a mixed model, so a plain lm/glm is not charged for their missingness)
  n_total <- nrow(data)
  t2_vars <- .safe_vars(c(outcome, predictors, if (is_mixed) clusters), data)
  cc2     <- stats::complete.cases(data[, t2_vars, drop = FALSE])
  data_t2 <- data[cc2, , drop = FALSE]
  n_t2    <- nrow(data_t2)
  n_miss  <- n_total - n_t2

  # Missing data warnings
  .ran("PF_MISSING_ANY")
  if (n_miss > 0L) {
    pct <- n_miss / n_total
    .add("PF_MISSING_ANY", "warning",
         paste0(n_miss, " row", if (n_miss != 1L) "s" else "", " (",
                round(pct * 100, 1L), "%) contain missing values. Complete-case ",
                "analysis will exclude ", if (n_miss != 1L) "these" else "this",
                ". Report in methods."))
    if (pct > 0.5) {
      .add("PF_MISSING_GT50", "warning",
           "Complete-case analysis excludes more than 50% of data. Results may not be representative.")
    } else if (pct > 0.2) {
      .add("PF_MISSING_GT20", "warning",
           "Complete-case analysis excludes more than 20% of data. Review missingness.")
    }
  }

  if (n_t2 == 0L) return(.done())

  # PF_FACTOR_SINGLE_LEVEL (Tier 2) — covariates after listwise deletion over
  # every model variable; a factor can collapse to one level here even when it
  # has several in the full data.
  if (length(setdiff(covariates, exposure)) > 0L) .ran("PF_FACTOR_SINGLE_LEVEL")
  .check_single_level(setdiff(covariates, exposure), data_t2, .add)

  out_t2        <- data_t2[[outcome]]
  out_binary_t2 <- is.factor(out_t2) && length(levels(droplevels(out_t2))) == 2L
  out_cont_t2   <- is.numeric(out_t2)

  # PF_OUTCOME_MODEL_MISMATCH
  if (!is.null(model_type)) {
    .ran("PF_OUTCOME_MODEL_MISMATCH")
    if (model_type %in% c("logistic", "logistic_mixed") && !out_binary_t2) {
      .add("PF_OUTCOME_MODEL_MISMATCH", "error",
           "Selected model requires a binary outcome but the outcome variable is not binary.")
    }
    if (model_type %in% c("linear", "linear_mixed") && !out_cont_t2) {
      .add("PF_OUTCOME_MODEL_MISMATCH", "error",
           "Selected model requires a continuous outcome but the outcome variable is not continuous.")
    }
  }

  # Cluster / model agreement: clusters assigned demand a mixed model, and a
  # mixed model demands clusters
  clusters_present <- .safe_vars(clusters, data_t2)
  if (!is.null(model_type) && !is_mixed) {
    .ran("PF_CLUSTERS_UNUSED")
    if (length(clusters_present) > 0L) {
      .add("PF_CLUSTERS_UNUSED", "error",
           paste0("Cluster variable", if (length(clusters_present) > 1L) "s" else "", " (",
                  paste(clusters_present, collapse = ", "),
                  ") assigned but a non-mixed model is selected. Select a mixed model, ",
                  "or remove the cluster role in Step 1."))
    }
  }

  if (is_mixed) {
    .ran("PF_MIXED_NO_CLUSTER")
    if (length(clusters_present) == 0L) {
      .add("PF_MIXED_NO_CLUSTER", "error",
           "Mixed model requires at least one cluster variable. Assign one in Step 1.")
    } else {
      .ran("PF_MIXED_SINGLE_CLUSTER", "PF_FEW_CLUSTERS", "PF_UNBALANCED_CLUSTERS")
    }

    for (cl in clusters_present) {
      cluster_sizes <- table(data_t2[[cl]])
      n_clusters    <- length(cluster_sizes)

      if (n_clusters <= 1L) {
        .add("PF_MIXED_SINGLE_CLUSTER", "error",
             paste0("Cluster variable '", cl, "' has only one value in the complete cases. ",
                    "A random intercept needs more than one cluster."))
        next
      }
      if (n_clusters < 10L) {
        .add("PF_FEW_CLUSTERS", "warning",
             paste0("Only ", n_clusters, " clusters in '", cl,
                    "'. Mixed model estimates may be unstable with fewer than 10."))
      }
      cv <- stats::sd(as.numeric(cluster_sizes)) / mean(as.numeric(cluster_sizes))
      if (!is.na(cv) && cv > 1) {
        .add("PF_UNBALANCED_CLUSTERS", "warning",
             paste0("Cluster sizes in '", cl, "' are highly unbalanced (",
                    min(cluster_sizes), "\u2013", max(cluster_sizes),
                    " rows). Interpret mixed model estimates cautiously."))
      }
    }

    # PF_CLUSTER_IDS_SHARED — with two or more cluster variables, values of the
    # finer one that recur under several values of the coarser one. Either the
    # design is crossed (fine), or IDs are only unique within the coarser group
    # (e.g. patient "12" at two centres) and would be merged into one cluster.
    if (length(clusters_present) >= 2L) {
      .ran("PF_CLUSTER_IDS_SHARED")
      pairs <- list()
      for (i in seq_along(clusters_present)[-1L]) {
        for (j in seq_len(i - 1L)) pairs <- c(pairs, list(clusters_present[c(j, i)]))
      }
      for (p in pairs) {
        n_uniq <- vapply(p, function(v) length(unique(data_t2[[v]])), integer(1))
        fine   <- p[which.max(n_uniq)]
        coarse <- setdiff(p, fine)
        spans  <- tapply(data_t2[[coarse]], data_t2[[fine]],
                         function(x) length(unique(x)))
        n_shared <- sum(spans > 1L, na.rm = TRUE)
        if (n_shared > 0L) {
          .add("PF_CLUSTER_IDS_SHARED", "warning",
               paste0(n_shared, " value", if (n_shared != 1L) "s" else "", " of '", fine,
                      "' appear under more than one '", coarse, "'. If '", fine,
                      "' IDs are only unique within a '", coarse,
                      "', those clusters will be merged - make the IDs unique first. ",
                      "If the two groupings are crossed, ignore this."))
        }
      }
    }
  }

  # Logistic-specific EPV and outcome prevalence checks
  if (!is.null(model_type) &&
      model_type %in% c("logistic", "logistic_mixed") &&
      out_binary_t2 &&
      length(predictors) > 0L) {

    .ran("PF_LOW_EPV_10", "PF_RARE_OUTCOME")
    ev_counts  <- table(droplevels(out_t2))
    n_events   <- min(ev_counts)
    event_rate <- n_events / n_t2
    # Parameters, not variables: 1 per numeric/logical term, (levels - 1) per
    # factor term on the complete-case rows — matches compute_covariate_sample()
    # so Step 4/Summary and this preflight check report the same EPV.
    n_params   <- sum(vapply(predictors, function(v) {
      col <- data_t2[[v]]
      if (is.factor(col)) max(length(levels(droplevels(col))) - 1L, 0L) else 1L
    }, integer(1)))

    if (n_params > 0L) {
      epv <- n_events / n_params

      if (epv < 5) {
        .add("PF_LOW_EPV_5", "warning",
             paste0("Fewer than 5 events per parameter (EPV = ", round(epv, 1L),
                    "). High risk of overfitting. Reduce covariates."))
      } else if (epv < 10) {
        .add("PF_LOW_EPV_10", "warning",
             paste0("Fewer than 10 outcome events per parameter (EPV = ",
                    round(epv, 1L), "). Consider reducing covariates."))
      }
    }

    if (event_rate < 0.05 || event_rate > 0.95) {
      .add("PF_RARE_OUTCOME", "warning",
           paste0("Outcome prevalence is ", round(event_rate * 100, 1L),
                  "%. Wald inference is fragile with rare events."))
    }
  }

  # PF_RARE_FACTOR_LEVEL
  fac_preds <- intersect(predictors, names(data_t2))
  fac_preds <- fac_preds[vapply(fac_preds, function(v) is.factor(data_t2[[v]]), logical(1))]
  if (length(fac_preds) > 0L) .ran("PF_RARE_FACTOR_LEVEL")
  for (v in fac_preds) {
    lev_counts <- table(droplevels(data_t2[[v]]))
    if (any(lev_counts < 5L)) {
      .add("PF_RARE_FACTOR_LEVEL", "warning",
           paste0("Variable '", v, "' has a level with fewer than 5 observations."))
    }
  }

  # PF_EXPOSURE_NOT_IN_MODEL
  if (!is.null(exposure) && nzchar(exposure) && length(predictors) > 0L) {
    .ran("PF_EXPOSURE_NOT_IN_MODEL")
    if (!exposure %in% predictors) {
      .add("PF_EXPOSURE_NOT_IN_MODEL", "warning",
           paste0("Assigned exposure variable '", exposure,
                  "' is not included as a model predictor."))
    }
  }

  # PF_HIGH_CORRELATION — numeric predictors only; skip on error
  num_preds <- intersect(predictors, names(data_t2))
  num_preds <- num_preds[vapply(num_preds,
                                function(v) is.numeric(data_t2[[v]]),
                                logical(1))]
  if (length(num_preds) >= 2L) {
    .ran("PF_HIGH_CORRELATION")
    cor_mat <- tryCatch(
      stats::cor(data_t2[, num_preds, drop = FALSE],
                 use = "pairwise.complete.obs"),
      error = function(e) NULL
    )
    if (!is.null(cor_mat)) {
      ut <- cor_mat[upper.tri(cor_mat)]
      if (any(abs(ut) > 0.7, na.rm = TRUE)) {
        .add("PF_HIGH_CORRELATION", "warning",
             "High correlation (> 0.7) detected between some candidate variables. Review collinearity.")
      }
    }
  }

  # PF_LOOKS_CATEGORICAL — numeric outcome/predictors holding only a handful of
  # whole numbers (0/1 flags, ASA class, ...). They are modelled as continuous
  # (one slope per unit); converting to a factor is the user's call.
  .ran("PF_LOOKS_CATEGORICAL")
  for (v in intersect(c(outcome, predictors), names(data_t2))) {
    x <- data_t2[[v]]
    if (!is.numeric(x)) next
    vals <- sort(unique(x[is.finite(x)]))
    if (length(vals) == 0L || length(vals) > .PF_CATEGORICAL_MAX_VALUES) next
    if (any(abs(vals - round(vals)) > 1e-8)) next
    shown <- if (length(vals) <= 4L) paste(vals, collapse = ", ") else
      paste0(min(vals), "\u2013", max(vals))
    txt <- if (identical(v, outcome) && length(vals) == 2L) {
      paste0("Outcome '", v, "' is numeric with only the values ", shown,
             ". Linear regression will be fitted to it. If it is a yes/no outcome, ",
             "convert it to a factor (Prepare \u203a Transforms \u203a Auto-factor) for logistic regression.")
    } else {
      paste0("'", v, "' is numeric with only ", length(vals), " distinct values (", shown,
             "). It will be modelled as continuous (one slope per unit). If it is ",
             "categorical, convert it to a factor in Prepare \u203a Transforms.")
    }
    .add("PF_LOOKS_CATEGORICAL", "warning", txt)
  }

  # PF_SMALL_TEST_SET — a test set needs roughly 100 events and 100
  # non-events (binary) or 100 rows (continuous) for its performance
  # estimates to be usefully precise (Riley et al., 2021).
  n_test_cc <- NA_integer_
  if (!is.null(split) && nrow(test_data) > 0L) {
    .ran("PF_SMALL_TEST_SET")
    test_cc   <- test_data[stats::complete.cases(test_data[, t2_vars, drop = FALSE]), , drop = FALSE]
    n_test_cc <- nrow(test_cc)
    y_test    <- test_cc[[outcome]]
    small <- if (out_binary_t2 && is.factor(y_test)) {
      min(table(factor(as.character(y_test), levels = levels(droplevels(out_t2))))) < 100L
    } else {
      n_test_cc < 100L
    }
    if (small) {
      .add("PF_SMALL_TEST_SET", "warning",
           paste0("The test set has ", n_test_cc, " complete row", if (n_test_cc != 1L) "s",
                  if (out_binary_t2) " and fewer than 100 events or non-events" else "",
                  ". Its performance estimates will be imprecise."))
    }
  }

  # Notes — only shown in verbose mode
  if (verbose) {
    if (!is.null(split)) {
      .add("PF_SPLIT_SUMMARY", "note",
           paste0("Train/test split on '", split$variable, "': the model is built on the ",
                  n_total, " training rows ('", split$training_level, "')",
                  if (!is.na(n_test_cc)) paste0("; ", n_test_cc, " complete test rows are held out") else "",
                  "."))
    }
    .add("PF_SAMPLE_SUMMARY", "note",
         paste0("N = ", n_t2, " of ", n_total, if (!is.null(split)) " training" else "",
                " rows included (", n_miss, " excluded for missing data)."))

    if (!is.null(model_type)) {
      label <- .ANALYSIS_MODEL_LABELS[[model_type]]
      n_cov <- length(setdiff(predictors, exposure))
      .add("PF_MODEL_SUMMARY", "note",
           paste0(if (is.null(label)) model_type else label, " with ",
                  length(predictors), " predictor", if (length(predictors) != 1L) "s" else "",
                  if (!is.null(exposure) && exposure %in% predictors && n_cov > 0L)
                    paste0(" (", exposure, " + ", n_cov, " covariate",
                           if (n_cov != 1L) "s" else "", ")"),
                  "."))
    }

    if (!is.null(exposure) && exposure %in% predictors && length(predictors) == 1L) {
      .add("PF_SINGLE_COVARIATE", "note",
           "No covariates selected - the model is unadjusted (exposure only).")
    } else if (length(predictors) == 1L) {
      .add("PF_SINGLE_COVARIATE", "note", "Model has a single predictor.")
    }

    ref_levels <- roles$reference_levels
    ref_levels <- ref_levels[intersect(names(ref_levels), c(outcome, predictors))]
    if (length(ref_levels) > 0L) {
      ref_str <- paste(names(ref_levels), "=",
                       vapply(ref_levels, as.character, character(1)),
                       collapse = "; ")
      .add("PF_REFERENCE_LEVELS", "note", paste0("Reference levels: ", ref_str))
    }

    structure_txt <- if (is_mixed && length(clusters_present) > 0L) {
      paste(vapply(clusters_present, function(cl) {
        sizes <- table(data_t2[[cl]])
        sprintf("%s: %d clusters, median %s rows each", cl, length(sizes),
                format(stats::median(as.numeric(sizes))))
      }, character(1)), collapse = "; ")
    } else {
      "One row per observation, no clustering."
    }
    .add("PF_DATA_STRUCTURE", "note", paste0("Data structure: ", structure_txt))
  }

  .done()
}


# ── Internal helpers ─────────────────────────────────────────────────────────

# Assemble validity_flag, display_messages and pass messages.
.finalize <- function(msgs, verbose, ran = character(0)) {
  levels_present <- vapply(msgs, `[[`, character(1), "level")
  validity_flag <- if ("error" %in% levels_present) {
    "invalid"
  } else if ("warning" %in% levels_present) {
    "warnings"
  } else {
    "valid"
  }
  display_msgs <- Filter(
    function(m) m$level != "note" || isTRUE(verbose),
    msgs
  )

  # A check passes when it ran and neither it nor a code folded onto it fired
  raised <- vapply(msgs, `[[`, character(1), "code")
  raised <- ifelse(raised %in% names(.PF_GROUP_HEAD), .PF_GROUP_HEAD[raised], raised)
  ran    <- unique(ran)
  passed <- lapply(intersect(setdiff(ran, raised), names(.PF_PASS_LABELS)), function(code) {
    list(code = code, level = "pass", message = .PF_PASS_LABELS[[code]])
  })

  list(validity_flag    = validity_flag,
       messages         = msgs,
       display_messages = display_msgs,
       checks_run       = ran,
       passed           = passed)
}

# Return the subset of `vars` that are non-NULL, non-empty, and present in `data`.
.safe_vars <- function(vars, data) {
  vars <- vars[!vapply(vars, is.null, logical(1))]
  vars <- vars[nzchar(vars)]
  intersect(vars, names(data))
}

# Emit PF_FACTOR_SINGLE_LEVEL for each factor in `vars` with < 2 observed
# levels in `data` (already complete-cased by the caller).
.check_single_level <- function(vars, data, add) {
  for (v in .safe_vars(vars, data)) {
    if (is.factor(data[[v]]) && nlevels(droplevels(data[[v]])) < 2L) {
      add("PF_FACTOR_SINGLE_LEVEL", "error",
          paste0("Variable '", v,
                 "' has only one level remaining after removing missing values."))
    }
  }
}

# Build the deduplicated predictor vector from exposure + covariates.
.safe_preds <- function(exposure, covariates) {
  preds <- unique(c(exposure, covariates))
  preds <- preds[!vapply(preds, is.null, logical(1))]
  preds[nzchar(preds)]
}
