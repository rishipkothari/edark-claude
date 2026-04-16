#' Analysis Preflight Validation Service
#'
#' Provides \code{validate_analysis()}, a pure function that checks an
#' \code{analysis_spec} + dataset pair for validity before running any
#' analysis operation. Implements all Tier 1 and Tier 2 checks from PRD §8.2.
#'
#' @name service_analysis_validation
NULL


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
#'   }
#'   Each message is a list with fields \code{code}, \code{level}, and
#'   \code{message}.
#' @export
validate_analysis <- function(spec, data, tier = "full", verbose = FALSE) {

  # Guard: NULL spec treated as no-outcome
  if (is.null(spec)) {
    msg <- list(code = "PF_NO_OUTCOME", level = "error",
                message = "No outcome variable assigned.")
    return(list(validity_flag = "invalid",
                messages         = list(msg),
                display_messages = list(msg)))
  }

  msgs <- list()

  .add <- function(code, level, txt) {
    msgs[[length(msgs) + 1L]] <<- list(code = code, level = level, message = txt)
  }

  roles      <- if (!is.null(spec$variable_roles)) spec$variable_roles else list()
  outcome    <- roles$outcome_variable
  exposure   <- roles$exposure_variable
  subject_id <- roles$subject_id_variable
  covariates <- roles$final_model_covariates
  model_type <- spec$model_design$model_type

  # ── Tier 1: Core Data Validity ──────────────────────────────────────────────

  if (is.null(outcome) || !nzchar(outcome)) {
    .add("PF_NO_OUTCOME", "error", "No outcome variable assigned.")
    return(.finalize(msgs, verbose))
  }

  if (is.null(data) || !outcome %in% names(data)) {
    return(.finalize(msgs, verbose))
  }

  # Complete cases over outcome + exposure + subject ID for Tier 1
  t1_vars <- .safe_vars(c(outcome, exposure, subject_id), data)
  cc1     <- stats::complete.cases(data[, t1_vars, drop = FALSE])
  data_t1 <- data[cc1, , drop = FALSE]
  n_t1    <- nrow(data_t1)

  if (n_t1 == 0L) {
    .add("PF_ZERO_COMPLETE", "error", "No complete cases remain.")
    return(.finalize(msgs, verbose))
  }

  out_t1           <- data_t1[[outcome]]
  out_is_binary    <- is.factor(out_t1) && length(levels(droplevels(out_t1))) == 2L
  out_is_continuous <- is.numeric(out_t1)

  if (out_is_binary && length(unique(as.integer(out_t1))) < 2L) {
    .add("PF_OUTCOME_NO_VARIANCE_BINARY", "error", "Outcome has no events.")
  }

  if (out_is_continuous && length(unique(out_t1)) < 2L) {
    .add("PF_OUTCOME_NO_VARIANCE_CONTINUOUS", "error",
         "Outcome has only one unique value.")
  }

  # PF_FACTOR_SINGLE_LEVEL — check predictors visible at this tier
  check_fac_vars <- if (!is.null(covariates) && length(covariates) > 0) {
    intersect(covariates, names(data_t1))
  } else {
    names(data_t1)[vapply(data_t1, is.factor, logical(1))]
  }
  for (v in check_fac_vars) {
    if (is.factor(data_t1[[v]]) &&
        length(levels(droplevels(data_t1[[v]]))) == 1L) {
      .add("PF_FACTOR_SINGLE_LEVEL", "error",
           paste0("Variable '", v,
                  "' has only one level remaining after removing missing values."))
    }
  }

  if (tier == "tier1") return(.finalize(msgs, verbose))

  # ── Tier 2: Model Specification ─────────────────────────────────────────────

  predictors <- .safe_preds(exposure, covariates)

  if (length(predictors) == 0L) {
    .add("PF_NO_PREDICTORS", "error", "No predictor variables assigned.")
  }

  # Full complete-case subset over all model variables
  n_total <- nrow(data)
  t2_vars <- .safe_vars(c(outcome, predictors, subject_id), data)
  cc2     <- stats::complete.cases(data[, t2_vars, drop = FALSE])
  data_t2 <- data[cc2, , drop = FALSE]
  n_t2    <- nrow(data_t2)
  n_miss  <- n_total - n_t2

  # Missing data warnings
  if (n_miss > 0L) {
    pct <- n_miss / n_total
    .add("PF_MISSING_ANY", "warning",
         paste0(n_miss, " row", if (n_miss != 1L) "s" else "",
                " contain missing values. Complete-case analysis will exclude ",
                if (n_miss != 1L) "these" else "this", ". Report in methods."))
    if (pct > 0.5) {
      .add("PF_MISSING_GT50", "warning",
           "Complete-case analysis excludes more than 50% of data. Results may not be representative.")
    } else if (pct > 0.2) {
      .add("PF_MISSING_GT20", "warning",
           "Complete-case analysis excludes more than 20% of data. Review missingness.")
    }
  }

  if (n_t2 == 0L) return(.finalize(msgs, verbose))

  out_t2         <- data_t2[[outcome]]
  out_binary_t2  <- is.factor(out_t2) && length(levels(droplevels(out_t2))) == 2L
  out_cont_t2    <- is.numeric(out_t2)

  # PF_OUTCOME_MODEL_MISMATCH
  if (!is.null(model_type)) {
    if (model_type %in% c("logistic", "logistic_mixed") && !out_binary_t2) {
      .add("PF_OUTCOME_MODEL_MISMATCH", "error",
           "Selected model requires a binary outcome but the outcome variable is not binary.")
    }
    if (model_type %in% c("linear", "linear_mixed") && !out_cont_t2) {
      .add("PF_OUTCOME_MODEL_MISMATCH", "error",
           "Selected model requires a continuous outcome but the outcome variable is not continuous.")
    }
  }

  # Mixed model checks
  if (!is.null(model_type) && model_type %in% c("linear_mixed", "logistic_mixed")) {
    if (is.null(subject_id) || !nzchar(subject_id)) {
      .add("PF_MIXED_NO_SUBJECT", "error",
           "Mixed model requires a subject ID variable. Assign one in Step 1.")
    } else if (subject_id %in% names(data_t2)) {
      cluster_sizes <- table(data_t2[[subject_id]])
      n_clusters    <- length(cluster_sizes)

      if (n_clusters <= 1L) {
        .add("PF_MIXED_SINGLE_CLUSTER", "error",
             "Mixed model requires more than one cluster. Only one subject ID value found in complete cases.")
      } else {
        if (n_clusters < 10L) {
          .add("PF_FEW_CLUSTERS", "warning",
               paste0("Only ", n_clusters,
                      " cluster", if (n_clusters != 1L) "s" else "",
                      " detected. Mixed model estimates may be unstable with few clusters."))
        }
        cv <- stats::sd(as.numeric(cluster_sizes)) / mean(as.numeric(cluster_sizes))
        if (!is.nan(cv) && cv > 1) {
          .add("PF_UNBALANCED_CLUSTERS", "warning",
               "Clusters are highly unbalanced in size. Interpret mixed model estimates cautiously.")
        }
      }
    }
  }

  # Logistic-specific EPV and outcome prevalence checks
  if (!is.null(model_type) &&
      model_type %in% c("logistic", "logistic_mixed") &&
      out_binary_t2 &&
      length(predictors) > 0L) {

    ev_counts  <- table(droplevels(out_t2))
    n_events   <- min(ev_counts)
    event_rate <- n_events / n_t2
    n_preds    <- length(predictors)
    epv        <- n_events / n_preds

    if (epv < 5) {
      .add("PF_LOW_EPV_5", "warning",
           paste0("Fewer than 5 events per variable (EPV = ", round(epv, 1L),
                  "). High risk of overfitting. Reduce covariates."))
    } else if (epv < 10) {
      .add("PF_LOW_EPV_10", "warning",
           paste0("Fewer than 10 outcome events per candidate variable (EPV = ",
                  round(epv, 1L), "). Consider reducing covariates."))
    }

    if (event_rate < 0.05 || event_rate > 0.95) {
      .add("PF_RARE_OUTCOME", "warning",
           paste0("Outcome prevalence is ", round(event_rate * 100, 1L),
                  "%. Wald inference is fragile with rare events."))
    }
  }

  # PF_RARE_FACTOR_LEVEL
  for (v in intersect(predictors, names(data_t2))) {
    if (is.factor(data_t2[[v]])) {
      lev_counts <- table(droplevels(data_t2[[v]]))
      if (any(lev_counts < 5L)) {
        .add("PF_RARE_FACTOR_LEVEL", "warning",
             paste0("Variable '", v, "' has a level with fewer than 5 observations."))
      }
    }
  }

  # PF_EXPOSURE_NOT_IN_MODEL
  if (!is.null(exposure) && nzchar(exposure) && length(predictors) > 0L) {
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

  # Notes — only shown in verbose mode
  if (verbose) {
    .add("PF_SAMPLE_SUMMARY", "note",
         paste0("N = ", n_total, " total; ", n_t2, " complete case",
                if (n_t2 != 1L) "s" else "", "; ", n_miss, " excluded."))

    if (!is.null(model_type)) {
      .add("PF_MODEL_SUMMARY", "note",
           paste0("Model: ", model_type, ". Predictors: ", length(predictors), "."))
    }

    if (length(predictors) == 1L) {
      .add("PF_SINGLE_COVARIATE", "note", "Model has a single predictor.")
    }

    ref_levels <- roles$reference_levels
    if (!is.null(ref_levels) && length(ref_levels) > 0L) {
      ref_str <- paste(names(ref_levels), "=",
                       vapply(ref_levels, as.character, character(1)),
                       collapse = "; ")
      .add("PF_REFERENCE_LEVELS", "note", paste0("Reference levels: ", ref_str))
    }

    t2_types <- vapply(t2_vars, function(v) class(data[[v]])[1L], character(1))
    .add("PF_DATA_STRUCTURE", "note",
         paste0("Variables: ",
                paste(paste0(t2_vars, " (", t2_types, ")"), collapse = ", ")))
  }

  .finalize(msgs, verbose)
}


# ── Internal helpers ─────────────────────────────────────────────────────────

# Assemble validity_flag and display_messages from the raw message list.
.finalize <- function(msgs, verbose) {
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
  list(validity_flag    = validity_flag,
       messages         = msgs,
       display_messages = display_msgs)
}

# Return the subset of `vars` that are non-NULL, non-empty, and present in `data`.
.safe_vars <- function(vars, data) {
  vars <- vars[!vapply(vars, is.null, logical(1))]
  vars <- vars[nzchar(vars)]
  intersect(vars, names(data))
}

# Build the deduplicated predictor vector from exposure + covariates.
.safe_preds <- function(exposure, covariates) {
  preds <- unique(c(exposure, covariates))
  preds <- preds[!vapply(preds, is.null, logical(1))]
  preds[nzchar(preds)]
}
