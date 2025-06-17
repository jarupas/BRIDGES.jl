#---------- helper functions ----------#
@doc raw"""
    compute_crf(wacc, lifetime) -> Float64 or Array{Float64}

Computes the Capital Recovery Factor (CRF), used to annualize investment costs over the lifetime of an asset following the formula:

``CRF = \frac{wacc (1 + wacc)^{lifetime}}{(1 + wacc)^{lifetime} - 1}``

# Arguments
- `wacc`: The weighted average cost of capital (WACC), as a scalar or array. Expressed as a decimal (e.g., 0.05 for 5%).
- `lifetime`: The economic lifetime of the investment (in years), as a scalar or array matching the shape of `wacc`.

# Returns
- `crf`: The capital recovery factor, with the same shape as the input(s).
"""
function compute_crf(wacc, lifetime)
    crf = (wacc.*(1+wacc).^lifetime)./((1+wacc).^lifetime .- 1)
    return crf
end


"""
    compute_failure_probabilities(dict, param)

Calculates failure probabilities and cumulative failure fractions for appliances/transport using Poisson distribution.

# Arguments
- `dict`: Dictionary containing appliance/transport information
- `param`: Dictionary containing model parameters

# Returns
- Updates the `APP` dictionary with:
  - `failureProb`: Matrix storing failure probabilities for each appliance class in each year of its lifetime (up to 50 years).
  - `cumFailureProb`: 3D matrix storing cumulative failure fractions for each appliance type, in each investment year, 
  for each year of the investment period.
"""
function compute_failure_probabilities(dict::Dict{Symbol, Any}, param)
    # Initialize matrices
    failureProb = zeros(dict[:Units], 150)
    cumFailureProb = zeros(dict[:Units], param["T_inv"], param["T_inv"])

    # Read failure probabilities from an exogenous CSV file
    failureArchive = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/failureProb.csv", DataFrame)

    # Calculate failure probabilities for each appliance class in each year of its lifetime (1 to 50 years)
    for a = 1:dict[:Units]
        for i = 1:50
            # Using failure data from the CSV file
            failureProb[a, i] = failureArchive[Int(dict[:Lifetime][a]), i]
        end

        # Ensure the sum across each row equals 1 (i.e., no appliance lasts longer than 50 years)
        failureProb[a, 50] = 1 - sum(failureProb[a, 1:49])
    end

    # Compute the cumulative failure fraction for each appliance type, in each investment year
    for a = 1:dict[:Units]
        for v = 1:param["T_inv"]
            for t = 1:param["T_inv"]
                cumFailureProb[a,v,t] = round(
                    sum(failureProb[a,1:max(param["Years"][t]-param["Years"][v],1)]),digits = 4
                )
                if t == v
                    cumFailureProb[a,v,t] = 0.0
                end
            end
        end
    end
    dict[:failureProb] = failureProb
    dict[:cumFailureProb] = cumFailureProb
end

"""
    compute_historical_units(dict, param)

Computes historical units for appliances based on failure probabilities and historical growth rates.

# Arguments
- `dict`: Dictionary containing appliance/transport information
- `param`: Dictionary containing model parameters

# Returns
- Updates the `dict` dictionary with:
  - `unitsHistorical`: Matrix storing historical units for each appliance/transport type, in each investment year.
"""
function compute_historical_units(dict::Dict{Symbol, Any}, param)
    baseSales = zeros(dict[:Units])
    unitsHistorical = zeros(param["T_inv"], dict[:Units])
    for a = 1:dict[:Units]
        # Calculate base year sales
        total_failure_fraction = sum(max(1 - round(sum(dict[:failureProb][a, 1:k]), digits = 4), 0) / (1 + dict[:HistoricalGR][a])^k for k in 1:50)
        baseSales[a] = (dict[:ApplianceCount][a]) / total_failure_fraction

        # Calculate historical units
        for I = 1:param["T_inv"]
            year_difference = Int.(param["Years"][I] .- param["BaseYear"])
            unitsHistorical[I,a] = baseSales[a] * sum((1+dict[:HistoricalGR][a])^(-1*k) * (1 - round(sum(dict[:failureProb][a,1:k+year_difference]),digits = 4)) for k = 1:50)
        end
    end
    dict[:unitsHistorical] = unitsHistorical
end

"""
    apply_toggle!(df::DataFrame, toggle::Dict{String, Int}, column::String) -> DataFrame

Applies a toggle mask to a DataFrame by modifying values in a specified column based on PrimeMover values.

# Arguments
- `df`: The DataFrame to modify
- `toggle`: Dictionary mapping PrimeMover values to integers (1 to keep, 0 to disable)
- `column`: Name of the column to modify

# Returns
- Modified DataFrame with specified rows' column values set to 0
"""
function apply_toggle!(df::DataFrame, toggle::Dict{String, Int}, column::String)
    for (key, allowed) in toggle
        if allowed == 0
            df[df."PrimeMover" .== key, column] .= 0
        end
    end
    return df
end


