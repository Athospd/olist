library(dplyr)
library(RSQLite)
library(tidyverse)
library(DBI)
library(purrr)
library(stringr)
library(readr)
library(glue)
library(httr)
library(rvest)

url <- "https://raw.githubusercontent.com/Athospd/work-at-olist-data/master/datasets/"

csvs <- c(
  "olist_customers_dataset.csv",
  "olist_geolocation_dataset.csv",
  "olist_order_items_dataset.csv",
  "olist_order_payments_dataset.csv",
  "olist_order_reviews_dataset.csv",
  "olist_orders_dataset.csv",
  "olist_products_dataset.csv",
  "olist_sellers_dataset.csv",
  "product_category_name_translation.csv"
)
# salva os csvs
walk(csvs, ~ {
  GET(paste0(url, .x), write_disk(paste0("inst/csv/", .x), overwrite = TRUE))
})

# monta mapa de cidade e estado
aff <- read_csv("inst/csv/olist_geolocation_dataset.csv")
aff2 <- aff %>% distinct(geolocation_zip_code_prefix, geolocation_city, geolocation_state)
aff <- aff %>% select(-geolocation_city, -geolocation_state)
write_csv(aff, "inst/csv/olist_geolocation_dataset.csv")
write_csv(aff2, "inst/csv/olist_zip_codes_cities_states.csv")

csvs <- c(csvs, "olist_zip_codes_cities_states.csv")
nomes <- str_remove(csvs, "\\.csv")


# salva em SQLite (.db)
engine = dbConnect(RSQLite::SQLite(), "inst/sqlite/olist.db")

walk2(csvs, nomes, ~{
  bd <- read_csv(paste0("inst/csv/", .x), guess_max = 100000)
  if(.y == "olist_order_reviews_dataset") {
    bd <- bd %>%
      mutate(across(review_comment_message:X13, ~replace_na(as.character(.), ""))) %>%
      unite(review_comment_message_and_timestamp, review_comment_message:X13, sep = "@") %>%
      mutate(review_comment_message_and_timestamp = str_remove(review_comment_message_and_timestamp, "@+$")) %>%
      separate(
        review_comment_message_and_timestamp,
        c("review_comment_message", "review_creation_date", "review_answer_timestamp"),
        sep = "@(?=[^@]+)",
        fill = "left",
        extra = "merge"
      ) %>%
      mutate(
        review_comment_message = na_if(review_comment_message, "")
      )
  }

  # CSV
  write_csv(bd, paste0("inst/csv/", .x))

  # SQLite
  copy_to(engine, bd, .y, overwrite = TRUE, temporary = FALSE)

  # R
  assign(.y, bd, envir = .GlobalEnv)
  eval(parse(text = glue("usethis::use_data({.y}, overwrite = TRUE)")))
})

db_list_tables(engine)

#
# dbConnect(RSQLite::SQLite(), system.file("sqlite/olist.db", package = "olist"))

dbDisconnect(engine)


