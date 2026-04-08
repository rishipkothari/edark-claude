# generate_report.R
# Core report generation logic — no Shiny dependency.
# Called by module_report.R (downloadHandler) and edark_report() programmatic API.


# ---------------------------------------------------------------------------
# Shared utilities
# ---------------------------------------------------------------------------

# Generate a safe HTML anchor ID from arbitrary text.
# Used by both section builders and the HTML assembler so anchors are consistent.
.make_html_anchor <- function(x) {
  x <- tolower(x)
  x <- gsub("[^a-z0-9_-]", "-", x)
  x <- gsub("-+", "-", x)
  x <- gsub("^-+|-+$", "", x)
  paste0("sec-", x)
}


# ---------------------------------------------------------------------------
# Dataset-level summary
# ---------------------------------------------------------------------------

#' Build a wide EDA summary table across all numeric and factor columns
#'
#' Returns a data.frame with one row per analyzed column. Numeric stats are
#' NA-filled for factor columns; Top_values is NA-filled for numeric columns.
#' Datetime and character columns are excluded.
#'
#' @param dataset A data.frame.
#' @param column_types Named character vector from detect_column_types().
#' @return A data.frame suitable for flextable().
#' @noRd
.build_dataset_summary <- function(dataset, column_types) {
  analyzed_cols <- names(column_types)[column_types %in% c("numeric", "factor")]
  analyzed_cols <- analyzed_cols[analyzed_cols %in% names(dataset)]

  rows <- lapply(analyzed_cols, function(col) {
    x        <- dataset[[col]]
    col_type <- column_types[[col]]
    n_total  <- length(x)
    n_miss   <- sum(is.na(x))
    pct_miss <- sprintf("%.1f%%", 100 * n_miss / n_total)
    n_unique <- length(unique(x[!is.na(x)]))

    if (col_type == "numeric") {
      vals <- x[!is.na(x)]
      data.frame(
        Variable   = col,
        Type       = "numeric",
        N          = n_total,
        N_missing  = n_miss,
        Pct_miss   = pct_miss,
        N_unique   = n_unique,
        Min        = if (length(vals)) round(min(vals), 2)    else NA_real_,
        Max        = if (length(vals)) round(max(vals), 2)    else NA_real_,
        Mean       = if (length(vals)) round(mean(vals), 2)   else NA_real_,
        SD         = if (length(vals)) round(sd(vals), 2)     else NA_real_,
        Median     = if (length(vals)) round(median(vals), 2) else NA_real_,
        IQR        = if (length(vals)) round(IQR(vals), 2)    else NA_real_,
        Skewness   = tryCatch(round(e1071::skewness(vals), 2), error = function(e) NA_real_),
        Kurtosis   = tryCatch(round(e1071::kurtosis(vals), 2), error = function(e) NA_real_),
        Top_values = NA_character_,
        stringsAsFactors = FALSE
      )
    } else {
      vals <- x[!is.na(x)]
      tbl  <- sort(table(as.character(vals)), decreasing = TRUE)
      top5 <- if (length(tbl) == 0) NA_character_ else
        paste(head(names(tbl), 5), collapse = " | ")
      data.frame(
        Variable   = col,
        Type       = "factor",
        N          = n_total,
        N_missing  = n_miss,
        Pct_miss   = pct_miss,
        N_unique   = n_unique,
        Min        = NA_real_,
        Max        = NA_real_,
        Mean       = NA_real_,
        SD         = NA_real_,
        Median     = NA_real_,
        IQR        = NA_real_,
        Skewness   = NA_real_,
        Kurtosis   = NA_real_,
        Top_values = top5,
        stringsAsFactors = FALSE
      )
    }
  })

  do.call(rbind, rows)
}


#' Style the dataset summary data.frame as a flextable
#' @noRd
.style_dataset_summary_ft <- function(df) {
  # Replace NA numerics with em-dash for display
  num_cols <- c("Min", "Max", "Mean", "SD", "Median", "IQR", "Skewness", "Kurtosis")
  df_disp  <- df
  for (col in num_cols) {
    df_disp[[col]] <- ifelse(is.na(df_disp[[col]]), "\u2014", as.character(df_disp[[col]]))
  }
  df_disp$Top_values <- ifelse(is.na(df_disp$Top_values), "\u2014", df_disp$Top_values)

  right_cols <- c("N", "N_missing", "Pct_miss", "N_unique",
                  "Min", "Max", "Mean", "SD", "Median", "IQR", "Skewness", "Kurtosis")

  ft <- flextable::flextable(df_disp)
  ft <- flextable::set_header_labels(ft,
    Variable   = "Variable",
    Type       = "Type",
    N          = "N",
    N_missing  = "N Missing",
    Pct_miss   = "% Missing",
    N_unique   = "Unique",
    Min        = "Min",
    Max        = "Max",
    Mean       = "Mean",
    SD         = "SD",
    Median     = "Median",
    IQR        = "IQR",
    Skewness   = "Skewness",
    Kurtosis   = "Kurtosis",
    Top_values = "Top Values (categorical)"
  )
  ft <- flextable::font(ft, fontname = "Arial", part = "all")
  ft <- flextable::fontsize(ft, size = 7, part = "body")
  ft <- flextable::fontsize(ft, size = 8, part = "header")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::bg(ft,
    i   = seq(1, nrow(df_disp), by = 2),
    bg  = "#F7F7F7",
    part = "body"
  )
  ft <- flextable::align(ft, part = "header", align = "center")
  ft <- flextable::align(ft, j = c("Variable", "Type", "Top_values"),
                         align = "left",  part = "body")
  ft <- flextable::align(ft, j = right_cols, align = "right", part = "body")
  ft <- flextable::border_remove(ft)
  ft <- flextable::hline_top(ft,  part = "header",
                              border = officer::fp_border(width = 1.2))
  ft <- flextable::hline(ft,      part = "header",
                          border = officer::fp_border(width = 0.6))
  ft <- flextable::hline_bottom(ft, part = "body",
                                 border = officer::fp_border(width = 1.2))
  ft <- flextable::width(ft, j = "Variable",   width = 1.5)
  ft <- flextable::width(ft, j = "Type",       width = 0.6)
  ft <- flextable::width(ft, j = "N",          width = 0.4)
  ft <- flextable::width(ft, j = "N_missing",  width = 0.6)
  ft <- flextable::width(ft, j = "Pct_miss",   width = 0.6)
  ft <- flextable::width(ft, j = "N_unique",   width = 0.5)
  ft <- flextable::width(ft, j = "Min",        width = 0.55)
  ft <- flextable::width(ft, j = "Max",        width = 0.55)
  ft <- flextable::width(ft, j = "Mean",       width = 0.55)
  ft <- flextable::width(ft, j = "SD",         width = 0.55)
  ft <- flextable::width(ft, j = "Median",     width = 0.55)
  ft <- flextable::width(ft, j = "IQR",        width = 0.45)
  ft <- flextable::width(ft, j = "Skewness",   width = 0.6)
  ft <- flextable::width(ft, j = "Kurtosis",   width = 0.6)
  ft <- flextable::width(ft, j = "Top_values", width = 2.0)
  ft <- flextable::set_table_properties(ft, layout = "fixed", align = "center")
  ft
}