"""
    scale_CAPEX!(df::DataFrame, techType::String, multiplier::Number) -> DataFrame

Scales capital expenditure (CAPEX) values for a specific technology type across years 2020 to 2050.

# Arguments
- `df`: DataFrame containing CAPEX data with Technology column and year columns
- `techType`: Name of the technology to filter (e.g., "Li-ion battery")
- `multiplier`: Value by which to scale the CAPEX entries

# Returns
- Modified DataFrame with selected values scaled in-place
"""
function scale_CAPEX!(df::DataFrame, techType::String, multiplier::Number)
    year_cols = findall(name -> name in string.(2020:2050), names(df))
    tech_idx = findall(==(techType), df[!, "Technology"])
    df[tech_idx, year_cols] .= df[tech_idx, year_cols] .* multiplier
    return df
end

"""
    get_cost_value(tech::AbstractString, lookup::DataFrame, scenarios::DataFrame, year::Int) -> Number

Fetches the cost value for a given technology and year from lookup tables.

# Arguments
- `tech`: Name of the technology or fuel to look up
- `lookup`: DataFrame containing cost values across years
- `scenarios`: DataFrame mapping technologies to cost scenario identifiers
- `year`: Numeric index representing the desired year

# Returns
- Cost value from the appropriate row and year column

# Throws
- Error if technology is not found or if no valid cost match exists
"""
function get_cost_value(tech::AbstractString, lookup::DataFrame, scenarios::DataFrame, year::Int)
    subset_idx = findall(==(tech), lookup.Technology)
    if isempty(subset_idx)
        error("Technology $(tech) not found in lookup.")
    end

    scen_idx = findall(==(tech), scenarios.Technology)
    if isempty(scen_idx)
        error("Technology $(tech) not found in CostScenarios.")
    end

    cost_scenario = scenarios.Cost[scen_idx[1]]
    scen_cost_idx = findall(==(cost_scenario), lookup.Cost)
    
    valid_idx = intersect(subset_idx, scen_cost_idx)
    if isempty(valid_idx)
        error("No cost match for $(tech) and scenario $(cost_scenario).")
    end
    return lookup[valid_idx[1], year]
end

"""
    add_cost_fields!(tech_dict::Dict, fields::Vector{Symbol}, T_inv)

Adds cost fields to a technology dictionary.

# Arguments
- `tech_dict`: Dictionary containing technology information
- `fields`: Vector of symbols representing the cost fields to add
- `T_inv`: Number of investment periods

# Returns
- Modified dictionary with added cost fields
"""
function add_cost_fields!(tech_dict::Dict, fields::Vector{Symbol}, T_inv)
    for f in fields
        tech_dict[f] = zeros(T_inv, tech_dict[:Units])
    end
end

"""
    compute_gas_system_costs(param::Dict) -> Tuple{Matrix{Float64}, Array{Float64, 3}, Vector{Float64}}

Computes annualized fixed costs and accumulated depreciation costs for a gas distribution system.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Tuple containing:
  - `BAU_costs`: Matrix of BAU system fixed costs [n_customers x T_inv]
  - `shutdown_costs`: 3D Array of shutdown depreciation costs [n_customers x T_inv x T_inv]
  - `discount_factors`: Vector of discount factors per investment period
"""
function compute_gas_system_costs(param::Dict)
    customers = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/CustomersOnDistSystem.csv", DataFrame)

    # Calculate revenue requirement and initial rate base
    RR_est = param["res_cost"] * customers.ResPop .+ param["com_cost"] * customers.ComPop
    RB_est = (1 .- param["shareFOM"]) .* RR_est ./ (param["equity"] + param["AvgDepreciation"])

    n_systems = size(customers, 1)
    T_inv = param["T_inv"]
    years = param["Years"]
    all_years = param["AllYears"]

    BAU_costs = zeros(n_systems, T_inv)
    shutdown_costs = zeros(n_systems, T_inv, T_inv)

    for i in 2:T_inv
        dep_horizon = years[i] - years[1]
        syd = dep_horizon * (dep_horizon + 1) / 2  # Sum-of-years-digits depreciation

        for j in 1:(T_inv - 1)
            if j < i
                cost = zeros(n_systems)
                nb = RB_est
                rem_years = years[i] - years[1]

                for y in 1:(years[j + 1] - years[j])
                    depreciation = rem_years / syd * RB_est
                    cost .+= depreciation .+ nb * param["debt"]
                    nb .-= depreciation
                    rem_years -= 1
                end
                shutdown_costs[:, i, j] = cost / (years[j + 1] - years[j])
            else
                shutdown_costs[:, i, j] .= 0.0
            end
        end

        # BAU cost calculation with reinvestment growth
        y_range = (all_years[i] - param["BaseYear"] + 1):(all_years[i + 1] - param["BaseYear"])
        BAU_costs[:, i] = sum(
            RR_est .* param["shareFOM"] .+
            (param["equity"] + param["AvgDepreciation"]) .* ((1 - param["AvgDepreciation"] + param["ReinvestmentRate"]) .^ y) .*
            ((1 - param["shareFOM"]) .* RR_est ./ (param["equity"] + param["AvgDepreciation"]))
            for y in y_range
        ) ./ length(y_range)
    end

    # First period special cases
    BAU_costs[:, 1] = RR_est
    shutdown_costs[:, 1, 1] = RB_est

    # Compute discounting factors for each investment period
    discount_factors = zeros(T_inv)
    for i in 1:T_inv
        if i < T_inv
            for j in 1:(years[i + 1] - years[i])
                t = years[i] - param["BaseYear"] + j - 1
                discount_factors[i] += 1 / (1 + param["societal_discounting"])^t
            end
        else
            for j in 1:(param["EndOfCostHorizon"] - years[i] - 1)
                t = years[i] - param["BaseYear"] + j - 1
                discount_factors[i] += 1 / (1 + param["societal_discounting"])^t
            end
        end
    end

    return BAU_costs, shutdown_costs, discount_factors
