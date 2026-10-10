# =============================================================================
# app.R  -  SnapCart Lite Shiny dashboard (4 tabs)
# Run:  shiny::runApp()   (from the project root, after run_all.R)
# =============================================================================
library(shiny); library(shinydashboard); library(DT)
library(ggplot2); library(dplyr); library(readr)

for (f in c("R/05_utils.R", "R/01_ocr_vision.R", "R/02_parse_claude.R")) source(f)
ensure_dirs()

# Serve the PNGs from output/figures at the URL path /figs
addResourcePath("figs", "output/figures")

# Read a CSV if it exists, else NULL (app still loads before training)
read_if <- function(path) if (file.exists(path)) read_csv(path, show_col_types = FALSE) else NULL

hist_df    <- read_if("data/historical_expenses.csv")
monthly_df <- read_if("output/tables/monthly_totals.csv")
next_fc    <- read_if("output/tables/next_month_forecast.csv")
comparison <- read_if("output/tables/model_comparison.csv")
glm_cm     <- read_if("output/tables/glm_confusion_matrix.csv")

# Defaults: mock Claude unless USE_MOCK_LLM=FALSE; mock OCR if no Vision key.
default_mock_llm <- identical(toupper(Sys.getenv("USE_MOCK_LLM", "TRUE")), "TRUE")
default_mock_ocr <- !nzchar(Sys.getenv("GOOGLE_VISION_API_KEY"))

# ------------------------------- UI ------------------------------------------
ui <- dashboardPage(
  skin = "blue",
  dashboardHeader(title = "SnapCart Lite"),
  dashboardSidebar(sidebarMenu(
    id = "tabs",
    menuItem("Upload Receipt",     tabName = "upload",   icon = icon("camera")),
    menuItem("Scan History",       tabName = "history",  icon = icon("list")),
    menuItem("Spending Forecast",  tabName = "forecast", icon = icon("chart-line")),
    menuItem("Model Performance",  tabName = "models",   icon = icon("table"))
  )),
  dashboardBody(tabItems(

    # ---- Tab 1: Upload Receipt (live OCR + Claude pipeline) ----
    tabItem("upload", fluidRow(
      box(title = "1. Upload receipt", width = 4, status = "primary",
          solidHeader = TRUE,
          fileInput("img", "Receipt photo (PNG/JPG)",
                    accept = c("image/png", "image/jpeg")),
          checkboxInput("use_mock_ocr", "Use MOCK OCR (no Vision key needed)",
                        value = default_mock_ocr),
          checkboxInput("use_mock", "Use MOCK Claude (saves API credit)",
                        value = default_mock_llm),
          actionButton("process", "Extract & Save", class = "btn-primary",
                       icon = icon("play")),
          hr(), imageOutput("preview", height = "auto")),
      box(title = "2. Raw OCR text (Google Cloud Vision)", width = 8,
          status = "info", solidHeader = TRUE,
          verbatimTextOutput("ocr_text")),
      box(title = "3. Structured receipt (Claude JSON -> tibble)", width = 8,
          status = "success", solidHeader = TRUE,
          valueBoxOutput("total_box", width = 6),
          DTOutput("parsed_tbl"))
    )),

    # ---- Tab 2: Scan History ----
    tabItem("history", box(
      title = "All stored receipts (data/receipts.csv)", width = 12,
      status = "primary", solidHeader = TRUE,
      DTOutput("history_tbl"), br(),
      downloadButton("dl_receipts", "Download CSV"))),

    # ---- Tab 3: Spending Forecast ----
    tabItem("forecast",
      fluidRow(
        valueBoxOutput("fc_box", width = 6),
        valueBoxOutput("fc_range_box", width = 6)),
      fluidRow(
        box(title = "Monthly spending + next-month forecast", width = 12,
            plotOutput("trend_plot", height = 300))),
      fluidRow(
        box(title = "Historical spend by category", width = 6,
            plotOutput("hist_cat_plot", height = 300)),
        box(title = "Your scanned receipts by category", width = 6,
            plotOutput("rcpt_cat_plot", height = 300)))),

    # ---- Tab 4: Model Performance ----
    tabItem("models",
      fluidRow(box(title = "Model comparison (held-out 20% test set)", width = 12,
                   status = "primary", solidHeader = TRUE,
                   DTOutput("cmp_tbl"),
                   p(em("RMSE in INR; R\u00b2 on the log scale the models were fit on. ",
                        "Accuracy/Sensitivity/F1 apply to the classifier only.")))),
      fluidRow(
        box(title = "Linear Regression", width = 4,
            tags$img(src = "figs/lm_actual_vs_pred.png",  width = "100%")),
        box(title = "Random Forest", width = 4,
            tags$img(src = "figs/rf_actual_vs_pred.png",  width = "100%")),
        box(title = "Logistic Regression", width = 4,
            tags$img(src = "figs/glm_actual_vs_pred.png", width = "100%"))),
      fluidRow(box(title = "Logistic Regression confusion matrix (counts)",
                   width = 6, tableOutput("cm_tbl"))))
  ))
)

