# app.R
# Preview Bootswatch themes and inspect common Bootstrap 5 classes in Shiny/bslib

library(shiny)
library(bslib)
library(htmltools)

# All Bootswatch themes currently supported by bslib for Bootstrap 5
bootswatch_themes <- c(
  "default",
  "cerulean",
  "cosmo",
  "cyborg",
  "darkly",
  "flatly",
  "journal",
  "litera",
  "lumen",
  "lux",
  "materia",
  "minty",
  "morph",
  "pulse",
  "quartz",
  "sandstone",
  "simplex",
  "sketchy",
  "slate",
  "solar",
  "spacelab",
  "superhero",
  "united",
  "vapor",
  "yeti",
  "zephyr"
)

class_reference <- data.frame(
  class = c(
    "btn btn-primary",
    "btn btn-secondary",
    "btn btn-success",
    "btn btn-info",
    "btn btn-warning",
    "btn btn-danger",
    "btn btn-light",
    "btn btn-dark",
    "alert alert-primary",
    "alert alert-secondary",
    "alert alert-success",
    "alert alert-info",
    "alert alert-warning",
    "alert alert-danger",
    "text-bg-primary",
    "text-bg-secondary",
    "text-bg-success",
    "text-bg-info",
    "text-bg-warning",
    "text-bg-danger",
    "badge text-bg-primary",
    "badge text-bg-secondary",
    "badge text-bg-success",
    "badge text-bg-info",
    "badge text-bg-warning",
    "badge text-bg-danger",
    "list-group-item list-group-item-primary",
    "list-group-item list-group-item-secondary",
    "list-group-item list-group-item-success",
    "list-group-item list-group-item-info",
    "list-group-item list-group-item-warning",
    "list-group-item list-group-item-danger"
  ),
  category = c(
    rep("Button", 8),
    rep("Alert", 6),
    rep("Text background utility", 6),
    rep("Badge", 6),
    rep("List group item", 6)
  ),
  purpose = c(
    "Main action button",
    "Secondary button",
    "Success/state-positive button",
    "Informational button",
    "Warning/caution button",
    "Destructive/danger button",
    "Light neutral button",
    "Dark neutral button",
    "Primary alert",
    "Secondary alert",
    "Success alert",
    "Info alert",
    "Warning alert",
    "Danger alert",
    "Primary background utility",
    "Secondary background utility",
    "Success background utility",
    "Info background utility",
    "Warning background utility",
    "Danger background utility",
    "Primary badge",
    "Secondary badge",
    "Success badge",
    "Info badge",
    "Warning badge",
    "Danger badge",
    "Primary contextual list item",
    "Secondary contextual list item",
    "Success contextual list item",
    "Info contextual list item",
    "Warning contextual list item",
    "Danger contextual list item"
  ),
  stringsAsFactors = FALSE
)

make_theme <- function(theme_name) {
  if (identical(theme_name, "default")) {
    bs_theme(version = 5)
  } else {
    bs_theme(version = 5, bootswatch = theme_name)
  }
}

swatch_box <- function(label, bg_class, text = NULL) {
  div(
    class = paste(
      "rounded border p-3 d-flex align-items-center justify-content-between",
      bg_class
    ),
    style = "min-height: 72px;",
    span(class = "fw-semibold", label),
    span(class = "small", if (is.null(text)) bg_class else text)
  )
}

class_demo_block <- function(css_class) {
  category <- class_reference$category[class_reference$class == css_class][1]
  purpose <- class_reference$purpose[class_reference$class == css_class][1]

  demo_tag <- switch(
    TRUE,
    grepl("^btn ", css_class) ~ tags$button(
      type = "button",
      class = css_class,
      "Example"
    ),
    grepl("^alert ", css_class) ~ div(
      class = css_class,
      role = "alert",
      "Example content using ", tags$code(css_class)
    ),
    grepl("^text-bg-", css_class) ~ div(
      class = paste(css_class, "rounded p-3"),
      "Example content using ", tags$code(css_class)
    ),
    grepl("^badge ", css_class) ~ span(
      class = css_class,
      "Example badge"
    ),
    grepl("^list-group-item ", css_class) ~ div(
      class = "list-group",
      div(class = css_class, "Example list-group item")
    ),
    div("No preview available")
  )

  div(
    class = "border rounded p-3 mb-3",
    div(class = "fw-semibold", css_class),
    div(class = "text-muted small mb-2", paste(category, "-", purpose)),
    demo_tag
  )
}

