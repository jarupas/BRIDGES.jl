"""
    normalize_series(series) -> Vector{Float64}

Normalize a vector to the range [0, 1] using min-max normalization.

# Arguments
- `series`: Input vector to be normalized

# Returns
- Normalized vector with values between 0 and 1
"""
function normalize_series(series)
    return (series .- minimum(series)) ./ (maximum(series) - minimum(series))
end


"""
    build_profile(param, fullPROF, ELEC, GAS, APP) -> Matrix{Float64}

Build normalized profiles for electricity demand, gas demand, VRE, and natural gas 
prices for clustering analysis. If `variableNatGasPrice` is `true`, the natural gas 
price profile is read from `NGElectricPowerPrice.csv` and repeated 
for each period. Otherwise, the natural gas price is set to `off_price` for all periods.

# Arguments
- `param`: Dictionary containing model parameters
- `fullPROF`: Dictionary containing 8760 profiles for various components
- `ELEC`: Dictionary containing electricity network information
- `GAS`: Dictionary containing gas network information
- `APP`: Dictionary containing appliance information

# Returns
- Matrix containing normalized profiles for clustering, (size: (`HOURS_PER_PERIOD` x features), `Periods_Per_Year`)
"""
function build_profile(param, cons, fullPROF, ELEC, GAS, APP)
    elec_demand = copy(fullPROF[:BaselineELEC])
    for n in 1:ELEC[:Nodes]
        appliance_load = sum(APP[:to_ELEC][n, a] * fullPROF[:ApplianceELEC][:, a] * APP[:ApplianceCount][a] * cons["UNIT_PER_THOUSAND"] for a in 1:APP[:Units])
        elec_demand[:, n] .+= appliance_load
    end
    elec_profile = sum(elec_demand, dims=2)
    elec_profile = normalize_series(elec_profile)
    elec_profile = reshape(elec_profile, (param["HOURS_PER_PERIOD"], param["Periods_Per_Year"]))

    gas_demand = copy(fullPROF[:BaselineGAS])
    for n in 1:GAS[:Nodes]
        appliance_load = sum(APP[:to_GAS][n, a] * fullPROF[:ApplianceGAS][:, a] * APP[:ApplianceCount][a] * cons["UNIT_PER_THOUSAND"] for a in 1:APP[:Units])
        gas_demand[:, n] .+= appliance_load
    end
    gas_profile = sum(gas_demand, dims=2)
    gas_profile = normalize_series(gas_profile)
    gas_profile = reshape(gas_profile, (param["HOURS_PER_PERIOD"], param["Periods_Per_Year"]))

    unique_profiles = unique(fullPROF[:VRE], dims=2)
    num_profiles = size(unique_profiles, 2)
    VRE = reshape(unique_profiles, (param["HOURS_PER_PERIOD"], param["Periods_Per_Year"], num_profiles))
    
    ng_price_profile = Float64[]
    if param["variableNatGasPrice"]["toggle"]
        daily_price = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/NGElectricPowerPrice.csv", DataFrame)
        ng_price_profile = repeat(round.(daily_price.Cost, digits=4), inner=24)
    else
        daily_price = fill(param["variableNatGasPrice"]["off_price"], Periods_Per_Year)
        ng_price_profile = repeat(daily_price, inner=param["HOURS_PER_PERIOD"])
    end
    fullPROF[:GasPrice] = ng_price_profile
    ng_price_profile = normalize_series(ng_price_profile)
    ng_price_profile = reshape(ng_price_profile, (param["HOURS_PER_PERIOD"], param["Periods_Per_Year"]))

    cluster_data = vcat(elec_profile, gas_profile)
    cluster_data = vcat(cluster_data, (VRE[:, :, x] for x in 1:num_profiles)...)
    cluster_data = vcat(cluster_data,ng_price_profile)
    return cluster_data
end

