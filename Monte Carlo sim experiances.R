library(ggplot2)
library(reshape2)

load_price <- read.csv("E:/桌面/MORSE/Dissertation/data/demand_and_price.csv")
re <- read.csv("E:/桌面/MORSE/Dissertation/data/robust_parameters.csv")

P_load <- load_price$Demand[1:24]
DA_price <- load_price$Price_DA[1:24]

N_sim <- 1000
set.seed(5042)

xi_matrix <- matrix(rnorm(n = N_sim * 24, mean = 0, sd = 0.33), nrow = N_sim, ncol = 24)
xi_matrix <- pmax(pmin(xi_matrix, 1), -1)

gamma_settings <- c(3, 3, 5, 5)

all_costs_list <- list()
mean_lines_list <- list()

for (c in 1:4) {
  gamma_val <- gamma_settings[c]
  
  path_ro <- sprintf("E:/桌面/MORSE/Dissertation/data/Cluster_%d/Final_Result_Cluster%d_Gamma_%d.csv", c, c, gamma_val)
  path_det <- sprintf("E:/桌面/MORSE/Dissertation/data/Cluster_%d/Final_Result_Cluster%d_Gamma_0.csv", c, c)
  
  ro <- read.csv(path_ro)
  det <- read.csv(path_det)
  
  PV_bar <- re[[paste0("P_bar_PV_Cluster", c)]]
  PV_Delta <- re[[paste0("Delta_P_PV_Cluster", c)]]
  Wind_bar <- re[[paste0("P_bar_Wind_Cluster", c)]]
  Wind_Delta <- re[[paste0("Delta_P_Wind_Cluster", c)]]
  
  ro_DA_cost <- sum(ro$P_DA * DA_price)
  det_DA_cost <- sum(det$P_DA * DA_price)
  
  ro_total_costs <- numeric(N_sim)
  det_total_costs <- numeric(N_sim)
  
  for (i in 1:N_sim) {
    xi <- xi_matrix[i, ]
    PV <- PV_bar - xi * PV_Delta
    Wind <- Wind_bar - xi * Wind_Delta
    P_re <- ifelse(PV + Wind > 0, PV + Wind, 0)
    
    ro_imbalance <- P_load + (ro$P_char - ro$P_dis) - P_re - ro$P_DA
    det_imbalance <- P_load + (det$P_char - det$P_dis) - P_re - det$P_DA
    
    ro_RT_cost_sim <- sum(ifelse(ro_imbalance > 0, ro_imbalance * (xi + 1.5) * DA_price, ro_imbalance * 0.7 * DA_price))
    det_RT_cost_sim <- sum(ifelse(det_imbalance > 0, det_imbalance * (xi + 1.5) * DA_price, det_imbalance * 0.7 * DA_price))
    
    ro_total_costs[i] <- ro_DA_cost + ro_RT_cost_sim
    det_total_costs[i] <- det_DA_cost + det_RT_cost_sim
  }
  
  cost_df <- data.frame(
    Scenario = 1:N_sim,
    Robust_Cost = ro_total_costs,
    Deterministic_Cost = det_total_costs
  )
  cost_melt <- melt(cost_df, id.vars = "Scenario", variable.name = "Model", value.name = "Total_Cost")
  
  cost_melt$Cluster <- sprintf("Cluster %d (Gamma = %d)", c, gamma_val)
  all_costs_list[[c]] <- cost_melt
  
  mean_lines_list[[c]] <- data.frame(
    Cluster = sprintf("Cluster %d (Gamma = %d)", c, gamma_val),
    Model = c("Robust_Cost", "Deterministic_Cost"),
    Mean_Cost = c(mean(ro_total_costs), mean(det_total_costs))
  )
}

final_cost_df <- do.call(rbind, all_costs_list)
final_mean_df <- do.call(rbind, mean_lines_list)

combined_density_plot <- ggplot(final_cost_df, aes(x = Total_Cost, fill = Model)) +
  geom_density(alpha = 0.5) +
  facet_wrap(~ Cluster, scales = "free_x", ncol = 2) +
  geom_vline(data = final_mean_df, aes(xintercept = Mean_Cost, color = Model), 
             linetype = "dashed", linewidth = 0.7) +
  scale_fill_manual(values = c("Robust_Cost" = "darkgreen", "Deterministic_Cost" = "red"),
                    labels = c("Robust", "Deterministic")) +
  scale_color_manual(values = c("Robust_Cost" = "darkgreen", "Deterministic_Cost" = "red"), guide = "none") +
  labs(x = "Total Cost",
       y = "Density",
       fill = "Model") +
  theme_minimal() +
  theme(legend.position = "bottom",
        strip.text = element_text(face = "bold")) # Cluster _ (Gamma = _)

print(combined_density_plot)