# ------------------------------ SERVER ---------------------------------------
server <- function(input, output, session) {

  rv <- reactiveValues(receipts = load_receipts(), ocr = "", parsed = NULL)

  # Preview the uploaded image
  output$preview <- renderImage({
    req(input$img)
    list(src = input$img$datapath, contentType = input$img$type, width = "100%")
  }, deleteFile = FALSE)

  # Full pipeline: Vision OCR -> Claude (or MOCK) -> validate -> append CSV
  observeEvent(input$process, {
    req(input$img)
    ok <- withProgress(message = "Processing receipt", value = 0, {
      tryCatch({
        incProgress(0.1, detail = if (input$use_mock_ocr) "OCR (MOCK)..." else "Google Cloud Vision OCR...")
        txt <- if (input$use_mock_ocr) ocr_receipt_MOCK() else ocr_receipt(input$img$datapath)
        rv$ocr <- txt

        incProgress(0.4, detail = if (input$use_mock) "Claude (MOCK)..." else "Claude API...")
        tbl <- parse_receipt(txt, mock = input$use_mock)

        incProgress(0.3, detail = "Saving to data/receipts.csv...")
        append_receipt(tbl)
        rv$receipts <- load_receipts()
        rv$parsed   <- tbl
        TRUE
      }, error = function(e) {
        showNotification(conditionMessage(e), type = "error", duration = 12)
        FALSE
      })
    })
    if (isTRUE(ok)) showNotification("Receipt parsed and saved.", type = "message")
  })

  output$ocr_text   <- renderText({ if (nzchar(rv$ocr)) rv$ocr else "Upload a receipt and click 'Extract & Save'." })
  output$parsed_tbl <- renderDT({ req(rv$parsed); datatable(rv$parsed, rownames = FALSE, options = list(dom = "tip", pageLength = 8)) })
  output$total_box  <- renderValueBox({
    req(rv$parsed)
    valueBox(sprintf("\u20b9%.2f", sum(rv$parsed$price)),
             paste("Items total -", rv$parsed$merchant[1] %||% "Unknown merchant"),
             icon = icon("receipt"), color = "green")
  })

  # Tab 2
  output$history_tbl <- renderDT(datatable(rv$receipts, rownames = FALSE, filter = "top"))
  output$dl_receipts <- downloadHandler(
    filename = function() "snapcart_receipts.csv",
    content  = function(file) write_csv(rv$receipts, file))

  # Tab 3
  output$fc_box <- renderValueBox({
    if (is.null(next_fc)) return(valueBox("N/A", "Run run_all.R first", color = "red"))
    valueBox(sprintf("\u20b9%.0f", next_fc$forecast),
             paste("Forecast spend for", format(next_fc$period, "%B %Y")),
             icon = icon("chart-line"), color = "blue")
  })
  output$fc_range_box <- renderValueBox({
    if (is.null(next_fc)) return(valueBox("N/A", "No forecast file", color = "red"))
    valueBox(sprintf("\u20b9%.0f - \u20b9%.0f", next_fc$lo80, next_fc$hi80),
             "80% prediction interval", icon = icon("arrows-up-down"), color = "purple")
  })
  output$trend_plot <- renderPlot({
    validate(need(!is.null(monthly_df), "Run run_all.R to generate monthly totals."))
    p <- ggplot(monthly_df, aes(period, total)) +
      geom_line(colour = "#2c7fb8") + geom_point(colour = "#2c7fb8") +
      labs(x = NULL, y = "Total spend (INR)") + theme_minimal(base_size = 13)
    if (!is.null(next_fc))
      p <- p + geom_pointrange(data = next_fc,
                               aes(x = period, y = forecast, ymin = lo80, ymax = hi80),
                               colour = "red", inherit.aes = FALSE)
    p
  })
  output$hist_cat_plot <- renderPlot({
    validate(need(!is.null(hist_df), "Run run_all.R first."))
    hist_df |> group_by(item_category) |> summarise(total = sum(amount), .groups = "drop") |>
      ggplot(aes(reorder(item_category, total), total)) +
      geom_col(fill = "#2c7fb8") + coord_flip() +
      labs(x = NULL, y = "Total spend (INR)") + theme_minimal(base_size = 13)
  })
  output$rcpt_cat_plot <- renderPlot({
    validate(need(nrow(rv$receipts) > 0, "No receipts scanned yet."))
    rv$receipts |> group_by(category) |> summarise(total = sum(price), .groups = "drop") |>
      ggplot(aes(reorder(category, total), total)) +
      geom_col(fill = "#41ab5d") + coord_flip() +
      labs(x = NULL, y = "Total spend (INR)") + theme_minimal(base_size = 13)
  })

  # Tab 4
  output$cmp_tbl <- renderDT({
    validate(need(!is.null(comparison), "Run run_all.R first."))
    datatable(comparison, rownames = FALSE, options = list(dom = "t"))
  })
  output$cm_tbl <- renderTable({
    req(glm_cm)
    tidyr::pivot_wider(glm_cm, names_from = Reference, values_from = Freq,
                       names_prefix = "Actual ")
  })
}

shinyApp(ui, server)
