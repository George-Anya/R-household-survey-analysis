# ====================================================================
# Household survey analysis (synthetic Kobo-style data)
# Author:  George Anya
# Purpose: import, clean, summarize and visualize survey data in R.
# Note:    all data is synthetic and used for practice only.
# ====================================================================

# --- 0. Setup --------------------------------------------------------
# install.packages("tidyverse")   # run once, then leave commented out
library(tidyverse)

# Set the working directory to the project folder before running
# (RStudio: Session > Set Working Directory > Choose Directory).
dir.create("outputs", showWarnings = FALSE)   # folder for charts and tables


# --- 1. Import -------------------------------------------------------
# Treat blanks and common "missing" codes (including Kobo's -99) as NA.
raw <- read_csv("data/household_survey.csv",
                na = c("", "NA", "n/a", "-99"))
glimpse(raw)


# --- 2. Inspect the problems ----------------------------------------
raw |> count(State)                    # inconsistent spellings and spacing
sum(duplicated(raw$`_id`))             # duplicate submissions
raw |> filter(`Household Size` > 30)   # impossible household sizes


# --- 3. Rename columns -----------------------------------------------
survey <- raw |>
  rename(id = `_id`, date = `Submission Date`, state = State,
         gender = `Respondent Gender`, hh_size = `Household Size`,
         meals = `Meals Yesterday`, displaced = Displaced,
         income = `Monthly Income (NGN)`,
         rice_price = `Rice Price per kg (NGN)`,
         water = `Clean Water Access`)
class(survey$income)   # "numeric" or "character", depending on the export


# --- 4. Clean ----------------------------------------------------------
# Remove repeat submissions first.
dedup <- survey |> distinct(id, .keep_all = TRUE)
n_outliers <- sum(dedup$hh_size > 30, na.rm = TRUE)

clean <- dedup |>
  mutate(
    state     = str_to_title(str_squish(state)),
    gender    = str_to_title(str_squish(gender)),
    displaced = str_to_title(str_squish(displaced)),
    water     = str_to_title(str_squish(water)),
    # Convert income text such as "45,000" to a number, but only if the
    # column was read as text. If it is already numeric, leave it alone.
    income    = if (is.character(income)) parse_number(income) else income,
    # Household sizes above 30 are treated as data-entry errors.
    hh_size   = if_else(hh_size > 30, NA_real_, hh_size)
  )

# Cleaning log: a record of every change made to the data.
cleaning_log <- tibble(
  step  = c("Raw rows",
            "Duplicate submissions removed",
            "Household sizes above 30 set to missing",
            "Rows in clean dataset"),
  count = c(nrow(raw),
            nrow(raw) - nrow(dedup),
            n_outliers,
            nrow(clean))
)
cleaning_log
write_csv(cleaning_log, "outputs/cleaning_log.csv")

# Quick checks
clean |> count(state)        # should show exactly six states
summary(clean$income)        # check values look sensible
colSums(is.na(clean))        # missing values per column


# --- 5. Summarize by state -------------------------------------------
by_state <- clean |>
  group_by(state) |>
  summarise(
    n              = n(),
    pct_displaced  = mean(displaced == "Yes", na.rm = TRUE) * 100,
    pct_low_meals  = mean(meals < 2, na.rm = TRUE) * 100,
    median_income  = median(income, na.rm = TRUE),
    avg_rice_price = mean(rice_price, na.rm = TRUE)
  ) |>
  arrange(desc(n))
by_state
write_csv(by_state, "outputs/summary_by_state.csv")

water_by_state <- clean |>
  group_by(state) |>
  summarise(
    n               = n(),
    pct_clean_water = mean(water == "Yes", na.rm = TRUE) * 100
  ) |>
  arrange(desc(pct_clean_water))
water_by_state

meals_by_gender <- clean |>
  filter(!is.na(gender), !is.na(meals)) |>
  group_by(gender) |>
  summarise(
    n         = n(),
    avg_meals = mean(meals)
  )
meals_by_gender