"""
    perform_cluster(param, cluster_data) -> Dict{Symbol, Any}

Perform clustering on the profile data using the specified clustering method, 
ward, kmeans or average for unspecified.

# Arguments
- `param`: Dictionary containing model parameters including clustering settings
- `cluster_data`: Matrix containing normalized profiles to be clustered

# Returns
- Dictionary containing:
  - `medoids`: Representative days for each cluster (size: `T_inv` x `T_ops`)
  - `weights`: Weights for each cluster (size: `T_inv` x `T_ops`)
  - `repdays`: Representative days mapping (size: `T_inv` x `Periods_Per_Year`)
  - `assignments`: Original cluster assignments (size: `Periods_Per_Year`)
"""
function perform_cluster(param, cluster_data)
    T_inv = param["T_inv"]
    T_ops = param["T_ops"]
    Periods_Per_Year = param["Periods_Per_Year"]

    medoids = zeros(Int, T_ops)
    repdays = zeros(Float64, Periods_Per_Year)
    weights = zeros(Float64, T_ops)

    # Compute distance matrix once
    D = Distances.pairwise(Euclidean(), cluster_data, dims = 2)

    # Choose clustering method
    if param["clustering_case"] == "ward"
        H = hclust(D, linkage = :ward)
        a = cutree(H, k = T_ops)
    elseif param["clustering_case"] == "kmeans"
        km = kmeans(cluster_data, T_ops)
        a = assignments(km)
    else
        H = hclust(D, linkage = :average)
        a = cutree(H, k = T_ops)
    end

    # Assign representative days
    for c = 1:(T_ops)
        idxs = findall(==(c), a)
        sub = cluster_data[:,idxs]
        
        # Use precomputed pairwise distances among sub-cluster
        sub_dists = Distances.pairwise(Euclidean(), sub, dims = 2)
        # Sum of distances to all other points
        total_dists = sum(sub_dists, dims = 2)
        # Find medoid (minimum total distance)
        medoid_idx = argmin(total_dists)[1]

        # Map back to original index
        medoids[c] = idxs[medoid_idx]
        weights[c] = length(idxs) / Periods_Per_Year

    end
    # Repeat medoids and weights across T_inv
    medoids = repeat(medoids', T_inv, 1)
    weights = repeat(weights', T_inv, 1)
    repdays = repeat(reshape(a, 1, :), T_inv, 1)

    CLUSTER = Dict(
        :medoids => medoids,
        :weights => weights,
        :repdays => repdays,
        :assignments => a
    )
    return CLUSTER
end

"""
    select_clustered_profile(param, CLUSTER, fullPROF, ELEC, GAS, APP, GEN) -> Dict{Symbol, Any}

Select and process profiles based on clustering results, applying growth factors and 
organizing data into appropriate dimensions.

# Returns
- Dictionary containing clustered profiles for:
  - `BaselineELEC`: Baseline electricity demands
  - `BaselineHEAT`: Baseline heat demands
  - `ApplianceELEC`: Appliance profiles
  - `ApplianceGAS`: Appliance profiles
  - `VRE`: Variable renewable energy profiles
  - `GasPrice`: Natural gas prices
"""
function select_clustered_profile(param, cons, CLUSTER, fullPROF, ELEC, GAS, APP, GEN)
    T_inv = param["T_inv"]
    T_ops = param["T_ops"]
    t_ops = param["t_ops"]

    PROF = Dict{Symbol, Any}()
    PROF[:BaselineELEC] = zeros(T_inv, T_ops, t_ops, ELEC[:Nodes])
    PROF[:BaselineHEAT] = zeros(T_inv, T_ops, t_ops, GAS[:Nodes])
    PROF[:VRE] = zeros(T_ops, t_ops, GEN[:Units])
    PROF[:ApplianceELEC] = zeros(T_ops, t_ops, APP[:Units])
    PROF[:ApplianceGAS] = zeros(T_ops, t_ops, APP[:Units])
    PROF[:GasPrice] = zeros(T_inv, T_ops)

    for t in 1:T_inv
        growth_factor = (1 + param["LoadGrowthRate"]) ^ (param["Years"][t] - param["BaseYear"])
        for i in 1:T_ops
            start_hour = Int((CLUSTER[:medoids][1,i]-1)*param["HOURS_PER_PERIOD"]+1)
            end_hour = start_hour + param["HOURS_PER_PERIOD"]-1
            hour_range = start_hour:end_hour

            PROF[:BaselineELEC][t, i, :, :] .= growth_factor .* fullPROF[:BaselineELEC][hour_range, :]
            PROF[:BaselineHEAT][t, i, :, :] .= growth_factor .* fullPROF[:BaselineGAS][hour_range, :]

            PROF[:VRE][i, :, :] .= fullPROF[:VRE][hour_range, :]
            PROF[:ApplianceELEC][i, :, :] .= round.(fullPROF[:ApplianceELEC][hour_range, :], digits=8)
            PROF[:ApplianceGAS][i, :, :]  .= round.(fullPROF[:ApplianceGAS][hour_range, :], digits=8)

            PROF[:GasPrice][t, i] = fullPROF[:GasPrice][start_hour] / cons["MWh_PER_MMBTU"]
        end
    end
    PROF[:fullBaselineELEC] = fullPROF[:BaselineELEC]
    PROF[:fullApplianceELEC] = fullPROF[:ApplianceELEC]
    return PROF
end

"""
    cluster!(param, cons, data) -> Tuple{Dict{Symbol, Any}, Dict{Symbol, Any}}

Main clustering function that orchestrates the entire clustering process.

# Arguments
- `param`: Dictionary containing model parameters
- `fullPROF`: Dictionary containing full profiles
- `ELEC`: Dictionary containing electricity network information
- `GAS`: Dictionary containing gas network information
- `APP`: Dictionary containing appliance information
- `GEN`: Dictionary containing generator information

# Returns
- Tuple containing:
  - `CLUSTER`: Dictionary with clustering results
  - `PROF`: Dictionary with processed profiles
"""
function cluster!(param, cons, data)
    
    cluster_data = build_profile(param, cons, data[:fullPROF], data[:ELEC], data[:GAS], data[:APP])
    data[:CLUSTER] = perform_cluster(param, cluster_data)
    data[:PROF] = select_clustered_profile(param, cons, data[:CLUSTER], data[:fullPROF], data[:ELEC], data[:GAS], data[:APP], data[:GEN])

    return nothing 
end