ui <- fluidPage(
  theme = make_theme("flatly"),
  tags$head(
    tags$style(HTML("
      .sticky-panel {
        position: sticky;
        top: 12px;
      }
      code {
        white-space: pre-wrap;
      }
      .class-meta dt {
        font-weight: 600;
      }
      .class-meta dd {
        margin-bottom: 0.5rem;
      }
    "))
  ),

  titlePanel("Bootswatch Theme Explorer"),

  fluidRow(
    column(
      width = 3,
      div(
        class = "sticky-panel",
        card(
          card_header("Controls"),
          card_body(
            selectInput(
              "theme_name",
              "Bootswatch theme",
              choices = bootswatch_themes,
              selected = "flatly"
            ),
            checkboxInput(
              "show_all_classes",
              "Show all class previews",
              value = FALSE
            ),
            selectizeInput(
              "class_pick",
              "Focus on specific classes",
              choices = class_reference$class,
              multiple = TRUE,
              options = list(placeholder = "Choose one or more classes")
            ),
            hr(),
            h6("Notes"),
            tags$ul(
              tags$li("The app switches the page theme live."),
              tags$li("The previews show how common Bootstrap classes render under that theme."),
              tags$li("Most colors come from Bootstrap semantic tokens like primary, warning, success, etc.")
            )
          )
        ),
        br(),
        card(
          card_header("Theme constructor"),
          card_body(
            verbatimTextOutput("theme_code")
          )
        )
      )
    ),

    column(
      width = 9,
      navset_tab(
        nav_panel(
          "Overview",
          br(),
          card(
            card_header("Semantic color preview"),
            card_body(
              fluidRow(
                column(6, swatch_box("Primary", "text-bg-primary")),
                column(6, swatch_box("Secondary", "text-bg-secondary"))
              ),
              br(),
              fluidRow(
                column(6, swatch_box("Success", "text-bg-success")),
                column(6, swatch_box("Info", "text-bg-info"))
              ),
              br(),
              fluidRow(
                column(6, swatch_box("Warning", "text-bg-warning")),
                column(6, swatch_box("Danger", "text-bg-danger"))
              ),
              br(),
              fluidRow(
                column(6, swatch_box("Light", "text-bg-light")),
                column(6, swatch_box("Dark", "text-bg-dark"))
              )
            )
          ),
          br(),
          card(
            card_header("Common component preview"),
            card_body(
              h6("Buttons"),
              div(
                class = "d-flex flex-wrap gap-2 mb-3",
                tags$button(class = "btn btn-primary", "Primary"),
                tags$button(class = "btn btn-secondary", "Secondary"),
                tags$button(class = "btn btn-success", "Success"),
                tags$button(class = "btn btn-info", "Info"),
                tags$button(class = "btn btn-warning", "Warning"),
                tags$button(class = "btn btn-danger", "Danger"),
                tags$button(class = "btn btn-light", "Light"),
                tags$button(class = "btn btn-dark", "Dark")
              ),
              h6("Alerts"),
              div(class = "alert alert-primary", "Primary alert"),
              div(class = "alert alert-secondary", "Secondary alert"),
              div(class = "alert alert-success", "Success alert"),
              div(class = "alert alert-info", "Info alert"),
              div(class = "alert alert-warning", "Warning alert"),
              div(class = "alert alert-danger", "Danger alert")
            )
          )
        ),

        nav_panel(
          "Class explorer",
          br(),
          uiOutput("class_preview_ui")
        ),

        nav_panel(
          "Class reference",
          br(),
          tableOutput("class_table"),
          br(),
          card(
            card_header("How to think about these classes"),
            card_body(
              tags$dl(
                class = "class-meta",
                tags$dt("Semantic classes"),
                tags$dd("Primary, secondary, success, info, warning, danger, light, and dark are theme-level color roles."),
                tags$dt("Component classes"),
                tags$dd("Classes like alert, btn, badge, and list-group-item define structure and behavior."),
                tags$dt("Combined classes"),
                tags$dd("A class string like btn btn-warning means: render a button component, then apply the warning semantic color variant.")
              )
            )
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  observe({
    session$setCurrentTheme(make_theme(input$theme_name))
  })

  output$theme_code <- renderText({
    if (identical(input$theme_name, "default")) {
      "bslib::bs_theme(version = 5)"
    } else {
      paste0(
        "bslib::bs_theme(\n",
        "  version = 5,\n",
        "  bootswatch = \"", input$theme_name, "\"\n",
        ")"
      )
    }
  })

  output$class_table <- renderTable({
    class_reference
  }, striped = TRUE, bordered = TRUE, hover = TRUE)

  output$class_preview_ui <- renderUI({
    classes_to_show <- if (isTRUE(input$show_all_classes) || length(input$class_pick) == 0) {
      class_reference$class
    } else {
      input$class_pick
    }

    tagList(lapply(classes_to_show, class_demo_block))
  })
}

shinyApp(ui, server)