# ---------------------------------------------------------------------------
# Table One
# ---------------------------------------------------------------------------

#' Build a Table One data frame (one row per variable; factor vars multi-row).
#'
#' For numeric variables: "mean (SD)" in the Overall and per-stratum columns
#' with a Kruskal-Wallis p-value (omitted when not stratified).
#' For factor variables: N (%) per level with a chi-square / Fisher's p-value.
#'
#' @param dataset A data.frame.
#' @param column_types Named character vector from detect_column_types().
#' @param variables Character vector of variable names to include.
#' @param stratify_by Column name to stratify by, or NULL.
#' @return A data.frame suitable for .style_tableone_ft().
#' @noRd
.build_tableone_df <- function(dataset, column_types, variables, stratify_by) {
  has_strat  <- !is.null(stratify_by) && nzchar(stratify_by) &&
                stratify_by %in% names(dataset)
  strata     <- if (has_strat) levels(factor(dataset[[stratify_by]])) else character(0)
  n_overall  <- nrow(dataset)
  n_strata   <- if (has_strat) vapply(strata, function(s)
    sum(!is.na(dataset[[stratify_by]]) & dataset[[stratify_by]] == s, na.rm = TRUE),
    integer(1)) else integer(0)

  # Build dynamic column names
  overall_col <- paste0("Overall (N=", n_overall, ")")
  strat_cols  <- if (has_strat)
    paste0(strata, " (N=", n_strata, ")") else character(0)
  p_col       <- "p-value"

  # Helper: format mean (SD)
  fmt_mean_sd <- function(x) {
    vals <- x[!is.na(x)]
    if (length(vals) == 0) return(NA_character_)
    paste0(round(mean(vals), 1), " (", round(sd(vals), 1), ")")
  }

  all_cols <- c("Variable", overall_col, strat_cols, if (has_strat) p_col)

  rows <- lapply(variables, function(var) {
    if (!var %in% names(column_types)) return(NULL)
    vtype <- column_types[[var]]
    x     <- dataset[[var]]

    if (vtype == "numeric") {
      # One row: "var, mean (SD)"
      row <- setNames(
        as.list(rep(NA_character_, length(all_cols))),
        all_cols
      )
      row[["Variable"]]   <- paste0(var, ", mean (SD)")
      row[[overall_col]]  <- fmt_mean_sd(x)
      if (has_strat) {
        for (i in seq_along(strata)) {
          idx          <- !is.na(dataset[[stratify_by]]) & dataset[[stratify_by]] == strata[i]
          row[[strat_cols[i]]] <- fmt_mean_sd(x[idx])
        }
        # Kruskal-Wallis p
        grps <- split(x[!is.na(x)], droplevels(factor(
          dataset[[stratify_by]][!is.na(x)],
          levels = strata
        )))
        grps <- grps[lengths(grps) > 0]
        row[[p_col]] <- tryCatch({
          if (length(grps) >= 2) {
            kt <- kruskal.test(x ~ factor(dataset[[stratify_by]], levels = strata),
                               data = dataset)
            formatC(kt$p.value, format = "g", digits = 3)
          } else NA_character_
        }, error = function(e) NA_character_)
      }
      list(as.data.frame(row, stringsAsFactors = FALSE))

    } else if (vtype == "factor") {
      lvls <- if (is.factor(x)) levels(x) else
        sort(unique(as.character(x[!is.na(x)])))
      n_valid_overall <- sum(!is.na(x))

      # Chi-square / Fisher's p
      p_val <- if (has_strat) {
        tryCatch({
          tbl    <- table(factor(x, levels = lvls),
                          factor(dataset[[stratify_by]], levels = strata))
          chi_ct <- suppressWarnings(chisq.test(tbl))
          if (any(chi_ct$expected < 5)) {
            fp <- fisher.test(tbl, simulate.p.value = TRUE, B = 2000)$p.value
            formatC(fp, format = "g", digits = 3)
          } else {
            formatC(chi_ct$p.value, format = "g", digits = 3)
          }
        }, error = function(e) NA_character_)
      } else NA_character_

      # Header row (variable name + N overall + N per stratum + p)
      hdr <- setNames(as.list(rep(NA_character_, length(all_cols))), all_cols)
      hdr[["Variable"]]  <- var
      hdr[[overall_col]] <- paste0("N=", n_valid_overall)
      if (has_strat) {
        for (i in seq_along(strata)) {
          idx <- !is.na(dataset[[stratify_by]]) & dataset[[stratify_by]] == strata[i]
          hdr[[strat_cols[i]]] <- paste0("N=", sum(!is.na(x[idx])))
        }
        hdr[[p_col]] <- p_val
      }

      # Level rows (indented with two spaces)
      level_rows <- lapply(lvls, function(lv) {
        row <- setNames(as.list(rep(NA_character_, length(all_cols))), all_cols)
        row[["Variable"]] <- paste0("  ", lv)
        n_lv <- sum(!is.na(x) & as.character(x) == lv)
        pct  <- if (n_valid_overall > 0) round(100 * n_lv / n_valid_overall, 1) else 0
        row[[overall_col]] <- paste0(n_lv, " (", pct, "%)")
        if (has_strat) {
          for (i in seq_along(strata)) {
            idx      <- !is.na(dataset[[stratify_by]]) & dataset[[stratify_by]] == strata[i]
            x_s      <- x[idx]
            n_valid_s <- sum(!is.na(x_s))
            n_lv_s   <- sum(!is.na(x_s) & as.character(x_s) == lv)
            pct_s    <- if (n_valid_s > 0) round(100 * n_lv_s / n_valid_s, 1) else 0
            row[[strat_cols[i]]] <- paste0(n_lv_s, " (", pct_s, "%)")
          }
          row[[p_col]] <- NA_character_
        }
        as.data.frame(row, stringsAsFactors = FALSE)
      })

      c(list(as.data.frame(hdr, stringsAsFactors = FALSE)), level_rows)
    } else {
      NULL
    }
  })

  rows <- unlist(rows, recursive = FALSE)
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) return(data.frame())
  do.call(rbind, rows)
}


