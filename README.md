# SnapCart Lite
**Cloud-OCR + LLM-Powered Receipt Intelligence and Spending Forecaster in R**

Snap a receipt photo: Google Cloud Vision reads it, Claude turns the messy text into structured JSON, and R models forecast your monthly spending and flag overspending, all inside a four-tab Shiny dashboard.

## Architecture

```
    Receipt image
         │
         ▼
    Google Cloud Vision API ──► Raw OCR text
                                      │
                                      ▼
                         Claude (Anthropic API) ──► Structured JSON
                                                          │
                                                          ▼
                                             ML models (LM / RF / GLM)
                                                          │
                                                          ▼
                                                   Shiny dashboard
```

## Project layout

```
snapcart-lite-r/
├── app.R                      # Shiny dashboard (4 tabs)
├── run_all.R                  # generate data -> EDA -> train models
├── install_packages.R         # one-off package installer
├── deploy.R                   # shinyapps.io deployment
├── R/
│   ├── 01_ocr_vision.R        # Google Cloud Vision OCR (+ mock)
│   ├── 02_parse_claude.R      # Claude via ellmer (+ MOCK + Gemini fallback)
│   ├── 03_generate_synthetic.R# writes data/historical_expenses.csv
│   ├── 04_train_models.R      # LM, ranger RF, logistic GLM
│   ├── 05_utils.R             # %||%, ensure_dirs(), receipt storage
│   └── 06_eda.R               # slide 3-12 outputs
├── data/                      # historical_expenses.csv, receipts.csv (git-ignored)
├── output/{figures,models,tables}/
├── docs/                      # PPT outline, Word report outline, costs, build plan
├── .Renviron.example  .gitignore  LICENSE  README.md
```

## Setup

1. **Install R (>= 4.1) and RStudio.** Open the folder as an RStudio Project so the working directory is the project root.
2. **Install packages:** `source("install_packages.R")`
3. **Google Cloud Vision key:** create a project at console.cloud.google.com, enable *Cloud Vision API*, then *APIs & Services → Credentials → Create API key*. Billing must be enabled, but the first 1,000 units/month are free.
4. **Anthropic key:** create one at console.anthropic.com (signup credit applies).
5. **(Optional) Gemini key:** aistudio.google.com, used as a free fallback.
6. **Populate `.Renviron`:** copy `.Renviron.example` to `.Renviron`, fill in the keys, then **restart R**. Never commit this file.

## How to run

```r
source("run_all.R")     # = R/03 generator + R/06 EDA + R/04 trainer
shiny::runApp()
```

Or step by step: `source("R/03_generate_synthetic.R")`, then `source("R/04_train_models.R")`, then `shiny::runApp()`.

The upload tab has two switches: **MOCK OCR** and **MOCK Claude**. With both ticked the whole pipeline runs offline with no keys.

## Run in VS Code (quick start)

1. Install R, VS Code, and the **R** extension (REditorSupport.r). Then in R: `install.packages("languageserver")`.
2. **File > Open Folder...** and select `snapcart-lite-r` (the folder containing `app.R`).
3. Copy `.Renviron.example` to `.Renviron` and add your keys (optional for the mock demo). Restart the R terminal afterwards.
4. In the VS Code terminal:
   ```bash
   Rscript install_packages.R
   Rscript run_all.R
   Rscript -e "shiny::runApp('.', launch.browser = TRUE)"
   ```
   Or use **Terminal > Run Task...** (tasks 1, 2, 3 are preconfigured in `.vscode/tasks.json`).
5. If VS Code cannot find R, set the R path in `.vscode/settings.json`.

Full walkthrough and troubleshooting: [docs/VSCODE_GUIDE.md](docs/VSCODE_GUIDE.md).

## Deployment to shinyapps.io

1. Create a free account at shinyapps.io and copy your token/secret.
2. `rsconnect::setAccountInfo(name = "<account>", token = "<token>", secret = "<secret>")`
3. Make sure `run_all.R` has been run, then `source("deploy.R")`.
4. Keys are forwarded with `envVars`, so they are not bundled in code.

Note: shinyapps.io storage is ephemeral, so `data/receipts.csv` resets when the app restarts. A cloud database is listed as future scope.

## Development-mock note

To preserve limited Anthropic credit, `parse_receipt_claude()` is replaced during development by `parse_receipt_claude_MOCK()`, which returns canned JSON. Both go through the same `parse_receipt_json()` validator, so the real path is exercised identically. Switch with `USE_MOCK_LLM=FALSE` in `.Renviron` or the checkbox in the app. If Anthropic fails and a Gemini key exists, `ellmer::chat_google_gemini()` is used automatically.

## Honest metrics

`amount` is generated with category multipliers, weekend/festival uplift and `rnorm(0, 0.4)` noise, so models do not fit perfectly. The label `overspendFlag` is derived from `amount` and is never used as a predictor.

GitHub: https://github.com/<your-username>/snapcart-lite-r
