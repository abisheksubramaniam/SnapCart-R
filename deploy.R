# Deploy to shinyapps.io (free tier). Run AFTER run_all.R so data/ and output/
# exist and get bundled.
#  1. rsconnect::setAccountInfo(name = "<account>", token = "<token>", secret = "<secret>")
#  2. source("deploy.R")
# envVars forwards your keys from .Renviron to the server (they are NOT bundled
# in the code and never touch GitHub).
rsconnect::deployApp(
  appDir     = ".",
  appName    = "snapcart-lite",
  appFiles   = c("app.R", "R", "data/historical_expenses.csv", "output"),
  envVars    = c("GOOGLE_VISION_API_KEY", "ANTHROPIC_API_KEY",
                 "ANTHROPIC_MODEL", "GOOGLE_API_KEY", "USE_MOCK_LLM"),
  forceUpdate = TRUE
)
