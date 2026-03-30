# Author: G. Carteny (modified)
# Date: 2026-03-30

# Admin -----------------------------------------------------------------------
want = c("shiny", "DT", "shinyjs", "shinythemes", "htmltools")
have = want %in% rownames(installed.packages())
if ( any(!have) ) { install.packages( want[!have] ) }
lapply(want, library, character.only = TRUE)
options(scipen = 99)
options(shiny.maxRequestSize = 100*1024^2) # 100 MB

# UI -------------------------------------------------------------------------
ui <- fluidPage(
  theme = shinytheme("flatly"),
  useShinyjs(),
  titlePanel("Tweet annotation app"),
  sidebarLayout(
    sidebarPanel(
      fileInput("file", "Upload CSV", accept = c(".csv")),
      textInput("text_col", "Text column name", value = "text"),
      textInput("context_col", "Context column name (optional)", value = "context"),
      textInput("annotator", "Annotator name / id", value = "annotator1"),
      actionButton("load", "Load data"),
      hr(),
      actionButton("prev_btn", "Previous"),
      actionButton("next_btn", "Next"),
      actionButton("randomize", "Randomize order"),
      hr(),
      textInput("save_dir_input", 
                "Output directory (type or paste a path)", 
                value = paste0(getwd(), '/output/')),
      actionButton("set_wd_btn", "Set as output directory"),
      hr(),
      textInput("save_fname_input", "File name", value = "annotations_saved"),
      h6("Effective save directory:"),
      verbatimTextOutput("save_dir"),
      actionButton("save", "Save annotations now", icon = icon("save")),
      downloadButton("download", "Download annotated CSV"),
      width = 3
    ),
    mainPanel(
      h4("Progress"),
      textOutput("progress_text"),
      hr(),
      h4("Context (if provided)"),
      wellPanel(uiOutput("current_context")),
      h4("Text to annotate"),
      wellPanel(uiOutput("current_text")),
      # not-a-sentence control
      radioButtons("is_sentence_choice", "Is this a valid sentence?",
                   choices = c("sentence", "not a sentence"),
                   selected = "sentence", inline = TRUE),
      # Topic annotation section (side-by-side layout for 2 topics)
      fluidRow(
        column(
          width = 6,
          h5("Primary topic"),
          uiOutput("issue_ui"),
          uiOutput("uncertainty_ui"),
          uiOutput("stance_ui"),
          uiOutput("policy_ui")
        ),
        column(
          width = 6,
          hidden(div(
            id = "topic2_div",
            h5("Second topic"),
            uiOutput("issue2_ui"),
            uiOutput("uncertainty2_ui"),
            uiOutput("stance2_ui")
          ))
        )
      ),
      hr(),
      actionButton("toggle_topic2", "Add second topic"),
      br(), br(),
      actionButton("annotate", "Record annotations"),
      actionButton("save_draft", "Save draft"),
      actionButton("clear_label", "Clear annotations for this row"),
      hr(),
      h4("Review / Table"),
      DTOutput("table"),
      width = 9
    )
  )
)