#' Style a Table One data frame as a flextable
#' @noRd
.style_tableone_ft <- function(df, has_strat = FALSE) {
  if (nrow(df) == 0 || ncol(df) == 0) return(flextable::flextable(data.frame()))

  # Bold header rows (non-indented Variable rows that are not numeric stats)
  is_header_row <- !grepl("^  ", df[["Variable"]]) & !grepl(", mean \\(SD\\)$", df[["Variable"]])
  # Indent level rows
  df_disp <- df
  df_disp[["Variable"]] <- trimws(df_disp[["Variable"]])  # display trim (indentation via padding)

  ft <- flextable::flextable(df_disp)
  ft <- flextable::font(ft, fontname = "Arial", part = "all")
  ft <- flextable::fontsize(ft, size = 8,  part = "body")
  ft <- flextable::fontsize(ft, size = 9,  part = "header")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::bold(ft, i = which(is_header_row), part = "body")
  ft <- flextable::padding(ft,
    i    = which(grepl("^  ", df[["Variable"]])),
    j    = "Variable",
    padding.left = 16,
    part = "body"
  )
  ft <- flextable::bg(ft, i = seq(1, nrow(df_disp), by = 2), bg = "#F7F7F7", part = "body")
  ft <- flextable::border_remove(ft)
  ft <- flextable::hline_top(ft,    part = "header", border = officer::fp_border(width = 1.2))
  ft <- flextable::hline(ft,        part = "header", border = officer::fp_border(width = 0.6))
  ft <- flextable::hline_bottom(ft, part = "body",   border = officer::fp_border(width = 1.2))
  ft <- flextable::align(ft, part = "header", align = "center")
  ft <- flextable::align(ft, j = "Variable", align = "left",   part = "body")
  ft <- flextable::align(ft, j = setdiff(names(df_disp), "Variable"),
                         align = "center", part = "body")
  ft <- flextable::width(ft, j = "Variable", width = 2.0)
  ft <- flextable::set_table_properties(ft, layout = "autofit", align = "center")
  ft
}


# ---------------------------------------------------------------------------
# Per-section table helpers
# ---------------------------------------------------------------------------

#' Univariate numeric: key-value table with Overall + per-stratum columns
#' @noRd
.build_univariate_numeric_table <- function(dataset, variable, stratify_by) {
  compute_stats <- function(x) {
    vals <- x[!is.na(x)]
    n    <- length(x)
    list(
      N        = n,
      Missing  = sum(is.na(x)),
      Mean     = if (length(vals)) round(mean(vals),   2) else NA_real_,
      Median   = if (length(vals)) round(median(vals), 2) else NA_real_,
      SD       = if (length(vals)) round(sd(vals),     2) else NA_real_,
      IQR      = if (length(vals)) round(IQR(vals),    2) else NA_real_,
      Min      = if (length(vals)) round(min(vals),    2) else NA_real_,
      Max      = if (length(vals)) round(max(vals),    2) else NA_real_,
      Skewness = tryCatch(round(e1071::skewness(vals), 2), error = function(e) NA_real_),
      Kurtosis = tryCatch(round(e1071::kurtosis(vals), 2), error = function(e) NA_real_)
    )
  }

  x         <- dataset[[variable]]
  overall   <- compute_stats(x)
  stat_names <- names(overall)

  df <- data.frame(Statistic = stat_names,
                   Overall   = unlist(overall),
                   stringsAsFactors = FALSE, row.names = NULL)

  if (!is.null(stratify_by) && stratify_by %in% names(dataset)) {
    strata <- levels(factor(dataset[[stratify_by]]))
    for (s in strata) {
      idx      <- !is.na(dataset[[stratify_by]]) & as.character(dataset[[stratify_by]]) == s
      s_stats  <- compute_stats(x[idx])
      df[[s]]  <- unlist(s_stats)
    }
  }

  df
}


#' Univariate factor: level counts with Overall + per-stratum columns
#' @noRd
.build_univariate_factor_table <- function(dataset, variable, stratify_by) {
  x      <- dataset[[variable]]
  levels_all <- if (is.factor(x)) levels(x) else sort(unique(as.character(x[!is.na(x)])))

  count_pct <- function(vec, lvls) {
    n_total <- length(vec)
    n_miss  <- sum(is.na(vec))
    tbl     <- table(factor(vec, levels = lvls))
    pcts    <- round(100 * as.integer(tbl) / (n_total - n_miss), 1)
    list(n_total = n_total, n_miss = n_miss, counts = as.integer(tbl), pcts = pcts)
  }

  overall <- count_pct(x, levels_all)

  # Header rows: N total, N missing
  header_rows <- data.frame(
    Level         = c("N", "N Missing"),
    `N (Overall)` = c(overall$n_total, overall$n_miss),
    `% (Overall)` = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE, check.names = FALSE
  )

  # Level rows
  level_rows <- data.frame(
    Level         = levels_all,
    `N (Overall)` = overall$counts,
    `% (Overall)` = overall$pcts,
    stringsAsFactors = FALSE, check.names = FALSE
  )

  df <- rbind(header_rows, level_rows)

  if (!is.null(stratify_by) && stratify_by %in% names(dataset)) {
    strata <- levels(factor(dataset[[stratify_by]]))
    for (s in strata) {
      idx    <- !is.na(dataset[[stratify_by]]) & as.character(dataset[[stratify_by]]) == s
      s_res  <- count_pct(x[idx], levels_all)
      n_col  <- paste0("N (", s, ")")
      pct_col <- paste0("% (", s, ")")
      df[[n_col]]   <- c(s_res$n_total, s_res$n_miss, s_res$counts)
      df[[pct_col]] <- c(NA_real_,       NA_real_,       s_res$pcts)
    }
  }

  df
}


