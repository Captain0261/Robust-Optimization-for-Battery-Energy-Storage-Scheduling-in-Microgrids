library(dplyr)
library(tidyr)
library(ggplot2)
library(cluster)
library(lubridate)

# read the pv and wind generation data
pv_data <- read.csv("ninja_pv_52.4949_-1.8518_corrected.csv", skip=3)
wind_data <- read.csv("ninja_wind_52.4949_-1.8518_corrected.csv", skip=3)

re <- pv_data %>% select(time, PV = electricity) %>%
  inner_join(wind_data %>% select(time, Wind = electricity), by = 'time')

re$time <- as.POSIXct(re$time, format="%Y-%m-%d %H:%M")
re$Date <- as.Date(re$time)
re$Hour <- format(re$time, "%H")

PV_wide <- re %>% select(Date, Hour, PV) %>%
  pivot_wider(names_from = Hour, values_from = PV, names_prefix = "PV_", values_fn = list(PV = mean))
PV_wide$PV_NA <- NULL
PV_wide <- PV_wide %>% mutate(PV_01 = ifelse(is.na(PV_01), (PV_00 + PV_02) / 2, PV_01))
PV_wide <- PV_wide %>% mutate(PV_00 = ifelse(is.na(PV_00), 0, PV_00))
PV_wide <- PV_wide %>% drop_na()

Wind_wide <- re %>% select(Date, Hour, Wind) %>%
  pivot_wider(names_from = Hour, values_from = Wind, names_prefix = "Wind_", values_fn = list(Wind = mean))
Wind_wide$Wind_NA <- NULL
Wind_wide <- Wind_wide %>% mutate(Wind_01 = ifelse(is.na(Wind_01), (Wind_00 + Wind_02) / 2, Wind_01))
Wind_wide <- Wind_wide %>% mutate(Wind_00 = ifelse(is.na(Wind_00), Wind_01, Wind_00))
Wind_wide <- Wind_wide %>% drop_na()

re_wide <- inner_join(PV_wide, Wind_wide, by = "Date")

cluster_data <- re_wide %>% select(-Date)
cluster_data <- scale(cluster_data)
cluster_data[is.nan(cluster_data)] <- 0

# divide the whole data into four clusters
set.seed(2025)
k <- 4
km <- kmeans(cluster_data, centers = k, nstart = 25)
re_wide$Cluster <- as.factor(km$cluster)

re <- re %>% inner_join(re_wide %>% select(Date, Cluster), by = "Date")

robust_parameters <- re %>% group_by(Cluster, Hour) %>% summarise(
    P_bar_PV = mean(350 * PV),
    P_bar_Wind = mean(75 * Wind),
    Delta_P_PV = 1.96 * sd(350 * PV),
    Delta_P_Wind = 1.96 * sd(75 * Wind),
    .groups = "drop"
  )

# draw the real PV generation
plot_data_PV <- robust_parameters %>%
  mutate(
    Hour = as.numeric(Hour),
    PV_upper = P_bar_PV + Delta_P_PV,
    PV_lower = pmax(0, P_bar_PV - Delta_P_PV)
  )
ggplot(plot_data_PV, aes(x = Hour)) +
  geom_ribbon(aes(ymin = PV_lower, ymax = PV_upper, fill = Cluster), alpha = 0.3) +
  geom_line(aes(y = P_bar_PV, color = Cluster), size = 1) +
  facet_wrap(~ Cluster, labeller = labeller(Cluster = function(x) paste0("Cluster ", x))) +
  labs(
    x = "Hour",
    y = "Generation (kW)"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# draw the real wind generation
plot_data_Wind <- robust_parameters %>%
  mutate(
    Hour = as.numeric(Hour),
    Wind_upper = P_bar_Wind + Delta_P_Wind,
    Wind_lower = pmax(0, P_bar_Wind - Delta_P_Wind)
  )
ggplot(plot_data_Wind, aes(x = Hour)) +
  geom_ribbon(aes(ymin = Wind_lower, ymax = Wind_upper, fill = Cluster), alpha = 0.3) +
  geom_line(aes(y = P_bar_Wind, color = Cluster),size = 1) +
  facet_wrap(~ Cluster, labeller = labeller(Cluster = function(x) paste0("Cluster ", x))) +
  labs(
    x = "Hour",
    y = "Generation (kW)"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

robust_parameters <- robust_parameters %>%
  pivot_wider(
    names_from = Cluster,
    values_from = c(P_bar_PV, P_bar_Wind, Delta_P_PV, Delta_P_Wind),
    names_glue = "{.value}_Cluster{Cluster}"
  ) %>%
  arrange(Hour)

# output the parameters will be used in robust model
# write.csv(robust_parameters, "Robust_Parameters.csv", row.names = FALSE)
# write.csv(re_wide %>% select(Date, Cluster), "Daily_Cluster.csv", row.names = FALSE)


# draw the uncertainty set of PV generation
ggplot(re, aes(x = as.numeric(Hour), y = 350 * PV, group = Date, color = Cluster)) +
  geom_line(alpha = 0.25) +
  facet_wrap(~ Cluster, labeller = labeller(Cluster = function(x) paste0("Cluster ", x))) +
  labs(
    x = "Hour",
    y = "Generation (kW)"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# draw the uncertainty set of wind generation
ggplot(re, aes(x = as.numeric(Hour), y = 75 * Wind, group = Date, color = Cluster)) +
  geom_line(alpha = 0.25) +
  facet_wrap(~ Cluster, labeller = labeller(Cluster = function(x) paste0("Cluster ", x))) +
  labs(
    x = "Hour",
    y = "Generation (kW)"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# draw the calander
re_wide <- re_wide %>%
  mutate(
    Month = month(Date, label = TRUE, abbr = TRUE, locale = "C"),
    Day = day(Date)
  )

ggplot(re_wide, aes(x = Day, y = Month, fill = Cluster)) +
  geom_tile(color = "black") +
  labs(
    x = "Day",
    y = "Month",
    fill = "Cluster"
  ) +
  scale_x_continuous(breaks = seq(1, 31, 5)) +
  theme_minimal() +
  theme(
    #panel.grid = element_blank(),
    axis.text.y = element_text(face = "bold")
  )


