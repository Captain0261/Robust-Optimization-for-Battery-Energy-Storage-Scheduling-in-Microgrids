# Robust-Optimization-for-Battery-Energy-Storage-Scheduling-in-Microgrids
Data-driven two-stage robust optimization model for microgrid battery scheduling using Julia (JuMP) and Gurobi, solved via the Big-M method and C&amp;CG algorithm.

## Data-Driven Scenario Generation
To accurately capture the real-world volatility of renewable energy, this project relies on empirical meteorological data rather than subjective assumptions.
* **Data Source:** Hourly photovoltaic (PV) and wind power generation data for Birmingham (2025) was sourced from [Renewables.ninja](https://www.renewables.ninja/).
* **K-Means Clustering:** Instead of relying on simple annual averages, the raw time-series data was partitioned into **four distinct meteorological clusters** using the K-means algorithm.
* **Uncertainty Sets:** For each cluster, the mathematical centroid serves as the nominal forecast baseline ($\bar{P}_t$), and the 95% confidence interval defines the maximum deviation bound ($\Delta P_t$) for the robust optimization model.
