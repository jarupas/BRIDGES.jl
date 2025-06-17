using JuMP

function get_results(m::Model, param, cons, data)

    results = Dict(
        :capex_GEN => JuMP.value.(m[:costs_GENcapital]),
        :opex_GEN => JuMP.value.(m[:costs_GENoperating]),
        :capex_STO_ELEC => JuMP.value.(m[:costs_ELECSTORAGEcapital]),
        :opex_STO_ELEC => JuMP.value.(m[:costs_ELECSTORAGEoperating]),
        :cost_STO_GAS => JuMP.value.(m[:costs_gasStorage]),
        :capex_STO_GAS => JuMP.value.(m[:costs_GASSTORAGEcapital]),
        :opex_STO_GAS => JuMP.value.(m[:costs_GASSTORAGEoperating]),
        :capex_STO_HEAT => JuMP.value.(m[:costs_HEATSTORAGEcapital]),
        :opex_STO_HEAT => JuMP.value.(m[:costs_HEATSTORAGEoperating]),
        :capex_P2G => JuMP.value.(m[:costs_P2Gcapital]),
        :opex_P2G => JuMP.value.(m[:costs_P2Goperating]),
        :capex_P2H => JuMP.value.(m[:costs_P2Hcapital]),
        :opex_P2H => JuMP.value.(m[:costs_P2Hoperating]),
        :cost_APP => JuMP.value.(m[:costs_appliances]),
        :cost_APP_DIST => JuMP.value.(m[:costs_distribution]),
        :cost_GAS => JuMP.value.(m[:gasdistsyst_Cost]),
        :cost_ELEC => JuMP.value.(m[:costs_transmission]),
        :cost_CO2 => JuMP.value.(m[:costs_CO2offsets]),
        :cost_NG => JuMP.value.(m[:costs_NGimports]),
        :built_GEN => JuMP.value.(m[:unitsbuilt_GEN]),
        :retired_GEN => JuMP.value.(m[:unitsretired_GEN]),
        :built_P2G => JuMP.value.(m[:unitsbuilt_P2G]),
        :retired_P2G => JuMP.value.(m[:unitsretired_P2G]),
        :built_P2H => JuMP.value.(m[:unitsbuilt_P2H]),
        :retired_P2H => JuMP.value.(m[:unitsretired_P2H]),
        :built_STO_ELEC => JuMP.value.(m[:unitsbuilt_STO_ELEC]),
        :retired_STO_ELEC => JuMP.value.(m[:unitsretired_STO_ELEC]),
        :built_STO_HEAT => JuMP.value.(m[:unitsbuilt_STO_HEAT]),
        :retired_STO_HEAT => JuMP.value.(m[:unitsretired_STO_HEAT]),
        :built_STO_GAS => JuMP.value.(m[:unitsbuilt_STO_GAS]),
        :retired_STO_GAS => JuMP.value.(m[:unitsretired_STO_GAS]),
        :built_APPS => JuMP.value.(m[:unitsbuilt_APPS]),
        :remaining_APPS => JuMP.value.(m[:unitsremaining_APPS]),
        :retired_APPS => JuMP.value.(m[:unitsretired_APPS]),
        :generation => JuMP.value.(m[:generation]),
        :commit_GEN => JuMP.value.(m[:commit_GEN]),
        :startup_GEN => JuMP.value.(m[:startup_GEN]),
        :shutdown_GEN => JuMP.value.(m[:shutdown_GEN]),
        :P2G_dispatch => JuMP.value.(m[:P2G_dispatch]),
        :commit_P2G => JuMP.value.(m[:commit_P2G]),
        :startup_P2G => JuMP.value.(m[:startup_P2G]),
        :shutdown_P2G => JuMP.value.(m[:shutdown_P2G]),
        :P2H_dispatch => JuMP.value.(m[:P2H_dispatch]),
        :commit_P2H => JuMP.value.(m[:commit_P2H]),
        :startup_P2H => JuMP.value.(m[:startup_P2H]),
        :shutdown_P2H => JuMP.value.(m[:shutdown_P2H]),
        :curtailmentRE => JuMP.value.(m[:curtailmentRE]),
        :storedEnergy_ELEC => JuMP.value.(m[:storedEnergy_ELEC]),
        :charging_ELEC => JuMP.value.(m[:charging_ELEC]),
        :discharging_ELEC => JuMP.value.(m[:discharging_ELEC]),
        :storedEnergy_GAS => JuMP.value.(m[:storedEnergy_GAS]),
        :charging_GAS => JuMP.value.(m[:charging_GAS]),
        :discharging_GAS => JuMP.value.(m[:discharging_GAS]),
        :storedEnergy_HEAT => JuMP.value.(m[:storedEnergy_HEAT]),
        :charging_HEAT => JuMP.value.(m[:charging_HEAT]),
        :discharging_HEAT => JuMP.value.(m[:discharging_HEAT]),
        :Demand_ELEC => JuMP.value.(m[:Demand_ELEC]),
        :Demand_GAS => JuMP.value.(m[:Demand_GAS]),
        :BaselineDemand_fromGAS => JuMP.value.(m[:BaselineDemand_fromGAS]),
        :BaselineDemand_fromDirectHeat => JuMP.value.(m[:BaselineDemand_fromDirectHeat]),
        :Flows_Elec => JuMP.value.(m[:Flows_Elec]),
        :unitsbuilt_TRANS_ELEC => JuMP.value.(m[:unitsbuilt_TRANS_ELEC]),
        :unitsretired_TRANS_ELEC => JuMP.value.(m[:unitsretired_TRANS_ELEC]),
        :addflow_TRANS_ELEC => JuMP.value.(m[:addflow_TRANS_ELEC]),
        :Flows_Gas => JuMP.value.(m[:Flows_Gas]),
        :unitsbuilt_TRANS_GAS => JuMP.value.(m[:unitsbuilt_TRANS_GAS]),
        :unitsretired_TRANS_GAS => JuMP.value.(m[:unitsretired_TRANS_GAS]),
        :SUPPLY_GAS_slack => JuMP.value.(m[:SUPPLY_GAS_slack]),
        :CleanGas_gassector => JuMP.value.(m[:CleanGas_gassector]),
        :CleanGas_powersector => JuMP.value.(m[:CleanGas_powersector]),
        :excess_powerEmissions => JuMP.value.(m[:excess_powerEmissions]),
        :excess_gasEmissions => JuMP.value.(m[:excess_gasEmissions]),
        :excess_fugitiveMethaneEmissions => JuMP.value.(m[:excess_fugitiveMethaneEmissions]),
        :methaneEmissions => JuMP.value.(m[:methaneEmissions]),  
    )

    if param["LINKED_PERIODS_STORAGE"] == 1
        results[:MinSOC_ELEC] = JuMP.value.(m[:MinSOC_ELEC])
        results[:MaxSOC_ELEC] = JuMP.value.(m[:MaxSOC_ELEC])
        results[:SOCTracked_ELEC] = JuMP.value.(m[:SOCTracked_ELEC])
        results[:MinSOC_GAS] = JuMP.value.(m[:MinSOC_GAS])
        results[:MaxSOC_GAS] = JuMP.value.(m[:MaxSOC_GAS])
        results[:SOCTracked_GAS] = JuMP.value.(m[:SOCTracked_GAS])
        results[:MinSOC_HEAT] = JuMP.value.(m[:MinSOC_HEAT])
        results[:MaxSOC_HEAT] = JuMP.value.(m[:MaxSOC_HEAT])
        results[:SOCTracked_HEAT] = JuMP.value.(m[:SOCTracked_HEAT])
    end

    if param["allsector_emissions_constraint"] == 1
        results[:powerEmissions] = JuMP.value.(m[:powerEmissions])
        results[:gasEmissions] = JuMP.value.(m[:gasEmissions])
        results[:appEmissions] = JuMP.value.(m[:appEmissions])
        results[:fugitiveMethaneEmissions] = JuMP.value.(m[:fugitiveMethaneEmissions])
    end

    return results
end

function mk_output_dir(case_name)
    timestamp = Dates.format(now(), "YYYYmmdd-HHMMSS")
    dir_name = joinpath(@__DIR__, "..", "..", "output", case_name, timestamp)
    @assert !ispath(dir_name) "File name already taken"
    mkpath(dir_name)
    return dir_name,timestamp
end