#' Bivariate numeric x numeric: correlation stats table
#' @noRd
.build_bivariate_num_num_table <- function(dataset, col_a, col_b, stratify_by) {
  run_cor <- function(x, y) {
    complete <- !is.na(x) & !is.na(y)
    if (sum(complete) < 3) return(list(r = NA, r2 = NA, p = NA, ci_lo = NA, ci_hi = NA))
    ct <- cor.test(x[complete], y[complete], method = "pearson")
    list(
      r     = round(ct$estimate, 3),
      r2    = round(ct$estimate^2, 3),
      p     = formatC(ct$p.value, format = "g", digits = 3),
      ci_lo = round(ct$conf.int[1], 3),
      ci_hi = round(ct$conf.int[2], 3)
    )
  }

  x       <- dataset[[col_a]]
  y       <- dataset[[col_b]]
  overall <- run_cor(x, y)

  df <- data.frame(
    Statistic = c("r", "R\u00b2", "p-value", "95% CI (low)", "95% CI (high)"),
    Overall   = c(overall$r, overall$r2, overall$p, overall$ci_lo, overall$ci_hi),
    stringsAsFactors = FALSE
  )

  if (!is.null(stratify_by) && stratify_by %in% names(dataset)) {
    strata <- levels(factor(dataset[[stratify_by]]))
    for (s in strata) {
      idx     <- !is.na(dataset[[stratify_by]]) & as.character(dataset[[stratify_by]]) == s
      s_res   <- run_cor(x[idx], y[idx])
      df[[s]] <- c(s_res$r, s_res$r2, s_res$p, s_res$ci_lo, s_res$ci_hi)
    }
  }

  df
}