end


#---------- load data ----------#

"""
    load_generators(param, cons) -> Dict{Symbol, Any}

Loads and processes generator data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters
- `cons`: Dictionary containing physical constants

# Returns
- Dictionary containing generator data with computed fields:
  - Raw data from CSV
  - `MaxNewAnnual`: Maximum annual build rates
  - `MaxNewTotal`: Total maximum build rates
  - `Retirement`: Retirement years
  - `CRF`: Capital recovery factors
  - `EmissionsFactor`: Emissions factors
"""
function load_generators(param,cons)
    toggles = Dict(
        "Natural Gas CC-CCS" => param["techScenario_NGCC"],
        "Natural Gas CC" => param["techScenario_NGCC"],
        "Natural Gas CT" => param["techScenario_NGCC"],
        "OffshoreWind" => param["techScenario_OffshoreWind"],
        "Nuclear" => param["techScenario_Nuclear"]
    )
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/Generators.csv",DataFrame)
    df = apply_toggle!(df, toggles,"MaxNewAnnual")
    GEN = Dict{Symbol, Any}(pairs(eachcol(df)))
    GEN[:Units] = length(GEN[:NodeELEC])
    GEN[:EmissionsFactor] = GEN[:EmissionsFactor] ./ cons["KG_PER_TON"]
    GEN[:Retirement] = min.(GEN[:InstallYear]+GEN[:Lifetime],GEN[:ForcedRetirement])
    GEN[:ForcedRetirement][GEN[:PrimeMover] .== "Nuclear"] .= param["nuclear_RetirementYear"]
    GEN[:CRF] = compute_crf(param["WACC"],GEN[:EconomicLifetime])
    return GEN
end

"""
    load_appliances(param) -> Dict{Symbol, Any}

Loads and processes appliance data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `CRF`: Capital recovery factors
  - `failureProb`: Failure probabilities
  - `cumulativefailurefrac`: Cumulative failure fractions
"""
function load_appliances(param, cons)
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/EndUseAppliances.csv",DataFrame)
    APP = Dict{Symbol, Any}(pairs(eachcol(df)))
    APP[:Units] = length(APP[:NodeELEC])
    APP[:ApplianceCount] = APP[:ApplianceCount] / cons["UNIT_PER_THOUSAND"]
    APP[:CRF] = compute_crf(param["WACC_APPLIANCES"],APP[:Lifetime])
    APP[:SERVICES] = length(unique(APP[:ServiceName]))
    APP[:UNIQUE_SERVICES] = unique(APP[:ServiceName])

    # Growth rate
    APP[:ServicesGR] = zeros(APP[:SERVICES],1)      # %\year
    APP[:HistoricalGR] = zeros(APP[:Units],1)      # %\year  
    APP[:ForecastGR] = zeros(APP[:Units],1)        # %\year   
    
    # Distribution system
    APP[:DISTSYS_ELEC] = unique(APP[:DistELEC])
    APP[:DISTSYS_GAS]  = unique(APP[:DistGAS])
    APP[:DIST_ELEC] = length(APP[:DISTSYS_ELEC])
    APP[:DIST_GAS] = length(APP[:DISTSYS_GAS])

    # Failure probability
    compute_failure_probabilities(APP, param)

   # Units remaining
    compute_historical_units(APP, param)
    return APP
end

"""
    load_p2g(param) -> Dict{Symbol, Any}

Loads and processes power-to-gas (P2G) data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `MaxNewAnnual`: Maximum annual build rates
  - `MaxNewTotal`: Total maximum build rates
  - `Retirement`: Retirement years
  - `CRF`: Capital recovery factors
  - `MoleFracs`: Mole fractions of CH4 and H2 in the gas mixture
"""
function load_p2g(param)
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/PowerToGas.csv",DataFrame)
    P2G = Dict{Symbol, Any}(pairs(eachcol(df)))
    P2G[:Units] = length(P2G[:NodeELEC])
    P2G[:Retirement] = min.(P2G[:InstallYear]+P2G[:Lifetime],P2G[:ForcedRetirement])
    P2G[:CRF] = compute_crf(param["WACC"],P2G[:EconomicLifetime]) 
    P2G[:MoleFracs] = Matrix(hcat(P2G[:MoleFrac_CH4],P2G[:MoleFrac_H2]))
    return P2G
end