# Server -----------------------------------------------------------------------
server <- function(input, output, session) {
  rv <- reactiveValues(
    df = NULL,
    order = NULL,
    pos = 1,
    loaded = FALSE,
    save_file = file.path(normalizePath(getwd(), winslash = "/"), "annotations_saved.csv"),
    tmp_save_file = NULL,
    topic2_active = FALSE
  )
  
  # Allow user to set working directory manually
  observeEvent(input$set_wd_btn, {
    req(input$save_dir_input)
    new_dir <- normalizePath(input$save_dir_input, winslash = "/", mustWork = FALSE)
    
    if (!dir.exists(new_dir)) {
      ok <- tryCatch({
        dir.create(new_dir, recursive = TRUE)
      }, error = function(e) FALSE)
      if (!ok) {
        showNotification(paste("Unable to create directory:", new_dir), type = "error")
        return()
      } else {
        showNotification(paste("Created and set working directory:", new_dir), type = "message")
      }
    } else {
      showNotification(paste("Working directory set to:", new_dir), type = "message")
    }
    
    setwd(new_dir)
    rv$save_file <- file.path(new_dir, paste0(input$save_fname_input, ".csv"))
    rv$tmp_save_file <- file.path(new_dir, paste0(tools::file_path_sans_ext(input$save_fname_input), "_tmp.csv"))
  })
  
  # labels & columns
  issue_choices <- c(
    "Labour: Undefined",
    "Labour: Salary or Pay gap",
    "Labour: Division of labour",
    "Labour: Labour rights and discrimination",
    "Labour: Other",
    "Welfare: Parental leave",
    "Welfare: Childcare and housework",
    "Welfare: Other care work",
    "Welfare: Healthcare",
    "Welfare: Education",
    "Welfare: Other",
    "Repr.: Political representation and participation",
    "Repr.: Social representation and participation",
    "Repr.: Gender-neutral language",
    "Repr.: Gender mainstreaming",
    "Repr.: Other",
    "RDV: Reproductive rights and discrimination",
    "RDV: Family rights and discrimination",
    "RDV: Sexual and gender-based violence",
    "RDV: Immigration and citizenship",
    "RDV: Other",
    "Notions: Feminism",
    "Notions: Patriarchy and heteronormativity",
    "Notions: LGBTQ+",
    "Notions: Other"
  )
  issue_col <- "issue"     # categorical 
  policy_col <- "policy_flag"    # policy flag column: "policy" / "other"
  stance_col <- "stance"         # numeric 0..10 (support scale)
  selected_col <- "selected_at"  # first time shown (set only once)
  annotated_col <- "annotated_at" # save timestamp
  uncertainty_col <- "uncertainty" # uncertainty slider related to issue
  annotator_col <- "annotator"
  not_sentence_col <- "not_sentence" # flag for not-a-sentence
  draft_col <- "draft_flag"          # draft flag (TRUE/FALSE)
  # second topic columns
  issue2_col <- "issue2"
  uncertainty2_col <- "uncertainty2"
  stance2_col <- "stance2"
  
  # helper to get context column name (NULL if empty)
  get_context_col <- reactive({
    ccol <- input$context_col
    if (is.null(ccol) || ccol == "") return(NULL)
    ccol
  })
  
  # set selected timestamp only if empty -> preserve first show time
  set_selected_time <- function(idx) {
    if (!is.null(rv$df) && idx >= 1 && idx <= nrow(rv$df)) {
      cur <- rv$df[[selected_col]][idx]
      if (is.na(cur) || identical(cur, "")) {
        rv$df[[selected_col]][idx] <- as.character(Sys.time())
      }
    }
  }
  
  observeEvent(input$load, {
    req(input$file)
    df <- read.csv(input$file$datapath, stringsAsFactors = FALSE, encoding = "UTF-8")
    if (!(input$text_col %in% colnames(df))) {
      showModal(modalDialog(
        title = "Column not found",
        paste0("Column '", input$text_col, "' not found. Available: ",
               paste(colnames(df), collapse = ", ")),
        easyClose = TRUE
      ))
      return()
    }
    
    # ensure context column exists if user specified one
    ccol <- get_context_col()
    if (!is.null(ccol) && !(ccol %in% names(df))) df[[ccol]] <- NA_character_
    
    # ensure required columns exist; create if missing
    if (!(issue_col %in% names(df))) df[[issue_col]] <- NA_character_
    if (!(policy_col %in% names(df))) df[[policy_col]] <- NA_character_
    if (!(stance_col %in% names(df))) df[[stance_col]] <- NA_real_
    if (!(annotator_col %in% names(df))) df[[annotator_col]] <- NA_character_
    if (!(annotated_col %in% names(df))) df[[annotated_col]] <- NA_character_
    if (!(selected_col %in% names(df))) df[[selected_col]] <- NA_character_
    if (!(uncertainty_col %in% names(df))) df[[uncertainty_col]] <- NA_real_
    if (!(not_sentence_col %in% names(df))) df[[not_sentence_col]] <- NA_character_
    if (!(draft_col %in% names(df))) df[[draft_col]] <- NA_character_
    # ensure second-topic columns exist (always present in CSV)
    if (!(issue2_col %in% names(df))) df[[issue2_col]] <- NA_character_
    if (!(uncertainty2_col %in% names(df))) df[[uncertainty2_col]] <- NA_real_
    if (!(stance2_col %in% names(df))) df[[stance2_col]] <- NA_real_
    
    rv$df <- df
    rv$order <- seq_len(nrow(df))
    rv$pos <- 1
    rv$loaded <- TRUE
    rv$topic2_active <- FALSE
    
    # set default save paths
    dir_norm <- normalizePath(input$save_dir_input %||% getwd(), winslash = "/", mustWork = FALSE)
    fname_input <- trimws(input$save_fname_input)
    if (fname_input == "") fname_input <- "annotations_saved"
    rv$save_file <- file.path(dir_norm, paste0(fname_input, ".csv"))
    rv$tmp_save_file <- file.path(dir_norm, paste0(tools::file_path_sans_ext(fname_input), "_tmp.csv"))
    
    # set selected timestamp for the first item immediately after load (only if empty)
    set_selected_time(rv$order[rv$pos])
  })
  
  # issue UI (select input)
  output$issue_ui <- renderUI({
    req(rv$loaded)
    selectInput(
      "issue_choice", 
      label = "Issue:",
      choices = issue_choices,
      selected = if (!is.null(rv$df[[issue_col]][rv$order[rv$pos]])) rv$df[[issue_col]][rv$order[rv$pos]] else NULL,
      multiple = FALSE,
      selectize = TRUE
    )
  })
  
  # issue2 UI (second topic) — similar to issue_ui
  output$issue2_ui <- renderUI({
    req(rv$loaded)
    selectInput(
      "issue2_choice",
      label = "Second topic - Issue:",
      choices = issue_choices,
      selected = if (!is.null(rv$df[[issue2_col]][rv$order[rv$pos]])) rv$df[[issue2_col]][rv$order[rv$pos]] else NULL,
      multiple = FALSE,
      selectize = TRUE
    )
  })
  
  # robust helper to read a numeric cell with a default fallback
  read_numeric_cell <- function(df, col, idx, default) {
    if (is.null(df) || is.null(col) || !(col %in% names(df)) || idx < 1 || idx > nrow(df)) return(as.numeric(default))
    v <- df[[col]][idx]
    v_num <- suppressWarnings(as.numeric(v))
    if (is.na(v_num)) return(as.numeric(default))
    v_num
  }
  
  # UNCERTAINTY UI (0..10) for the issue label — robust to NA/missing
  output$uncertainty_ui <- renderUI({
    req(rv$loaded, rv$df)
    idx <- rv$order[rv$pos]
    cur <- read_numeric_cell(rv$df, uncertainty_col, idx, default = 0)
    sliderInput("uncertainty",
                label = "Uncertainty for issue (0 = certain, 10 = very uncertain)",
                min = 0, max = 10, step = 1,
                value = cur,
                ticks = TRUE)
  })
  # uncertainty2 for second topic
  output$uncertainty2_ui <- renderUI({
    req(rv$loaded, rv$df)
    idx <- rv$order[rv$pos]
    cur <- read_numeric_cell(rv$df, uncertainty2_col, idx, default = 0)
    sliderInput("uncertainty2",
                label = "Uncertainty for second topic (0 = certain, 10 = very uncertain)",
                min = 0, max = 10, step = 1,
                value = cur,
                ticks = TRUE)
  })
  
  # POLICY UI (policy / other)
  output$policy_ui <- renderUI({
    req(rv$loaded)
    radioButtons("policy_choice", "Policy-related:", choices = c("policy", "other"))
  })
  
  # STANCE UI (numeric 0..10) — robust to NA/missing
  output$stance_ui <- renderUI({
    req(rv$loaded, rv$df)
    idx <- rv$order[rv$pos]
    cur <- rv$df[[stance_col]][idx]
    
    div(
      style = "display: flex; align-items: center; max-width: 400px;",  # match uncertainty width
      sliderInput(
        "stance_score",
        label = "Stance (0 = against, 10 = support)",
        min = 0, max = 10, step = 1,
        value = ifelse(is.na(cur), 5, cur),
        width = "100%"
      ),
      actionButton(
        "stance_unknown",
        "Unknown",
        class = "btn btn-outline-secondary btn-sm",
        style = "margin-left: 8px; margin-top: 20px;"
      )
    )
  })
  
  
  # Second stance (same layout)
  output$stance2_ui <- renderUI({
    req(rv$loaded, rv$df)
    idx <- rv$order[rv$pos]
    cur <- rv$df[[stance2_col]][idx]
    
    div(
      style = "display: flex; align-items: center; max-width: 400px;",  # same width
      sliderInput(
        "stance2_score",
        label = "Second topic stance (0 = against, 10 = support)",
        min = 0, max = 10, step = 1,
        value = ifelse(is.na(cur), 5, cur),
        width = "100%"
      ),
      actionButton(
        "stance2_unknown",
        "Unknown",
        class = "btn btn-outline-secondary btn-sm",
        style = "margin-left: 8px; margin-top: 20px;"
      )
    )
  })
  
  
  observeEvent(input$stance_unknown, {
    updateSliderInput(session, "stance_score", value = NA)
  })
  
  observeEvent(input$stance2_unknown, {
    updateSliderInput(session, "stance2_score", value = NA)
  })
  
  # Stance UI button css
  #   tags$style(HTML("
  #   #stance_unknown, #stance2_unknown {
  #     margin-top: -4px;
  #   }
  # "))
  
  # current context (above text)
  output$current_context <- renderUI({
    req(rv$loaded, rv$df)
    idx <- rv$order[rv$pos]
    ccol <- get_context_col()
    if (is.null(ccol) || !(ccol %in% names(rv$df))) return(NULL)
    
    ctx <- rv$df[[ccol]][idx]
    if (is.null(ctx) || is.na(ctx) || trimws(ctx) == "") return(NULL)
    
    ctx <- as.character(ctx)  # ensure proper string
    ctx <- htmltools::htmlEscape(ctx)  # escape any HTML symbols
    
    HTML(paste0(
      "<div style='background-color:#f8f9fa;padding:10px;border-radius:8px;
                 border-left:4px solid #0d6efd;margin-bottom:10px;'>
       <b>Context:</b><br>", ctx, "</div>"
    ))
  })
  
  output$current_text <- renderUI({
    req(rv$loaded, rv$df)
    idx <- rv$order[rv$pos]
    txt <- rv$df[[input$text_col]][idx]
    if (is.null(txt) || is.na(txt) || trimws(txt) == "") return(NULL)
    
    txt <- as.character(txt)
    txt <- htmltools::htmlEscape(txt)
    
    HTML(paste0(
      "<div style='background-color:#fff3cd;padding:12px;border-radius:8px;
                 border-left:4px solid #ffc107;margin-bottom:15px;'>
       <b>Text #", idx, ":</b><br>", txt, "</div>"
    ))
  })
  
  output$progress_text <- renderText({
    req(rv$loaded)
    n <- nrow(rv$df)
    annotated <- sum(!is.na(rv$df[[issue_col]]))
    paste0(sprintf("Annotated (issue): %d/%d (current index %d of %d)", annotated, n, rv$pos, n))
  })
  
  output$table <- renderDT({
    req(rv$loaded)
    dat <- rv$df
    dat$index <- seq_len(nrow(dat))
    ccol <- get_context_col()
    cols <- c("index", input$text_col, ccol, issue_col, uncertainty_col, policy_col, stance_col,
              issue2_col, uncertainty2_col, stance2_col,
              not_sentence_col, draft_col, annotator_col, selected_col, annotated_col)
    cols <- cols[cols %in% names(dat)]
    dat[, cols, drop = FALSE]
  }, options = list(pageLength = 10), selection = 'single', server = FALSE)
  
  # navigation: set selected_at only if empty
  observeEvent(input$next_btn, {
    req(rv$loaded)
    if (rv$pos < length(rv$order)) {
      rv$pos <- rv$pos + 1
      set_selected_time(rv$order[rv$pos])
    }
  })
  observeEvent(input$prev_btn, {
    req(rv$loaded)
    if (rv$pos > 1) {
      rv$pos <- rv$pos - 1
      set_selected_time(rv$order[rv$pos])
    }
  })
  observeEvent(input$table_rows_selected, {
    req(rv$loaded)
    sel <- input$table_rows_selected
    if (length(sel)) {
      rv$pos <- sel[1]
      set_selected_time(rv$order[rv$pos])
    }
  })
  
  # Toggle topic2 visibility
  observeEvent(input$toggle_topic2, {
    req(rv$loaded)
    rv$topic2_active <- !isTRUE(rv$topic2_active)
    if (rv$topic2_active) {
      show("topic2_div")
      updateActionButton(session, "toggle_topic2", label = "Remove second topic")
      showNotification("Second topic enabled for this session (toggle on).", type = "message")
    } else {
      hide("topic2_div")
      updateActionButton(session, "toggle_topic2", label = "Add second topic")
      # clear second-topic values for current row (so non-activated rows stay blank)
      idx <- rv$order[rv$pos]
      rv$df[[issue2_col]][idx] <- NA_character_
      rv$df[[uncertainty2_col]][idx] <- NA_real_
      rv$df[[stance2_col]][idx] <- NA_real_
      showNotification("Second topic disabled and cleared for current row.", type = "warning")
    }
  })
  
  # When user toggles "not a sentence", disable/enable other inputs (including second topic)
  observeEvent(input$is_sentence_choice, {
    req(rv$loaded)
    if (input$is_sentence_choice == "not a sentence") {
      disable("issue_choice"); disable("uncertainty"); disable("policy_choice"); disable("stance_score")
      # disable second-topic inputs if visible
      disable("issue2_choice"); disable("uncertainty2"); disable("stance2_score")
      showNotification("Other coding inputs disabled while 'not a sentence' is selected.", type = "warning")
    } else {
      enable("issue_choice"); enable("uncertainty"); enable("policy_choice"); enable("stance_score")
      # enable second-topic inputs only if topic2 is active
      if (isTRUE(rv$topic2_active)) {
        enable("issue2_choice"); enable("uncertainty2"); enable("stance2_score")
      }
      showNotification("Coding inputs enabled.", type = "message")
    }
  })
  
  # annotate: save all labels (final annotation) -> draft_flag = FALSE
  observeEvent(input$annotate, {
    req(rv$loaded)
    idx <- rv$order[rv$pos]
    is_not_sentence <- identical(input$is_sentence_choice, "not a sentence")
    rv$df[[not_sentence_col]][idx] <- if (is_not_sentence) "TRUE" else "FALSE"
    
    if (is_not_sentence) {
      # clear other coding fields
      rv$df[[issue_col]][idx] <- NA_character_
      rv$df[[policy_col]][idx] <- NA_character_
      rv$df[[stance_col]][idx] <- NA_real_
      rv$df[[uncertainty_col]][idx] <- NA_real_
      rv$df[[issue2_col]][idx] <- NA_character_
      rv$df[[uncertainty2_col]][idx] <- NA_real_
      rv$df[[stance2_col]][idx] <- NA_real_
    } else {
      # primary topic
      rv$df[[issue_col]][idx] <- input$issue_choice
      rv$df[[policy_col]][idx] <- input$policy_choice
      rv$df[[uncertainty_col]][idx] <- as.numeric(input$uncertainty)
      rv$df[[stance_col]][idx] <- as.numeric(input$stance_score)
      # second topic only if active
      if (isTRUE(rv$topic2_active)) {
        rv$df[[issue2_col]][idx] <- input$issue2_choice
        rv$df[[uncertainty2_col]][idx] <- as.numeric(input$uncertainty2)
        rv$df[[stance2_col]][idx] <- as.numeric(input$stance2_score)
      }
    }
    
    rv$df[[annotator_col]][idx] <- input$annotator
    rv$df[[annotated_col]][idx] <- as.character(Sys.time())
    rv$df[[draft_col]][idx] <- "FALSE"
    
    showNotification(sprintf("Recorded annotation for row %d", idx), type = "message")
    
    # advance to next row
    if (rv$pos < nrow(rv$df)) {
      rv$pos <- rv$pos + 1
      set_selected_time(rv$order[rv$pos])
      # Reset interface for next row
      updateRadioButtons(session, "is_sentence_choice", selected = "sentence")
      rv$topic2_active <- FALSE
      hide("topic2_div")
      updateActionButton(session, "toggle_topic2", label = "Add second topic")
    }
  })
  
  # save draft: write current choices but mark draft_flag = TRUE
  observeEvent(input$save_draft, {
    req(rv$loaded)
    idx <- rv$order[rv$pos]
    is_not_sentence <- identical(input$is_sentence_choice, "not a sentence")
    rv$df[[not_sentence_col]][idx] <- if (is_not_sentence) "TRUE" else "FALSE"
    
    if (!is_not_sentence) {
      rv$df[[issue_col]][idx] <- input$issue_choice
      rv$df[[policy_col]][idx] <- input$policy_choice
      rv$df[[uncertainty_col]][idx] <- as.numeric(input$uncertainty)
      rv$df[[stance_col]][idx] <- as.numeric(input$stance_score)
      if (isTRUE(rv$topic2_active)) {
        rv$df[[issue2_col]][idx] <- input$issue2_choice
        rv$df[[uncertainty2_col]][idx] <- as.numeric(input$uncertainty2)
        rv$df[[stance2_col]][idx] <- as.numeric(input$stance2_score)
      }
    }
    
    rv$df[[annotator_col]][idx] <- input$annotator
    rv$df[[annotated_col]][idx] <- as.character(Sys.time())
    rv$df[[draft_col]][idx] <- "TRUE"
    
    showNotification(sprintf("Saved draft for row %d", idx), type = "message")
    
    # Reset interface so second topic is hidden for next annotation
    rv$topic2_active <- FALSE
    hide("topic2_div")
    updateActionButton(session, "toggle_topic2", label = "Add second topic")
  })
  
  # clear all annotation-related fields for current item (including selected_at)
  observeEvent(input$clear_label, {
    req(rv$loaded)
    idx <- rv$order[rv$pos]
    rv$df[[issue_col]][idx] <- NA_character_
    rv$df[[policy_col]][idx] <- NA_character_
    rv$df[[annotator_col]][idx] <- NA_character_
    rv$df[[annotated_col]][idx] <- NA_character_
    rv$df[[uncertainty_col]][idx] <- NA_real_
    rv$df[[stance_col]][idx] <- NA_real_
    rv$df[[selected_col]][idx] <- NA_character_
    rv$df[[not_sentence_col]][idx] <- NA_character_
    rv$df[[draft_col]][idx] <- NA_character_
    rv$df[[issue2_col]][idx] <- NA_character_
    rv$df[[uncertainty2_col]][idx] <- NA_real_
    rv$df[[stance2_col]][idx] <- NA_real_
    showNotification(paste0("Cleared issue, policy, uncertainty, stance, second-topic, not_sentence, draft and timestamps for row ", idx), type = "message")
  })
  
  observeEvent(input$randomize, {
    req(rv$loaded)
    rv$order <- sample(rv$order)
    rv$pos <- 1
    set_selected_time(rv$order[rv$pos])
    showNotification("Order randomized.")
  })
  
  # manual save to server main file (final)
  ensure_save_dir <- function(full_path) {
    if (is.null(full_path) || full_path == "") return(NULL)
    dir <- dirname(full_path)
    dir_norm <- tryCatch(normalizePath(dir, winslash = "/", mustWork = FALSE),
                         error = function(e) NA_character_)
    if (is.na(dir_norm)) return(NULL)
    if (!dir.exists(dir_norm)) {
      ok <- tryCatch(dir.create(dir_norm, recursive = TRUE), error = function(e) FALSE)
      if (!ok) return(NULL)
    }
    dir_norm
  }
  
  observeEvent(input$save, {
    req(rv$loaded)
    target <- rv$save_file
    if (is.null(target) || target == "") {
      showNotification("Save path not set. Please specify a save directory and filename.", type = "error")
      return()
    }
    
    dir_ok <- ensure_save_dir(target)
    if (is.null(dir_ok)) {
      showNotification(sprintf("Cannot create or access directory for '%s'. Check the path and permissions.", target), type = "error")
      return()
    }
    
    tryCatch({
      write.csv(rv$df, target, row.names = FALSE, fileEncoding = "UTF-8")
      showNotification(sprintf("Annotations saved to: %s", normalizePath(target, winslash = "/", mustWork = FALSE)), type = "message")
    }, error = function(e) {
      showNotification(paste("Error saving annotations:", e$message), type = "error")
    })
  })
  
  # update save paths when inputs change
  observeEvent(list(input$save_dir_input, input$save_fname_input), {
    req(input$save_dir_input, input$save_fname_input)
    dir_try <- input$save_dir_input
    dir_norm <- tryCatch(normalizePath(dir_try, winslash = "/", mustWork = FALSE),
                         error = function(e) NA_character_)
    if (is.na(dir_norm)) {
      showNotification("Invalid directory path.", type = "error")
      return()
    }
    if (!dir.exists(dir_norm)) {
      ok <- tryCatch(dir.create(dir_norm, recursive = TRUE), error = function(e) FALSE)
      if (!ok) {
        showNotification(sprintf("Unable to create directory: %s", dir_norm), type = "error")
        return()
      } else {
        showNotification(sprintf("Created directory: %s", dir_norm), type = "message")
      }
    }
    fname_input <- trimws(input$save_fname_input)
    if (fname_input == "") fname_input <- "annotations_saved"
    ext <- tolower(tools::file_ext(fname_input))
    if (ext == "") {
      fname_with_ext <- paste0(fname_input, ".csv")
    } else {
      fname_with_ext <- fname_input
    }
    rv$save_file <- file.path(dir_norm, fname_with_ext)
    rv$tmp_save_file <- file.path(dir_norm, paste0(tools::file_path_sans_ext(fname_with_ext), "_tmp.csv"))
  })
  
  # autosave tmp every 30s
  autoSave <- reactiveTimer(30000)
  observe({
    autoSave()
    if (rv$loaded) {
      tryCatch({
        tmp <- rv$tmp_save_file
        if (is.null(tmp) || tmp == "") {
          tmp <- file.path(dirname(rv$save_file), paste0(tools::file_path_sans_ext(basename(rv$save_file)), "_tmp.csv"))
          rv$tmp_save_file <- tmp
        }
        write.csv(rv$df, tmp, row.names = FALSE, fileEncoding = "UTF-8")
        showNotification(sprintf("Temporary autosave written to %s (CSV)", basename(tmp)), type = "message")
      }, error = function(e) {
        message("Autosave error: ", e$message)
      })
    }
  })
  
  # download handler
  output$download <- downloadHandler(
    filename = function() paste0(input$save_fname_input, '_', Sys.Date(), ".csv"),
    content = function(file) { req(rv$loaded); write.csv(rv$df, file, row.names = FALSE, fileEncoding = "UTF-8") }
  )
  
  # save_dir display
  output$save_dir <- renderText({
    req(input$save_dir_input, input$save_fname_input)
    full_path <- file.path(input$save_dir_input, input$save_fname_input)
    dir <- dirname(normalizePath(full_path, winslash = "/", mustWork = FALSE))
    if (dir == ".") dir <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
    dir
  })
  
  # keyboard shortcuts: left/right for navigation (keeps earlier behavior)
  observe({
    runjs("
      document.onkeydown = function(e) {
        e = e || window.event;
        if (e.keyCode == 37) Shiny.onInputChange('key', 'left');
        if (e.keyCode == 39) Shiny.onInputChange('key', 'right');
        if (e.keyCode >=49 && e.keyCode <=51) {
          Shiny.onInputChange('key', 'num' + (e.keyCode-48));
        }
      }
    ")
  })
  
  observeEvent(input$key, {
    k <- input$key
    if (k == "left" && rv$loaded && rv$pos > 1) {
      rv$pos <- rv$pos - 1
      set_selected_time(rv$order[rv$pos])
    }
    if (k == "right" && rv$loaded && rv$pos < nrow(rv$df)) {
      rv$pos <- rv$pos + 1
      set_selected_time(rv$order[rv$pos])
    }
    if (startsWith(k, "num") && rv$loaded) {
      num <- as.numeric(sub("num", "", k))
      mapping <- issue_choices
      if (!is.na(num) && num >= 1 && num <= length(mapping)) {
        chosen <- mapping[num]
        updateSelectInput(session, "issue_choice", selected = chosen)
        isolate({
          idx <- rv$order[rv$pos]
          rv$df[[issue_col]][idx] <- chosen
          rv$df[[annotator_col]][idx] <- input$annotator
          rv$df[[annotated_col]][idx] <- as.character(Sys.time())
          if (!is.null(input$uncertainty)) rv$df[[uncertainty_col]][idx] <- as.numeric(input$uncertainty)
          if (!is.null(input$policy_choice)) rv$df[[policy_col]][idx] <- input$policy_choice
          if (!is.null(input$stance_score)) rv$df[[stance_col]][idx] <- as.numeric(input$stance_score)
          rv$df[[draft_col]][idx] <- "FALSE"
          rv$df[[not_sentence_col]][idx] <- "FALSE"
          # second-topic quick save only if active
          if (isTRUE(rv$topic2_active)) {
            if (!is.null(input$issue2_choice)) rv$df[[issue2_col]][idx] <- input$issue2_choice
            if (!is.null(input$uncertainty2)) rv$df[[uncertainty2_col]][idx] <- as.numeric(input$uncertainty2)
            if (!is.null(input$stance2_score)) rv$df[[stance2_col]][idx] <- as.numeric(input$stance2_score)
          } else {
            rv$df[[issue2_col]][idx] <- NA_character_
            rv$df[[uncertainty2_col]][idx] <- NA_real_
            rv$df[[stance2_col]][idx] <- NA_real_
          }
        })
        if (rv$pos < nrow(rv$df)) {
          rv$pos <- rv$pos + 1
          set_selected_time(rv$order[rv$pos])
        }
      }
    }
  })
}

# Run app ---------------------------------------------------------------------
shinyApp(ui, server)