#' Bivariate numeric x factor: distribution by factor level + Kruskal-Wallis p
#' @noRd
.build_bivariate_num_fac_table <- function(dataset, numeric_col, factor_col, stratify_by) {
  num_vec <- dataset[[numeric_col]]
  fac_vec <- dataset[[factor_col]]
  lvls    <- if (is.factor(fac_vec)) levels(fac_vec) else
    sort(unique(as.character(fac_vec[!is.na(fac_vec)])))

  compute_by_level <- function(num, fac, prefix = "") {
    rows <- lapply(lvls, function(lv) {
      idx  <- !is.na(fac) & as.character(fac) == lv
      vals <- num[idx & !is.na(num)]
      data.frame(
        Level  = lv,
        N      = sum(idx),
        Mean   = if (length(vals)) round(mean(vals),   2) else NA_real_,
        Median = if (length(vals)) round(median(vals), 2) else NA_real_,
        SD     = if (length(vals)) round(sd(vals),     2) else NA_real_,
        IQR    = if (length(vals)) round(IQR(vals),    2) else NA_real_,
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, rows)
  }

  df <- compute_by_level(num_vec, fac_vec)

  # Kruskal-Wallis p appended as footer row
  mw_p <- tryCatch({
    grps <- split(num_vec[!is.na(num_vec)], droplevels(factor(fac_vec[!is.na(num_vec)], levels = lvls)))
    grps <- grps[lengths(grps) > 0]
    if (length(grps) >= 2) {
      wt <- kruskal.test(num_vec ~ factor(fac_vec, levels = lvls), data = dataset)
      formatC(wt$p.value, format = "g", digits = 3)
    } else NA_character_
  }, error = function(e) NA_character_)

  footer <- data.frame(
    Level  = if (!is.na(mw_p)) paste0("Kruskal-Wallis p = ", mw_p) else "Kruskal-Wallis p = NA",
    N      = NA_real_, Mean = NA_real_, Median = NA_real_, SD = NA_real_, IQR = NA_real_,
    stringsAsFactors = FALSE
  )

  rbind(df, footer)
}


#' Bivariate factor x factor: cross-tab N (%) + chi-square (or Fisher's) footer
#' Uses Fisher's exact test (simulated p-value) when any expected cell count < 5.
#' @noRd
.build_bivariate_fac_fac_table <- function(dataset, col_a, col_b, stratify_by) {
  make_crosstab <- function(a_vec, b_vec, a_lvls, b_lvls) {
    tbl   <- table(factor(a_vec, levels = a_lvls), factor(b_vec, levels = b_lvls))
    n_row <- rowSums(tbl)
    rows  <- lapply(seq_along(a_lvls), function(i) {
      cells <- vapply(seq_along(b_lvls), function(j) {
        n   <- tbl[i, j]
        pct <- if (n_row[i] > 0) round(100 * n / n_row[i], 1) else 0
        paste0(n, " (", pct, "%)")
      }, character(1))
      as.data.frame(t(c(Level = a_lvls[i], cells)), stringsAsFactors = FALSE)
    })
    out <- do.call(rbind, rows)
    names(out) <- c(col_a, b_lvls)
    out
  }

  a_vec  <- dataset[[col_a]]
  b_vec  <- dataset[[col_b]]
  a_lvls <- if (is.factor(a_vec)) levels(a_vec) else sort(unique(as.character(a_vec[!is.na(a_vec)])))
  b_lvls <- if (is.factor(b_vec)) levels(b_vec) else sort(unique(as.character(b_vec[!is.na(b_vec)])))

  df <- make_crosstab(a_vec, b_vec, a_lvls, b_lvls)

  # Use Fisher's exact when any expected count < 5, chi-square otherwise
  tbl    <- table(factor(a_vec, levels = a_lvls), factor(b_vec, levels = b_lvls))
  chi_ct <- suppressWarnings(chisq.test(tbl))
  footer_label <- tryCatch({
    if (any(chi_ct$expected < 5)) {
      fisher_p <- fisher.test(tbl, simulate.p.value = TRUE, B = 2000)$p.value
      paste0("Fisher's exact p = ", formatC(fisher_p, format = "g", digits = 3),
             " (simulated; expected cell counts < 5)")
    } else {
      paste0("Chi-square p = ", formatC(chi_ct$p.value, format = "g", digits = 3))
    }
  }, error = function(e) "Test p = NA")

  footer            <- df[1, , drop = FALSE]
  footer[1, ]       <- NA
  footer[[col_a]]   <- footer_label
  rbind(df, footer)
}


#' Style a section summary data.frame as a compact flextable
#' @noRd
.style_section_ft <- function(df) {
  ft <- flextable::flextable(df)
  ft <- flextable::font(ft, fontname = "Arial", part = "all")
  ft <- flextable::fontsize(ft, size = 8,  part = "body")
  ft <- flextable::fontsize(ft, size = 9,  part = "header")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::bg(ft,
    i    = seq(1, nrow(df), by = 2),
    bg   = "#F7F7F7",
    part = "body"
  )
  ft <- flextable::border_remove(ft)
  ft <- flextable::hline_top(ft,    part = "header", border = officer::fp_border(width = 1.2))
  ft <- flextable::hline(ft,        part = "header", border = officer::fp_border(width = 0.6))
  ft <- flextable::hline_bottom(ft, part = "body",   border = officer::fp_border(width = 1.2))
  ft <- flextable::set_table_properties(ft, layout = "autofit", align = "center")
  ft
}


# ---------------------------------------------------------------------------
# Section builders
# ---------------------------------------------------------------------------

.build_all_vars_sections <- function(dataset, column_types, variables, stratify_variable,
                                      progress_fn = NULL, plot_aesthetics = list()) {
  # Only numeric and factor — datetime excluded
  variables <- variables[variables %in% names(column_types) &
                           column_types[variables] %in% c("numeric", "factor")]
  # Describing a variable against itself as stratifier is nonsensical — skip it
  if (!is.null(stratify_variable) && nzchar(stratify_variable))
    variables <- variables[variables != stratify_variable]
  n <- length(variables)

  sections <- vector("list", n)
  for (i in seq_along(variables)) {
    if (!is.null(progress_fn)) progress_fn(i / n, paste0("Variable ", i, " of ", n, ": ", variables[[i]]))

    var      <- variables[[i]]
    var_type <- column_types[[var]]

    stratify_by <- if (!is.null(stratify_variable) && nzchar(stratify_variable) &&
                        stratify_variable %in% names(dataset))
      stratify_variable else NULL

    spec <- modifyList(list(
      plot_type        = route_plot_type(var_type, NULL),
      column_a         = var,
      column_b         = NULL,
      primary_role     = "exposure",
      stratify_by      = stratify_by,
      color_palette    = "Set2",
      show_data_labels = FALSE,
      show_legend      = TRUE,
      legend_position  = "top",
      trend_resolution = "Month"
    ), plot_aesthetics)

    plot_obj <- render_plot(spec, dataset, split_panels = TRUE)

    summary_df <- if (var_type == "numeric") {
      .build_univariate_numeric_table(dataset, var, stratify_by)
    } else {
      .build_univariate_factor_table(dataset, var, stratify_by)
    }
    summary_ft <- .style_section_ft(summary_df)

    sections[[i]] <- list(
      title      = var,
      anchor     = .make_html_anchor(var),
      plot_obj   = plot_obj,
      summary_ft = summary_ft
    )
  }
  Filter(Negate(is.null), sections)
}


.build_primary_vs_others_sections <- function(dataset, column_types,
                                               secondary_vars,
                                               primary_variable,
                                               primary_role,
                                               stratify_variable,
                                               progress_fn = NULL,
                                               plot_aesthetics = list()) {
  # Only numeric and factor — datetime excluded from both primary and secondary
  valid_types <- c("numeric", "factor")
  if (!primary_variable %in% names(column_types) ||
      !column_types[[primary_variable]] %in% valid_types)
    stop("primary_variable must be numeric or factor.")

  secondary_vars <- secondary_vars[
    secondary_vars %in% names(column_types) &
    column_types[secondary_vars] %in% valid_types
  ]

  # Skip any secondary variable that is also the stratify variable — plotting
  # a variable against itself as both a comparison and a stratifier is nonsensical.
  if (!is.null(stratify_variable) && nzchar(stratify_variable)) {
    secondary_vars <- secondary_vars[secondary_vars != stratify_variable]
  }

  n <- length(secondary_vars)
  sections <- vector("list", n)

  for (i in seq_along(secondary_vars)) {
    if (!is.null(progress_fn)) progress_fn(i / n, paste0("Section ", i, " of ", n, ": ", secondary_vars[[i]]))

    sec_var <- secondary_vars[[i]]

    # Axis assignment from role
    if (primary_role == "exposure") {
      col_a      <- primary_variable
      col_b      <- sec_var
      col_a_type <- column_types[[primary_variable]]
      col_b_type <- column_types[[sec_var]]
    } else {
      col_a      <- sec_var
      col_b      <- primary_variable
      col_a_type <- column_types[[sec_var]]
      col_b_type <- column_types[[primary_variable]]
    }

    # violin_jitter normalization: factor must be col_a (X)
    if (col_a_type == "numeric" && col_b_type == "factor") {
      tmp        <- col_a;      col_a      <- col_b;      col_b      <- tmp
      tmp        <- col_a_type; col_a_type <- col_b_type; col_b_type <- tmp
    }

    stratify_by <- if (!is.null(stratify_variable) && nzchar(stratify_variable) &&
                        stratify_variable %in% names(dataset))
      stratify_variable else NULL

    spec <- modifyList(list(
      plot_type        = route_plot_type(col_a_type, col_b_type),
      column_a         = col_a,
      column_b         = col_b,
      primary_role     = primary_role,
      stratify_by      = stratify_by,
      color_palette    = "Set2",
      show_data_labels = FALSE,
      show_legend      = TRUE,
      legend_position  = "top",
      trend_resolution = "Month"
    ), plot_aesthetics)

    plot_obj <- render_plot(spec, dataset, split_panels = TRUE)

    # Select appropriate bivariate table helper
    summary_df <- if (col_a_type == "numeric" && col_b_type == "numeric") {
      .build_bivariate_num_num_table(dataset, col_a, col_b, stratify_by)
    } else if (col_a_type == "factor" && col_b_type == "numeric") {
      # col_a is factor (X), col_b is numeric (Y) after normalisation
      .build_bivariate_num_fac_table(dataset, col_b, col_a, stratify_by)
    } else if (col_a_type == "factor" && col_b_type == "factor") {
      .build_bivariate_fac_fac_table(dataset, col_a, col_b, stratify_by)
    } else {
      NULL
    }

    summary_ft <- if (!is.null(summary_df)) .style_section_ft(summary_df) else NULL

    title <- paste(primary_variable, "\u00d7", sec_var)
    if (!is.null(stratify_by))
      title <- paste(title, "\u00b7 stratified by", stratify_by)

    sections[[i]] <- list(
      title      = title,
      anchor     = .make_html_anchor(sec_var),   # keyed on secondary var for summary table links
      plot_obj   = plot_obj,
      summary_ft = summary_ft
    )
  }
  Filter(Negate(is.null), sections)
}


# ---------------------------------------------------------------------------
# Format assemblers
# ---------------------------------------------------------------------------

# Helper: add a title bar to a PPTX slide
.pptx_title <- function(prs, title) {
  officer::ph_with(
    prs,
    value    = title,
    location = officer::ph_location(left = 0.4, top = 0.2, width = 12.2, height = 0.55)
  )
}

# Helper: add a plot to a PPTX slide (full-width body area)
# Patchwork objects are rasterised to PNG because rvg::dml() only accepts plain ggplots.
.pptx_plot <- function(prs, plot_obj) {
  plot_loc <- officer::ph_location(left = 0.4, top = 0.85, width = 12.2, height = 6.0)
  if (inherits(plot_obj, "patchwork")) {
    tmp_png <- tempfile(fileext = ".png")
    on.exit(unlink(tmp_png), add = TRUE)
    ggplot2::ggsave(tmp_png, plot = plot_obj, width = 12.2, height = 6.0,
                    units = "in", dpi = 150)
    officer::ph_with(prs,
      value    = officer::external_img(src = tmp_png, width = 12.2, height = 6.0),
      location = plot_loc)
  } else {
    officer::ph_with(prs,
      value    = rvg::dml(ggobj = plot_obj),
      location = plot_loc)
  }
}

# Helper: add a flextable to a PPTX slide (full-width body area)
.pptx_table <- function(prs, ft) {
  officer::ph_with(prs,
    value    = ft,
    location = officer::ph_location(left = 0.4, top = 0.85, width = 12.2, height = 6.0))
}


.assemble_pptx <- function(sections, dataset_summary_df, output_path,
                             progress_fn = NULL,
                             include_dataset_summary = TRUE,
                             tableone_ft = NULL) {
  prs <- officer::read_pptx(
    system.file("templates/ppt_16x9_blank_template.pptx", package = "edark")
  )

  # ── Optional: Table One slide ────────────────────────────────────────────
  if (!is.null(tableone_ft)) {
    prs <- officer::add_slide(prs, layout = "Blank", master = "Office Theme")
    prs <- .pptx_title(prs, "Table 1")
    prs <- .pptx_table(prs, tableone_ft)
  }

  # ── Optional: Dataset summary slide ─────────────────────────────────────
  if (isTRUE(include_dataset_summary)) {
    prs <- officer::add_slide(prs, layout = "Blank", master = "Office Theme")
    prs <- .pptx_title(prs, "Dataset Summary")
    ds_ft <- .style_dataset_summary_ft(dataset_summary_df)
    prs   <- .pptx_table(prs, ds_ft)
  }

  # ── Per-section: plot slide + table slide ────────────────────────────────
  n <- length(sections)
  for (i in seq_along(sections)) {
    if (!is.null(progress_fn)) progress_fn(i / n, paste0("Slide ", i, " of ", n))
    sec <- sections[[i]]

    # Plot slide(s) — split_panels may give a list of two ggplots
    plots <- if (is.list(sec$plot_obj) && !inherits(sec$plot_obj, "ggplot")) sec$plot_obj else list(sec$plot_obj)
    for (pl in plots) {
      prs <- officer::add_slide(prs, layout = "Blank", master = "Office Theme")
      prs <- .pptx_title(prs, sec$title)
      prs <- .pptx_plot(prs, pl)
    }

    # Table slide (only if a summary flextable exists)
    if (!is.null(sec$summary_ft)) {
      prs <- officer::add_slide(prs, layout = "Blank", master = "Office Theme")
      prs <- .pptx_title(prs, sec$title)
      prs <- .pptx_table(prs, sec$summary_ft)
    }
  }

  print(prs, target = output_path)
  invisible(output_path)
}


.assemble_docx <- function(sections, dataset_summary_df, output_path,
                             progress_fn = NULL,
                             include_dataset_summary = TRUE,
                             tableone_ft = NULL) {
  doc <- officer::read_docx()

  # ── Optional: Table One page ─────────────────────────────────────────────
  if (!is.null(tableone_ft)) {
    doc <- officer::body_add_par(doc, "Table 1", style = "heading 1")
    doc <- flextable::body_add_flextable(doc, tableone_ft)
    doc <- officer::body_add_break(doc)
  }

  # ── Optional: Dataset summary page ──────────────────────────────────────
  if (isTRUE(include_dataset_summary)) {
    doc <- officer::body_add_par(doc, "Dataset Summary", style = "heading 1")
    ds_ft <- .style_dataset_summary_ft(dataset_summary_df)
    doc   <- flextable::body_add_flextable(doc, ds_ft)
    doc   <- officer::body_add_break(doc)
  }

  # ── Per-section: plot page + table page ──────────────────────────────────
  n <- length(sections)
  for (i in seq_along(sections)) {
    if (!is.null(progress_fn)) progress_fn(i / n, paste0("Section ", i, " of ", n))
    sec <- sections[[i]]

    # Plot page(s) — split_panels may give a list of two ggplots
    plots <- if (is.list(sec$plot_obj) && !inherits(sec$plot_obj, "ggplot")) sec$plot_obj else list(sec$plot_obj)
    for (pl in plots) {
      doc <- officer::body_add_par(doc, sec$title, style = "heading 1")
      if (inherits(pl, "patchwork")) {
        tmp_png <- tempfile(fileext = ".png")
        ggplot2::ggsave(tmp_png, plot = pl, width = 6.5, height = 5, units = "in", dpi = 150)
        doc <- officer::body_add_img(doc, src = tmp_png, width = 6.5, height = 5)
        unlink(tmp_png)
      } else {
        doc <- officer::body_add_gg(doc, value = pl, width = 6.5, height = 5, res = 150)
      }
      doc <- officer::body_add_break(doc)
    }

    # Table page (plot loop already ended with a break)
    if (!is.null(sec$summary_ft)) {
      doc <- officer::body_add_par(doc, sec$title, style = "heading 1")
      doc <- flextable::body_add_flextable(doc, sec$summary_ft)
      if (i < n) doc <- officer::body_add_break(doc)
    } else if (i < n) {
      # no table — the break from the plot loop is sufficient, nothing extra needed
    }
  }

  print(doc, target = output_path)
  invisible(output_path)
}


.assemble_html <- function(sections, dataset_summary_df, output_path,
                             report_type = "all_vars",
                             linked_var_anchors = NULL,
                             include_dataset_summary = TRUE,
                             tableone_ft = NULL) {
  template_path <- system.file("report_template.Rmd", package = "edark")

  rmarkdown::render(
    input             = template_path,
    output_file       = normalizePath(output_path, mustWork = FALSE),
    output_dir        = dirname(normalizePath(output_path, mustWork = FALSE)),
    intermediates_dir = tempdir(),
    params            = list(
      sections                = sections,
      dataset_summary_df      = dataset_summary_df,
      report_type             = report_type,
      linked_var_anchors      = linked_var_anchors,
      include_dataset_summary = include_dataset_summary,
      tableone_ft             = tableone_ft
    ),
    quiet             = TRUE,
    envir             = new.env(parent = globalenv())
  )

  invisible(output_path)
}


# ---------------------------------------------------------------------------
# Main function
# ---------------------------------------------------------------------------

#' Generate an EDARK report
#'
#' Builds a report from a dataset and a list of plot sections. Called by
#' \code{module_report.R}'s \code{downloadHandler} and by \code{edark_report()}.
#'
#' @param dataset A \code{data.frame} — the working dataset.
#' @param column_types Named character vector of column types (from
#'   \code{detect_column_types()}).
#' @param report_type \code{"all_vars"} or \code{"primary_vs_others"}.
#' @param variables Character vector of variable names to include in the report.
#' @param primary_variable For \code{"primary_vs_others"}: the primary variable name.
#' @param primary_role \code{"exposure"} or \code{"outcome"}.
#' @param stratify_variable Optional column name to stratify all bivariate plots by.
#' @param format Output format: \code{"pptx"}, \code{"docx"}, or \code{"html"}.
#' @param output_path Absolute path to write the report to.
#' @param progress_fn Optional \code{function(fraction, detail)} called at each
#'   section milestone. Intended for use with \code{shiny::setProgress()}.
#'
#' @return Invisibly returns \code{output_path}.
#'
#' @export
generate_report <- function(dataset,
                             column_types,
                             report_type,
                             variables,
                             primary_variable        = NULL,
                             primary_role            = "exposure",
                             stratify_variable       = NULL,
                             format,
                             output_path,
                             progress_fn             = NULL,
                             include_dataset_summary = TRUE,
                             include_tableone        = FALSE,
                             ggplot_theme            = "minimal",
                             color_palette           = "Set2",
                             show_data_labels        = FALSE,
                             show_legend             = TRUE,
                             legend_position         = "top") {
  stopifnot(report_type %in% c("all_vars", "primary_vs_others"))
  stopifnot(format %in% c("pptx", "docx", "html"))
  stopifnot(is.data.frame(dataset), length(variables) >= 1)

  # Build dataset-level summary once (numeric + factor only)
  if (!is.null(progress_fn)) progress_fn(0, "Building dataset summary...")
  dataset_summary_df <- .build_dataset_summary(dataset, column_types)

  # Build Table One if requested (only meaningful for all_vars / descriptive mode)
  tableone_ft <- if (isTRUE(include_tableone) && report_type == "all_vars") {
    strat <- if (!is.null(stratify_variable) && nzchar(stratify_variable))
      stratify_variable else NULL
    to_vars <- variables[variables %in% names(column_types) &
                           column_types[variables] %in% c("numeric", "factor")]
    if (!is.null(strat)) to_vars <- setdiff(to_vars, strat)
    to_df <- tryCatch(
      .build_tableone_df(dataset, column_types, to_vars, strat),
      error = function(e) NULL
    )
    if (!is.null(to_df) && nrow(to_df) > 0)
      .style_tableone_ft(to_df, has_strat = !is.null(strat))
    else NULL
  } else NULL

  plot_aesthetics <- list(
    ggplot_theme     = ggplot_theme,
    color_palette    = color_palette,
    show_data_labels = show_data_labels,
    show_legend      = show_legend,
    legend_position  = legend_position
  )

  sections <- if (report_type == "all_vars") {
    .build_all_vars_sections(dataset, column_types, variables, stratify_variable,
                              progress_fn = progress_fn, plot_aesthetics = plot_aesthetics)
  } else {
    if (is.null(primary_variable))
      stop("primary_variable must be specified for report_type = 'primary_vs_others'")
    secondary_vars <- setdiff(variables, primary_variable)
    if (length(secondary_vars) == 0)
      stop("No secondary variables to plot — ensure variables contains columns besides primary_variable.")
    .build_primary_vs_others_sections(
      dataset, column_types, secondary_vars,
      primary_variable, primary_role, stratify_variable,
      progress_fn = progress_fn, plot_aesthetics = plot_aesthetics
    )
  }

  if (length(sections) == 0)
    stop("No sections could be built — check that selected variables exist in the dataset.")

  # Build linked_var_anchors for HTML: named vector mapping variable name → anchor ID.
  # For all_vars: every section variable links to its section.
  # For primary_vs_others: only secondary variables link to their sections.
  linked_var_anchors <- if (report_type == "all_vars") {
    setNames(
      sapply(sections, function(s) s$anchor),
      sapply(sections, function(s) s$title)
    )
  } else {
    sec_var_names <- setdiff(variables, primary_variable)
    sec_var_names <- sec_var_names[
      sec_var_names %in% names(column_types) &
      column_types[sec_var_names] %in% c("numeric", "factor")
    ]
    if (!is.null(stratify_variable) && nzchar(stratify_variable))
      sec_var_names <- sec_var_names[sec_var_names != stratify_variable]
    setNames(
      sapply(sections, function(s) s$anchor),
      sec_var_names[seq_along(sections)]
    )
  }

  if (!is.null(progress_fn)) progress_fn(0.95, "Assembling output...")

  switch(format,
    pptx = .assemble_pptx(sections, dataset_summary_df, output_path, progress_fn,
                          include_dataset_summary = include_dataset_summary,
                          tableone_ft             = tableone_ft),
    docx = .assemble_docx(sections, dataset_summary_df, output_path, progress_fn,
                          include_dataset_summary = include_dataset_summary,
                          tableone_ft             = tableone_ft),
    html = .assemble_html(sections, dataset_summary_df, output_path,
                          report_type             = report_type,
                          linked_var_anchors      = linked_var_anchors,
                          include_dataset_summary = include_dataset_summary,
                          tableone_ft             = tableone_ft)
  )

  invisible(output_path)
}


# ── Custom report helpers ─────────────────────────────────────────────────────

# Build a warning placeholder plot for items whose columns are no longer valid.
.custom_item_error_plot <- function(title, msg) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0.5, y = 0.5,
                      label = paste0("Could not render: ", title, "\n", msg),
                      hjust = 0.5, vjust = 0.5, colour = "grey40", size = 4) +
    ggplot2::theme_void()
}