"""
    load_p2h(param) -> Dict{Symbol, Any}

Loads and processes power-to-heat (P2H) data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `MaxNewAnnual`: Maximum annual build rates
  - `MaxNewTotal`: Total maximum build rates
  - `Retirement`: Retirement years
  - `CRF`: Capital recovery factors
"""
function load_p2h(param)
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/PowerToHeat.csv",DataFrame)
    P2H = Dict{Symbol, Any}(pairs(eachcol(df)))
    P2H[:Units] = length(P2H[:NodeELEC])
    P2H[:Retirement] = min.(P2H[:InstallYear]+P2H[:Lifetime],P2H[:ForcedRetirement])
    P2H[:CRF] = compute_crf(param["WACC"],P2H[:EconomicLifetime]) 
    return P2H
end

"""
    load_storage_heat(param) -> Dict{Symbol, Any}

Loads and processes heat storage data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `MaxNewAnnual`: Maximum annual build rates
  - `MaxNewTotal`: Total maximum build rates
  - `Retirement`: Retirement years
  - `CRF`: Capital recovery factors
"""
function load_storage_heat(param)
    toggles = Dict(
        "Hydrogen-to-Heat" => param["H2Heating_allowed"]
    )
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/Storage_HEAT.csv",DataFrame)
    df = apply_toggle!(df, toggles,"MaxNewAnnual")
    STO_HEAT = Dict{Symbol, Any}(pairs(eachcol(df)))
    STO_HEAT[:Units] = length(STO_HEAT[:NodeELEC])
    STO_HEAT[:Retirement] = min.(STO_HEAT[:InstallYear]+STO_HEAT[:Lifetime],STO_HEAT[:ForcedRetirement])
    STO_HEAT[:CRF] = compute_crf(param["WACC"],STO_HEAT[:EconomicLifetime])
    return STO_HEAT
end

"""
    load_storage_elec(param) -> Dict{Symbol, Any}

Loads and processes electrical storage data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `MaxNewAnnual`: Maximum annual build rates
  - `MaxNewTotal`: Total maximum build rates
  - `Retirement`: Retirement years
  - `CRF`: Capital recovery factors
"""
function load_storage_elec(param)
    toggles = Dict(
        "Multi-day storage" => param["MDS_allowed"],
        "Pumped hydro storage" => param["PHS_allowed"],
        "Long-duration storage" => param["LDS_allowed"]
    )
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/Storage_ELEC.csv",DataFrame)    
    df = apply_toggle!(df, toggles,"MaxNewAnnual")
    STO_ELEC = Dict{Symbol, Any}(pairs(eachcol(df)))
    STO_ELEC[:Units] = length(STO_ELEC[:NodeELEC])
    STO_ELEC[:Retirement] = min.(STO_ELEC[:InstallYear]+STO_ELEC[:Lifetime],STO_ELEC[:ForcedRetirement])
    STO_ELEC[:CRF] = compute_crf(param["WACC"],STO_ELEC[:EconomicLifetime]) 
    return STO_ELEC
end

"""
    load_storage_gas(param) -> Dict{Symbol, Any}

Loads and processes gas storage data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `MaxNewAnnual`: Maximum annual build rates
  - `MaxNewTotal`: Total maximum build rates
  - `Retirement`: Retirement years
  - `CRF`: Capital recovery factors
  - `MoleFracs`: Mole fractions of CH4 and H2 in the gas mixture
"""
function load_storage_gas(param)
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/Storage_GAS.csv",DataFrame)
    STO_GAS = Dict{Symbol, Any}(pairs(eachcol(df)))
    STO_GAS[:Units] = length(STO_GAS[:NodeELEC])
    STO_GAS[:Retirement] = min.(STO_GAS[:InstallYear]+STO_GAS[:Lifetime],STO_GAS[:ForcedRetirement])
    STO_GAS[:CRF] = compute_crf(param["WACC"],STO_GAS[:EconomicLifetime])
    STO_GAS[:MoleFracs] = Matrix(hcat(STO_GAS[:MoleFrac_CH4],STO_GAS[:MoleFrac_H2]))
    return STO_GAS
end