# --- 6. Charts ---------------------------------------------------------
# 6.1 Households eating fewer than two meals, by state
p_meals_state <- ggplot(by_state,
                        aes(x = reorder(state, pct_low_meals), y = pct_low_meals)) +
  geom_col(fill = "steelblue") +
  geom_text(aes(label = round(pct_low_meals)), hjust = -0.2) +
  coord_flip() +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(title = "Households eating fewer than 2 meals yesterday",
       x = NULL, y = "% of households",
       caption = "Source: synthetic practice data") +
  theme_minimal()
p_meals_state
ggsave("outputs/meals_by_state.png", p_meals_state, width = 8, height = 5, dpi = 300)

# 6.2 Average rice price per kg by month
p_rice <- clean |>
  mutate(month = floor_date(date, "month")) |>
  group_by(state, month) |>
  summarise(avg_rice = mean(rice_price, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(month, avg_rice, colour = state)) +
  geom_line() + geom_point() +
  labs(title = "Average rice price per kg by month",
       x = NULL, y = "NGN", colour = "State",
       caption = "Source: synthetic practice data") +
  theme_minimal()
p_rice
ggsave("outputs/rice_price_by_month.png", p_rice, width = 8, height = 5, dpi = 300)

# 6.3 Monthly income by displacement status
p_income <- clean |>
  filter(!is.na(income), !is.na(displaced)) |>
  ggplot(aes(displaced, income)) +
  geom_boxplot(fill = "grey85") +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Monthly income by displacement status",
       x = "Displaced household", y = "NGN",
       caption = "Source: synthetic practice data") +
  theme_minimal()
p_income
ggsave("outputs/income_by_displacement.png", p_income, width = 6, height = 5, dpi = 300)

# 6.4 Clean water access by state
p_water <- ggplot(water_by_state,
                  aes(x = reorder(state, pct_clean_water), y = pct_clean_water)) +
  geom_col(fill = "steelblue") +
  geom_text(aes(label = round(pct_clean_water)), hjust = -0.2) +
  coord_flip() +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(title = "Households with clean water access by state",
       x = NULL, y = "% of households",
       caption = "Source: synthetic practice data. Excludes households with no answer.") +
  theme_minimal()
p_water
ggsave("outputs/clean_water_by_state.png", p_water, width = 8, height = 5, dpi = 300)

# 6.5 Average meals by respondent gender
p_meals_gender <- ggplot(meals_by_gender, aes(x = gender, y = avg_meals, fill = gender)) +
  geom_col(width = 0.5, show.legend = FALSE) +
  geom_text(aes(label = round(avg_meals, 2)), vjust = -0.5) +
  scale_y_continuous(limits = c(0, 3), expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Average meals eaten yesterday by respondent gender",
       x = NULL, y = "Average number of meals",
       caption = "Source: synthetic practice data") +
  theme_minimal()
p_meals_gender
ggsave("outputs/meals_by_gender.png", p_meals_gender, width = 6, height = 5, dpi = 300)


# --- 7. Checks on the findings -----------------------------------------
# Is the gender difference in meals larger than chance would explain?
# A large p-value means the gap could easily be random.
t.test(meals ~ gender, data = clean)

# Missing income by state (counts are small, so read differences cautiously)
missing_income_by_state <- clean |>
  group_by(state) |>
  summarise(
    total_rows     = n(),
    missing_income = sum(is.na(income)),
    pct_missing    = mean(is.na(income)) * 100
  ) |>
  arrange(desc(missing_income))
missing_income_by_state
write_csv(missing_income_by_state, "outputs/missing_income_by_state.csv")

# Non-response check: do households with and without income differ on
# other variables? Large differences suggest the missing values is not random.
nonresponse_check <- clean |>
  mutate(income_missing = is.na(income)) |>
  group_by(income_missing) |>
  summarise(
    n             = n(),
    pct_displaced = mean(displaced == "Yes", na.rm = TRUE) * 100,
    avg_hh        = mean(hh_size, na.rm = TRUE)
  )
nonresponse_check
write_csv(nonresponse_check, "outputs/nonresponse_check.csv")