# Map each custom report item's plot spec to a section object, re-rendering
# using the current working dataset. Returns a list of section objects
# {title, anchor, plot_obj, summary_ft} — the same format used by the full report
# assemblers. Items that fail to render produce a warning placeholder rather
# than aborting the entire report.
.build_custom_report_sections <- function(items, dataset, column_types,
                                           progress_fn = NULL, plot_aesthetics = list()) {
  n        <- length(items)
  sections <- vector("list", n)

  trend_types <- c("trend_count", "trend_numeric", "trend_proportion", "trend_factor")

  for (i in seq_along(items)) {
    item  <- items[[i]]
    spec  <- item$plot_spec
    title <- item$title

    if (!is.null(progress_fn))
      progress_fn(i / n, paste0("Item ", i, " of ", n, ": ", title))

    # Apply report-level aesthetics over the frozen per-item spec
    if (length(plot_aesthetics) > 0) spec <- modifyList(spec, plot_aesthetics)

    # Re-render plot from spec + current dataset; trap errors per-item
    plot_obj <- tryCatch(
      render_plot(spec, dataset, split_panels = TRUE),
      error = function(e) .custom_item_error_plot(title, conditionMessage(e))
    )

    col_a      <- spec$column_a
    col_b      <- spec$column_b
    strat      <- if (!is.null(spec$stratify_by) && nzchar(spec$stratify_by))
                    spec$stratify_by else NULL
    col_a_type <- if (!is.null(col_a) && col_a %in% names(column_types))
                    column_types[[col_a]] else NULL
    col_b_type <- if (!is.null(col_b) && col_b %in% names(column_types))
                    column_types[[col_b]] else NULL

    is_trend <- !is.null(spec$plot_type) && spec$plot_type %in% trend_types

    summary_ft <- if (is_trend) {
      NULL  # trend plots: plot only, no table (consistent with existing report behaviour)
    } else if (!is.null(col_b) && !is.null(col_a_type) && !is.null(col_b_type)) {
      summary_df <- tryCatch({
        if (col_a_type == "numeric" && col_b_type == "numeric") {
          .build_bivariate_num_num_table(dataset, col_a, col_b, strat)
        } else if (col_a_type == "factor" && col_b_type == "numeric") {
          # spec normalises violin_jitter so factor is always col_a
          .build_bivariate_num_fac_table(dataset, col_b, col_a, strat)
        } else if (col_a_type == "factor" && col_b_type == "factor") {
          .build_bivariate_fac_fac_table(dataset, col_a, col_b, strat)
        } else NULL
      }, error = function(e) NULL)
      if (!is.null(summary_df)) .style_section_ft(summary_df) else NULL
    } else if (!is.null(col_a) && !is.null(col_a_type)) {
      summary_df <- tryCatch({
        if (col_a_type == "numeric") {
          .build_univariate_numeric_table(dataset, col_a, strat)
        } else if (col_a_type == "factor") {
          .build_univariate_factor_table(dataset, col_a, strat)
        } else NULL
      }, error = function(e) NULL)
      if (!is.null(summary_df)) .style_section_ft(summary_df) else NULL
    } else {
      NULL
    }

    sections[[i]] <- list(
      title      = title,
      anchor     = .make_html_anchor(paste0("custom-", i, "-", item$id)),
      plot_obj   = plot_obj,
      summary_ft = summary_ft
    )
  }

  sections
}