"""
    load_transmission_electric(param) -> Dict{Symbol, Any}

Loads and processes electric transmission data from CSV files.

# Arguments
- `param`: Dictionary containing model parameters

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `MaxPower`: Maximum power ratings
  - `CAPEX`: Capital costs
  - `AMMORTIZED`: Amortized costs
"""
function load_transmission_electric(param)
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/ElecTransmission.csv",DataFrame)
    ELEC = Dict{Symbol, Any}(pairs(eachcol(df)))
    ELEC[:EDGES] = length(ELEC[:NodeIn])
    ELEC[:MaxPower] = ELEC[:MaxPower] .* param["transmission_multiplier"]
    ELEC[:RatedPower] = ELEC[:RatedPower] .* param["transmission_multiplier"]
    ELEC[:CAPEX] = param["ElecTransmissionCapitalCosts"].* ELEC[:Distance]
    ELEC[:Lifetime] = 50
    ELEC[:CRF] = compute_crf(param["WACC"],param["EconomicLifetime_ELECTrans"]) 
    ELEC[:AMMORTIZED] = ELEC[:CAPEX] .* ELEC[:RatedPower] .* (ELEC[:CRF]+param["ElecTransmissionOperatingCosts"])
    ELEC[:Nodes] = size(Matrix(CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/BaselineElectricDemands.csv",DataFrame)), 2)
    ELEC[:REGIONS] = String.(propertynames(CSV.File("$(param["current_dir"])/../../data/$(param["case_name"])/BaselineElectricDemands.csv")))
    return ELEC
end

"""
    load_transmission_gas(param, cons, STO_GAS, P2G) -> Dict{Symbol, Any}

Loads and processes gas transmission data using the Correa-Posada gas flow model.

# Arguments
- `param`: Dictionary containing model parameters
- `cons`: Dictionary containing physical constants
- `STO_GAS`: Dictionary containing gas storage information
- `P2G`: Dictionary containing power-to-gas information

# Returns
- Dictionary containing:
  - Raw data from CSV
  - `EDGES`: Number of pipeline segments.
  - `SLACK_PRESSURE`: Maximum pressure at the slack node
  - `MAXSLACK`: Maximum supply at the each node. Set to zero everywhere except for the slack node. Units: MW.
  - `K1`, `K2`: Coefficients from Correa-Posada gas flow model, with corrections on constants to bring pressures up to MPa.

# References
- Correa-Posada & Sanchez-Martin (2014): *"Integrated power and natural gas model for energy adequacy in short-term operation."*, IEEE Transactions on Power Systems.
"""
function load_transmission_gas(param, cons, STO_GAS, P2G)
    df = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/GasTransmission.csv",DataFrame)
    GAS = Dict{Symbol, Any}(pairs(eachcol(df)))
    GAS[:EDGES] = length(GAS[:NodeIn])
    GAS[:K1] = zeros(GAS[:EDGES])
    GAS[:K2] = zeros(GAS[:EDGES])
    GAS[:Nodes] = size(Matrix(CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/BaselineGasDemands.csv",DataFrame)), 2)
    GAS[:REGIONS] = String.(propertynames(CSV.File("$(param["current_dir"])/../../data/$(param["case_name"])/BaselineGasDemands.csv")))
    # Correa-Posada & Sanchez-Martin model
    for e = 1:GAS[:EDGES]
        GAS[:K1][e] = (cons["PI"]/4)*GAS[:Diameter][e]^2/cons["R"]/cons["M_CH4"]/cons["T_GAS"]/cons["COMPRESSIBILITY"]/cons["UNIVDENSITY_CH4"]*cons["M_CH4"] .*10^6 # MPa
        GAS[:K2][e] = (cons["PI"]/4)^2*GAS[:Diameter][e]^5/GAS[:FrictionFactor][e]/cons["R"]/cons["M_CH4"]/cons["T_N"]/cons["COMPRESSIBILITY"]/cons["UNIVDENSITY_CH4"]*cons["M_CH4"]^2 .*10^12 # MPa
    end

    # Pressure and supply at slack node
    slack_indices = findall(x -> x in param["SLACK_NODE"], GAS[:REGIONS])
    GAS[:SLACK_PRESSURE] = cons["PRESSURE_MAX"]
    GAS[:MAXSLACK] = zeros(1,GAS[:Nodes])
    GAS[:MAXSLACK][1, slack_indices] .= param["SLACK_GAS"]

    # Gas quality tracking
    GAS[:MM] = [cons["M_CH4"], cons["M_H2"]]*cons["MOL_PER_KMOL"]                     # kg/kmol
    GAS[:LHV] = [cons["LHV_CH4"], cons["LHV_H2"]]                                     # MJ/kg
    GAS[:FRAC_MAX] = [1.0, param["H2molfrac_max"]]                                    # kmol/kmol gas
    GAS[:FRAC_SLACK] = zeros(GAS[:Nodes],param["GAS_COMPONENTS"])
    GAS[:FRAC_SLACK][:,1] .= 1.0

    GAS[:MM_SLACK] = sum(GAS[:FRAC_SLACK].*transpose(GAS[:MM]), dims = 2)                           # [kg/kmol gas]
    STO_GAS[:MM_STORAGE] = sum(STO_GAS[:MoleFracs].*transpose(GAS[:MM]), dims = 2)                  # [kg/kmol gas]
    P2G[:MM_P2G] = sum(P2G[:MoleFracs].*transpose(GAS[:MM]), dims = 2)                              # [kg/kmol gas]

    GAS[:LHV_SLACK] = sum(GAS[:FRAC_SLACK].*transpose(GAS[:MM].*GAS[:LHV]), dims = 2)./GAS[:MM_SLACK]                   # [MJ/kg gas]
    STO_GAS[:LHV_STORAGE] = sum(STO_GAS[:MoleFracs].*transpose(GAS[:MM].*GAS[:LHV]), dims = 2)./STO_GAS[:MM_STORAGE]    # [MJ/kg gas]
    P2G[:LHV_P2G] = sum(P2G[:MoleFracs].*transpose(GAS[:MM].*GAS[:LHV]), dims = 2)./P2G[:MM_P2G]                        # [MJ/kg gas]
    return GAS
end

"""
    load_timeseries(param, GAS, ELEC) -> Dict{Symbol, Any}

Loads and processes time series data for electricity and gas demands.

# Arguments
- `param`: Dictionary containing model parameters
- `GAS`: Dictionary containing gas network information
- `ELEC`: Dictionary containing electricity network information

# Returns
- Dictionary containing:
  - `BaselineELEC`: Baseline electricity demands. Units = MWh.
  - `BaselineGAS`: Baseline gas demands. Units = MWh.
  - `ApplianceELEC`: Appliance profiles. Units = MWh.
  - `ApplianceGAS`: Appliance profiles. Units = MWh.
  - `VRE`: Variable renewable energy profiles. Units = [-].
"""
function load_timeseries(param, GAS, ELEC)
    fullPROF = Dict{Symbol, Any}()  # Instantiate an empty dictionary
    
    fullPROF[:BaselineELEC] = Matrix(CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/BaselineElectricDemands.csv",DataFrame))
    fullPROF[:BaselineGAS] = Matrix(CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/BaselineGasDemands.csv",DataFrame)) * param["baselinegasdemand_multiplier"]
    fullPROF[:ApplianceELEC] =  round.(Matrix(CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/ApplianceProfiles_ELEC.csv",DataFrame)),digits = 8)
    fullPROF[:ApplianceGAS] =  round.(Matrix(CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/ApplianceProfiles_GAS.csv",DataFrame)),digits = 8)

    fullPROF[:VRE] = max.(Matrix(CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/HourlyVRE.csv",DataFrame)),0)
    return fullPROF
end

"""
    add_costs!(param, GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT) -> Nothing

Adds cost information to various system components.

# Returns
- Adds to existing dictionaries:
  - `CAPEX`: Capital cost. Units = \$ /kW for generators and \$ /unit for appliances.
  - `FOM`: Fixed operating cost. Units = \$ /kW-yr.
  - `VOM`: Variable operating cost. Units = \$ /MWh.
  - `Fuel`: Fuel cost. Units = \$ /MMBtu.
"""
function add_costs!(param, GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT)
    CAPEXLookup = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/CAPEXLookup.csv",DataFrame)
    FOMLookup = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/FOMLookup.csv",DataFrame)
    VOMLookup = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/VOMLookup.csv",DataFrame)
    FuelCostLookup = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/FuelCostLookUp.csv",DataFrame)
    CostScenarios = CSV.read("$(param["current_dir"])/../../data/$(param["case_name"])/CostScenarios.csv",DataFrame)

    idx_yr = parse(Int,names(CAPEXLookup)[3]) - 1 

    add_cost_fields!(GEN, [:CAPEX, :FOM, :VOM, :FUEL], param["T_inv"])
    add_cost_fields!(P2G, [:CAPEX, :FOM, :VOM], param["T_inv"])
    add_cost_fields!(P2H, [:CAPEX, :FOM, :VOM], param["T_inv"])
    add_cost_fields!(STO_ELEC, [:CAPEX, :FOM], param["T_inv"])
    add_cost_fields!(STO_GAS, [:CAPEX, :FOM], param["T_inv"])             # Not included
    add_cost_fields!(STO_HEAT, [:CAPEX, :FOM], param["T_inv"])
    add_cost_fields!(APP, [:CAPEX, :FOM], param["T_inv"])

    for i = 1:length(param["cost_multiplier"]["tech"])
        techType = param["cost_multiplier"]["tech"][i]
        CAPEXLookup = scale_CAPEX!(CAPEXLookup, techType , param["cost_multiplier"]["mult"][i])
        println("$(techType) 2025 cost is: ", round(CAPEXLookup[CAPEXLookup[!, "Technology"] .== techType, "2025"][1]) , "\$ /kW")
    end

    for i = 1:param["T_inv"]
        year_col = Int(param["Years"][i] - idx_yr)
        for g = 1:GEN[:Units]
            tech = GEN[:PrimeMover][g]
            fuel = GEN[:Fuel][g]
            GEN[:CAPEX][i, g] = get_cost_value(tech, CAPEXLookup, CostScenarios, year_col)
            GEN[:FOM][i, g]   = get_cost_value(tech, FOMLookup, CostScenarios, year_col)
            GEN[:VOM][i, g]   = get_cost_value(tech, VOMLookup, CostScenarios, year_col)
            GEN[:FUEL][i, g] = get_cost_value(fuel, FuelCostLookup, CostScenarios, year_col)
        end
        for d = 1:P2G[:Units]
            tech = P2G[:PrimeMover][d]
            P2G[:CAPEX][i, d] = get_cost_value(tech, CAPEXLookup, CostScenarios, year_col)
            P2G[:FOM][i, d]   = get_cost_value(tech, FOMLookup, CostScenarios, year_col)
            P2G[:VOM][i, d]   = get_cost_value(tech, VOMLookup, CostScenarios, year_col)
        end
        for d = 1:P2H[:Units]
            tech = P2H[:PrimeMover][d]
            P2H[:CAPEX][i, d] = get_cost_value(tech, CAPEXLookup, CostScenarios, year_col)
            P2H[:FOM][i, d]   = get_cost_value(tech, FOMLookup, CostScenarios, year_col)
            P2H[:VOM][i, d]   = get_cost_value(tech, VOMLookup, CostScenarios, year_col)
        end
        for s = 1:STO_ELEC[:Units]
            tech = STO_ELEC[:PrimeMover][s]
            STO_ELEC[:CAPEX][i, s] = get_cost_value(tech, CAPEXLookup, CostScenarios, year_col)
            STO_ELEC[:FOM][i, s]   = get_cost_value(tech, FOMLookup, CostScenarios, year_col)
        end
        for s = 1:STO_HEAT[:Units]
            tech = STO_HEAT[:PrimeMover][s]
            STO_HEAT[:CAPEX][i, s] = get_cost_value(tech, CAPEXLookup, CostScenarios, year_col)
            STO_HEAT[:FOM][i, s]   = get_cost_value(tech, FOMLookup, CostScenarios, year_col)
        end
        for a = 1:APP[:Units]
            tech = APP[:ApplianceName][a]
            APP[:CAPEX][i, a] = get_cost_value(tech, CAPEXLookup, CostScenarios, year_col)
            APP[:FOM][i, a]   = get_cost_value(tech, FOMLookup, CostScenarios, year_col)
        end
    end

    param["discountfactor"] = zeros(param["T_inv"])
    for i = 1:param["T_inv"]
        if i < param["T_inv"]
            for j = 1:Int(param["Years"][i+1]-param["Years"][i])
                param["discountfactor"][i] = param["discountfactor"][i] + 1/((1+param["societal_discounting"])^(param["Years"][i]-param["BaseYear"]+j-1))
            end
        end
        if i == param["T_inv"]
            for j = 1:Int(param["EndOfCostHorizon"] - param["Years"][i] - 1)
                param["discountfactor"][i] = param["discountfactor"][i] + 1/((1+param["societal_discounting"])^(param["Years"][i]-param["BaseYear"]+j-1))
            end
        end
    end

    param["BAU_costs"], param["shutdown_costs"], param["discount_factors"] = compute_gas_system_costs(param)

end

"""
    create_mapping!(param, GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT, ELEC, GAS) -> Nothing

Creates mapping matrices between different system components.

# Returns
- Nothing (modifies input dictionaries in-place)
"""
function create_mapping!(param, GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT, ELEC, GAS)
    APP[:to_SERVICE] = zeros(APP[:Units],APP[:SERVICES])
    APP[:DIST_to_ELEC] = zeros(APP[:DIST_ELEC], APP[:Units])
    APP[:DIST_to_GAS] = zeros(APP[:DIST_GAS], APP[:Units])
    APP[:to_ELEC] = zeros(ELEC[:Nodes], APP[:Units])
    APP[:to_GAS] = zeros(GAS[:Nodes], APP[:Units])
    for a = 1:APP[:Units]
        APP[:to_SERVICE][a,findfirst(occursin.([(APP[:ServiceName][a])],APP[:UNIQUE_SERVICES]))] = 1
        APP[:DIST_to_ELEC][findfirst(occursin.([string(APP[:DistELEC][a])],string.(APP[:DISTSYS_ELEC]))),a] = 1
        APP[:DIST_to_GAS][findfirst(occursin.([string(APP[:DistGAS][a])],string.(APP[:DISTSYS_GAS]))),a] = 1
        APP[:to_ELEC][findfirst(occursin.([string(APP[:NodeELEC][a])],ELEC[:REGIONS])),a] = 1
        APP[:to_GAS][findfirst(occursin.([string(APP[:NodeGAS][a])],GAS[:REGIONS])),a] = 1
    end

    GEN[:to_ELEC] = zeros(ELEC[:Nodes], GEN[:Units])
    GEN[:to_GAS] = zeros(GAS[:Nodes], GEN[:Units])
    for g = 1:GEN[:Units]
        GEN[:to_ELEC][findfirst(occursin.([string(GEN[:NodeELEC][g])],ELEC[:REGIONS])),g] = 1
        GEN[:to_GAS][findfirst(occursin.([string(GEN[:NodeGAS][g])],GAS[:REGIONS])),g] = 1
    end

    P2G[:to_ELEC] = zeros(ELEC[:Nodes], P2G[:Units])
    P2G[:to_GAS] = zeros(GAS[:Nodes], P2G[:Units])
    for d = 1:P2G[:Units]
        P2G[:to_ELEC][findfirst(occursin.([string(P2G[:NodeELEC][d])],ELEC[:REGIONS])),d] = 1
        P2G[:to_GAS][findfirst(occursin.([string(P2G[:NodeGAS][d])],GAS[:REGIONS])),d] = 1
    end

    P2H[:to_ELEC] = zeros(ELEC[:Nodes], P2H[:Units])
    P2H[:to_GAS]  = zeros(GAS[:Nodes], P2H[:Units])
    for d = 1:P2H[:Units]
        P2H[:to_ELEC][findfirst(occursin.([string(P2H[:NodeELEC][d])],ELEC[:REGIONS])),d] = 1
        P2H[:to_GAS][findfirst(occursin.([string(P2H[:NodeGAS][d])],GAS[:REGIONS])),d] = 1
    end

    STO_ELEC[:to_ELEC] = zeros(ELEC[:Nodes], STO_ELEC[:Units])
    STO_ELEC[:to_GAS] = zeros(GAS[:Nodes], STO_ELEC[:Units])
    for s = 1:STO_ELEC[:Units]
        STO_ELEC[:to_ELEC][findfirst(occursin.([string(STO_ELEC[:NodeELEC][s])],ELEC[:REGIONS])),s] = 1
        STO_ELEC[:to_GAS][findfirst(occursin.([string(STO_ELEC[:NodeGAS][s])],GAS[:REGIONS])),s] = 1
    end

    STO_GAS[:to_ELEC] = zeros(ELEC[:Nodes], STO_GAS[:Units])
    STO_GAS[:to_GAS] = zeros(GAS[:Nodes], STO_GAS[:Units])
    for s = 1:STO_GAS[:Units]
        STO_GAS[:to_ELEC][findfirst(occursin.([string(STO_GAS[:NodeELEC][s])],ELEC[:REGIONS])),s] = 1
        STO_GAS[:to_GAS][findfirst(occursin.([string(STO_GAS[:NodeGAS][s])],GAS[:REGIONS])),s] = 1
    end

    STO_HEAT[:to_HEAT] = zeros(ELEC[:Nodes], STO_HEAT[:Units])
    for s = 1:STO_HEAT[:Units]
        STO_HEAT[:to_HEAT][findfirst(occursin.([string(STO_HEAT[:NodeGAS][s])],ELEC[:REGIONS])),s] = 1
    end
    
    ELEC[:A] = zeros(ELEC[:Nodes], ELEC[:EDGES])
    for e = 1:ELEC[:EDGES]
        ELEC[:A][findfirst(occursin.([string(ELEC[:NodeIn][e])],ELEC[:REGIONS])),e] = 1
        ELEC[:A][findfirst(occursin.([string(ELEC[:NodeOut][e])],ELEC[:REGIONS])),e] = -1
    end
    if ELEC[:Nodes] == 1
        ELEC[:A] = ELEC[:A]*0
    end
    GAS[:A] = zeros(GAS[:Nodes], GAS[:EDGES])
    for e = 1:GAS[:EDGES]
        GAS[:A][findfirst(occursin.([string(GAS[:NodeIn][e])],GAS[:REGIONS])),e] = 1
        GAS[:A][findfirst(occursin.([string(GAS[:NodeOut][e])],GAS[:REGIONS])),e] = -1
    end
    if GAS[:Nodes] == 1
        GAS[:A] = GAS[:A]*0
    end
end

"""
    compute_biomethane!(param, APP, P2G) -> Nothing

Computes biomethane limits based on initial core gas demands.

# Returns
- Nothing (modifies input dictionaries in-place)
"""
function compute_biomethane!(param, cons, APP, P2G, GAS, fullPROF)
    P2G[:maxBiomethane] = param["max_biomethane_share"]*sum(sum(sum(APP[:to_GAS][n,a]*fullPROF[:ApplianceGAS][:,a]*APP[:ApplianceCount][a]*cons["UNIT_PER_THOUSAND"] for a = 1:APP[:Units]) + fullPROF[:BaselineGAS][:,n] for n = 1:GAS[:Nodes]))*ones(param["T_inv"])

end


"""
    load_data(param,cons) -> Tuple{Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}, Dict{Symbol, Any}}

Main loading function that loads and processes all data required for the model.

# Arguments
- `param`: Dictionary containing model parameters
- `cons`: Dictionary containing physical constants

# Returns
- Tuple containing:
  - `GEN`: Dictionary containing generator information
  - `APP`: Dictionary containing appliance information
  - `P2G`: Dictionary containing power-to-gas information
  - `P2H`: Dictionary containing power-to-heat information
  - `STO_ELEC`: Dictionary containing electrical storage information
  - `STO_GAS`: Dictionary containing gas storage information
  - `STO_HEAT`: Dictionary containing heat storage information
  - `ELEC`: Dictionary containing electricity network information
  - `GAS`: Dictionary containing gas network information
  - `fullPROF`: Dictionary containing all profiles
"""
function load_data(param,cons)

    # Compute temporal parameters
    param["Periods_Per_Year"] = Int(cons["HOURS_PER_YEAR"]/param["HOURS_PER_PERIOD"])
    param["T_ops"] = param["N_Periods"]
    param["t_ops"] = param["HOURS_PER_PERIOD"]


    GEN = load_generators(param, cons)
    APP = load_appliances(param, cons)

    P2G = load_p2g(param)
    P2H = load_p2h(param)
    STO_HEAT = load_storage_heat(param)
    STO_ELEC = load_storage_elec(param)
    STO_GAS = load_storage_gas(param)

    ELEC = load_transmission_electric(param)
    GAS = load_transmission_gas(param, cons, STO_GAS, P2G)

    fullPROF = load_timeseries(param, GAS, ELEC)

    add_costs!(param, GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT)
    create_mapping!(param, GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT, ELEC, GAS)
    
    compute_biomethane!(param, cons, APP, P2G, GAS, fullPROF)

    return Dict(
        :GEN => GEN,:APP => APP,:P2G => P2G,:P2H => P2H,
        :STO_ELEC => STO_ELEC, :STO_GAS => STO_GAS, :STO_HEAT => STO_HEAT,
        :ELEC => ELEC, :GAS => GAS, :fullPROF => fullPROF
    )
end