#' Generate a custom report from user-curated plot items
#'
#' Shiny-free entry point for custom report generation. Takes a list of items
#' collected via the EDARK Explore tab and assembles them into a report.
#'
#' @param items List of custom report item objects as stored in
#'   `shared_state$custom_report_items`. Each must have `id`, `plot_spec`,
#'   `thumb_path`, and `title` fields.
#' @param dataset The working data frame to use for re-rendering plots and
#'   building summary tables.
#' @param column_types Named character vector mapping column names to types
#'   (`"numeric"`, `"factor"`, `"datetime"`, `"character"`).
#' @param format Output format: `"pptx"`, `"docx"`, or `"html"`.
#' @param output_path File path for the generated report.
#' @param progress_fn Optional callback `function(fraction, detail)` for
#'   progress reporting (e.g. Shiny's `setProgress`).
#'
#' @return `output_path`, invisibly.
#' @export
generate_custom_report <- function(items, dataset, column_types, format,
                                    output_path, progress_fn = NULL,
                                    ggplot_theme     = "minimal",
                                    color_palette    = "Set2",
                                    show_data_labels = FALSE,
                                    show_legend      = TRUE,
                                    legend_position  = "top") {
  stopifnot(is.list(items), length(items) >= 1)
  stopifnot(format %in% c("pptx", "docx", "html"))
  stopifnot(is.data.frame(dataset))

  if (!is.null(progress_fn)) progress_fn(0, "Building dataset summary...")
  dataset_summary_df <- .build_dataset_summary(dataset, column_types)

  plot_aesthetics <- list(
    ggplot_theme     = ggplot_theme,
    color_palette    = color_palette,
    show_data_labels = show_data_labels,
    show_legend      = show_legend,
    legend_position  = legend_position
  )

  sections <- .build_custom_report_sections(items, dataset, column_types, progress_fn,
                                             plot_aesthetics = plot_aesthetics)

  if (length(sections) == 0)
    stop("No sections could be built from the custom report items.")

  if (!is.null(progress_fn)) progress_fn(0.95, "Assembling output...")

  switch(format,
    pptx = .assemble_pptx(sections, dataset_summary_df, output_path, progress_fn),
    docx = .assemble_docx(sections, dataset_summary_df, output_path, progress_fn),
    html = .assemble_html(sections, dataset_summary_df, output_path,
                          report_type = "custom", linked_var_anchors = NULL)
  )

  invisible(output_path)
}
