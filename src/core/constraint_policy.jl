using JuMP

function add_constraint_policy!(m::Model, param, cons, data)

    GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT, ELEC, GAS, PROF, CLUSTER = unpack_data(data)

    T_inv = param["T_inv"]
    T_ops = param["T_ops"]
    t_ops = param["t_ops"]
    Years = param["Years"]

    NODES_ELEC = ELEC[:Nodes]
    NODES_GAS = GAS[:Nodes]

    gen = GEN[:Units]
    p2g = P2G[:Units]
    p2h = P2H[:Units]
    sto_elec = STO_ELEC[:Units]
    sto_heat = STO_HEAT[:Units]
    sto_gas = STO_GAS[:Units]
    app = APP[:Units]
    RepDays = CLUSTER[:repdays]


    ################################################################################
    ### Policy-driven constraints
    ################################################################################

    if param["consider_refrigerants"] >= 1
        
        annual_leak_pu = APP[:AverageCharge].*APP[:AnnualLeak].*cons["LB_PER_TON"]       # per unit annual leak [ton refrigerant/year]
        eol_loss_pu = APP[:EOLLoss].*APP[:EOLLoss].*cons["LB_PER_TON"]             # per unit eol loss [ton refrigerant]

        @variable(m, appliance_leak[I = 1:T_inv,a = 1:app] >= 0)     # MMTCO2
        @variable(m, APP_historical_leak[I = 1:T_inv,a = 1:app] >= 0)
        @variable(m, APP_historical_retired[I = 1:T_inv,a = 1:app] >= 0)

        @constraint(m, [a = 1:app], m[:APP_historical_retired][1,a] == APP[:ApplianceCount][a] - APP[:unitsHistorical][1,a])
        if T_inv > 1
            @constraint(m, [I = 2:T_inv,a = 1:app], m[:APP_historical_retired][I,a] == APP[:unitsHistorical][I-1,a] - APP[:unitsHistorical][I,a])
        end
        @constraint(m, [I = 1:T_inv,a = 1:app], m[:APP_historical_leak][I,a] == cons["GWP_R410A"]*(annual_leak_pu[a]*APP[:unitsHistorical][I,a] + eol_loss_pu[a]*m[:APP_historical_retired][I,a])/1000) # MMT CO2e/year

        @variable(m, APP_new_leak[I = 1:T_inv,a = 1:app] >= 0)
        @variable(m, APP_new_remaining[I = 1:T_inv,a = 1:app] >= 0)

        @constraint(m, [I = 1:T_inv,a = 1:app], m[:APP_new_remaining][I,a] == sum(m[:unitsbuilt_APPS][i0,a] - m[:unitsretired_APPS][i0,a] for i0 = 1:I))

        if param["consider_refrigerants"] == 1       # CARB aligned
            @constraint(m, [I = 1:T_inv,a = 1:app], m[:APP_new_leak][I,a] == cons["GWP_R32"]*(annual_leak_pu[a]*m[:APP_new_remaining][I,a] + eol_loss_pu[a]*m[:unitsretired_APPS][I,a])/1000) # MMT CO2e/year
            @constraint(m, [I = 1:T_inv,a = 1:app], m[:appliance_leak][I,a] == m[:APP_historical_leak][I,a] + m[:APP_new_leak][I,a])  # MMTCO2/unit
        elseif param["consider_refrigerants"] == 2   # beyond CARB
            @constraint(m, [I = 1:T_inv,a = 1:app], m[:APP_new_leak][I,a] == cons["GWP_C3H8"]*(annual_leak_pu[a]*m[:APP_new_remaining][I,a] + eol_loss_pu[a]*m[:unitsretired_APPS][I,a])/1000) # MMT CO2e/year
            @constraint(m, [I = 1:T_inv,a = 1:app], m[:appliance_leak][I,a] == m[:APP_historical_leak][I,a] + m[:APP_new_leak][I,a])  # MMTCO2/unit
        elseif param["consider_refrigerants"] == 3   # stagnant case
            @constraint(m, [I = 1:T_inv,a = 1:app], m[:APP_new_leak][I,a] == cons["GWP_R410A"]*(annual_leak_pu[a]*m[:APP_new_remaining][I,a] + eol_loss_pu[a]*m[:unitsretired_APPS][I,a])/1000) # MMT CO2e/year
            @constraint(m, [I = 1:T_inv,a = 1:app], m[:appliance_leak][I,a] == m[:APP_historical_leak][I,a] + m[:APP_new_leak][I,a])  # MMTCO2/unit
        else
            error("consider_refrigerants must be between 0 and 3!")
        end
        @variable(m, excess_refEmissions[I = 1:T_inv] >= 0)
    else
        m[:appliance_leak] = zeros(T_inv,app)
        m[:excess_refEmissions] = zeros(T_inv)
    end

    if param["methaneLeak_ON"] == 1
        @variable(m, excess_fugitiveMethaneEmissions[I = 1:T_inv] >= 0)
        @variable(m, methaneEmissions[I = 1:T_inv] >= 0)
        @constraint(m, [I = 1:T_inv], m[:methaneEmissions][I] == sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(m[:SUPPLY_GAS_slack][I,T,n]*t_ops for n = 1:NODES_GAS) for T = 1:T_ops) * param["CH4_leakage"] / cons["ENERGYCONTENT_CH4"] * cons["GWP_CH4"])
    else
        m[:methaneEmissions] = zeros(T_inv)
        m[:excess_fugitiveMethaneEmissions] = zeros(T_inv)
    end

    ### Nominal allocation of net-zero emissions gas consumption to each sector, 
    # not to exceed the amount of gaseous energy consumed by that sector
    # See Eq. 2.62 in Von Wald thesis
    ################################################################################
    @variable(m, CleanGas_gassector[I = 1:T_inv] >= 0)
    @variable(m, CleanGas_powersector[I = 1:T_inv] >= 0)
    @constraint(m, [I = 1:T_inv], m[:CleanGas_gassector][I] + m[:CleanGas_powersector][I] == sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(m[:P2G_dispatch][I,T,t,d]*P2G[:ETA][d] for d = 1:p2g) for t = 1:t_ops) for T = 1:T_ops))
    @constraint(m, [I = 1:T_inv], m[:CleanGas_powersector][I] <= sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum((m[:generation][I,T,t,g]*GEN[:HeatRate][g] + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*cons["MWh_PER_MMBTU"]*GEN[:isNGFueled][g] for g = 1:gen) for t = 1:t_ops) for T = 1:T_ops))
    @constraint(m, [I = 1:T_inv], m[:CleanGas_gassector][I] <= sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(m[:Demand_GAS][I,T,t,n] for n = 1:NODES_GAS) for t = 1:t_ops) for T = 1:T_ops))

    ### Slack variables for emissions constraint violations that could represent:
    #   > use of negative emissions offsets at a fixed cost 
    #   > excess carbon emissions evaluated in objective function at a "social cost of carbon"
    # The power and gas sector emissions that exceed their respective emissions intensity constraint are constrained by the maxOffsets share of total emissions liabilities
    # See Eq. 2.61 in Von Wald thesis
    ## Constraints on the emissions intensity of the electric and gas sectors.
    # Here, some emissions from gaseous fuel consumption are offset by the nominal allocation of net-zero emission gas to each sector.
    # See Eq. 2.60 in Von Wald thesis
    ################################################################################
    @variable(m, excess_powerEmissions[I = 1:T_inv] >= 0)
    @variable(m, excess_gasEmissions[I = 1:T_inv] >= 0)
    if param["allsector_emissions_constraint"] == 1
        @variable(m, powerEmissions[I = 1:T_inv] >= 0)          # MMTCO2
        @variable(m, gasEmissions[I = 1:T_inv] >= 0)            # MMTCO2
        @variable(m, appEmissions[I = 1:T_inv] >= 0)            # MMTCO2
        @variable(m, fugitiveMethaneEmissions[I = 1:T_inv] >= 0) 

        @constraint(m, [I = 1:T_inv], m[:excess_powerEmissions][I] + m[:excess_gasEmissions][I] + m[:excess_refEmissions][I] + m[:excess_fugitiveMethaneEmissions][I] <= param["maxOffsets"][I]*param["initialEmissions"])
        
        @constraint(m, [I = 1:T_inv], m[:powerEmissions][I] + m[:gasEmissions][I] + m[:appEmissions][I] + m[:fugitiveMethaneEmissions][I] <= param["TotalEmissions_Allowed"][I])     # MMTCO2
        @constraint(m, [I = 1:T_inv], sum(m[:appliance_leak][I,a] for a = 1:app)*1e6 <= m[:appEmissions][I]*1e6 + m[:excess_refEmissions][I])     # MMTCO2
        @constraint(m, [I = 1:T_inv], sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum((m[:generation][I,T,t,g]*GEN[:HeatRate][g] + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*GEN[:EmissionsFactor][g] for g = 1:gen) for t = 1:t_ops) for T = 1:T_ops) - cons["EF_NG"]*m[:CleanGas_powersector][I] <= m[:powerEmissions][I]*1e6 + m[:excess_powerEmissions][I])
        @constraint(m, [I = 1:T_inv], sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*cons["EF_NG"]*sum(sum(m[:Demand_GAS][I,T,t,n] for n = 1:NODES_GAS) for t = 1:t_ops) for T = 1:T_ops) - cons["EF_NG"]*m[:CleanGas_gassector][I] <= m[:gasEmissions][I]*1e6 + m[:excess_gasEmissions][I])    
        @constraint(m, [I = 1:T_inv], m[:methaneEmissions][I] <= m[:fugitiveMethaneEmissions][I]*1e6 + m[:excess_fugitiveMethaneEmissions][I])     # MMTCO2
    else
        @constraint(m, [I = 1:T_inv], m[:excess_powerEmissions][I] <= param["maxOffsets_elec"][I]*(sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum((m[:generation][I,T,t,g]*GEN[:HeatRate][g] + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*GEN[:EmissionsFactor][g] for g = 1:gen) for t = 1:t_ops) for T = 1:T_ops)))
        @constraint(m, [I = 1:T_inv], m[:excess_gasEmissions][I] <= param["maxOffsets_gas"][I]*(sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*cons["EF_NG"]*sum(sum(m[:Demand_GAS][I,T,t,n] for n = 1:NODES_GAS) for t = 1:t_ops) for T = 1:T_ops)))

        @constraint(m, [I = 1:T_inv], sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum((m[:generation][I,T,t,g]*GEN[:HeatRate][g] + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*GEN[:EmissionsFactor][g] for g = 1:gen) for t = 1:t_ops) for T = 1:T_ops) - cons["EF_NG"]*m[:CleanGas_powersector][I]  <= param["EI_ElecSector"][I]/1000*sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(m[:generation][I,T,t,g0] for g0 = 1:gen) for t = 1:t_ops) for T = 1:T_ops) + m[:excess_powerEmissions][I])
        @constraint(m, [I = 1:T_inv], sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*cons["EF_NG"]*sum(sum(m[:Demand_GAS][I,T,t,n] for n = 1:NODES_GAS) for t = 1:t_ops) for T = 1:T_ops) - cons["EF_NG"]*m[:CleanGas_gassector][I] <= param["EI_GasSector"][I]/1000*sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(m[:Demand_GAS][I,T,t,n] for n = 1:NODES_GAS) for t = 1:t_ops) for T = 1:T_ops) + m[:excess_gasEmissions][I])
    end

    ### Maximum biomethane production and use of sustainable bio-energy. 
    # Total bio-energy constraint is included in the case where net-zero emissions fuel production units can be used to generate methane or LPG fuel
    # but must compete for sustainable biomass feedstocks.
    # See Eq. 2.63 in Von Wald thesis
    ################################################################################
    @constraint(m, [I = 1:T_inv], P2G[:maxBiomethane][I] >= sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(P2G[:isBiomethane][d]*m[:P2G_dispatch][I,T,t,d]*P2G[:ETA][d] for d = 1:p2g) for t = 1:t_ops) for T = 1:T_ops))
    @constraint(m, [I = 1:T_inv], P2G[:maxBiomethane][I] >= sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(P2G[:isBiomass][d]*m[:P2G_dispatch][I,T,t,d]*(P2G[:ETA][d]+P2G[:P2LETA][d]) for d = 1:p2g) for t = 1:t_ops) for T = 1:T_ops))

    ###############################################################################
    ### Gas distribution retirement constraint set
    # See Eq. 2.69 in Von Wald thesis
    ###############################################################################
    # User can select whether to allow the model to decide when the retire the gas system
    # by setting gasdistretirement_allowed = 1.
    # In this case, binary variables are introduced to indicate for each distribution system
    # when that system is shut down.
    if param["gasdistretirement_allowed"] == 1
        @variable(m, distSysRetirement_GAS[I = 1:T_inv, d = 1:APP[:DIST_GAS]], Bin)
        @constraint(m, [I = 1:T_inv, d = 1:APP[:DIST_GAS]], (1-sum(m[:distSysRetirement_GAS][j,d] for j = 1:I))*sum(sum(APP[:ApplianceCount][a]*PROF[:ApplianceGAS][t,a] for t = 1:cons["HOURS_PER_YEAR"]) for a = 1:app) >= sum(sum(sum(APP[:DIST_to_GAS][d,a]*(m[:unitsremaining_APPS][I,a])*PROF[:ApplianceGAS][T,t,a] for a = 1:app) for t= 1:t_ops) for T = 1:T_ops))
    # If no gas distribution retirement is contemplated by the model, the distSysRetirement_GAS indicators are fixed parameters
    else
        m[:distSysRetirement_GAS] = zeros(T_inv,APP[:DIST_GAS])
    end


    ###############################################################################
    ### Ancillary customer electrification costs 
    # See Eq. 2.66 in Von Wald thesis
    ###############################################################################
    @variable(m, applianceInfrastructureCosts[I = 1:T_inv, a = 1:app] >= 0)
    @constraint(m,[a = 1:app], m[:applianceInfrastructureCosts][1,a] >= m[:unitsbuilt_APPS][1,a]*1000*APP[:UpgradeCostLow][a])
    if T_inv > 1
        @constraint(m,[I = 2:T_inv, a = 1:app], m[:applianceInfrastructureCosts][I,a] >= 1000*(m[:unitsbuilt_APPS][I,a] - sum(round(APP[:cumFailureProb][a,v,I]-APP[:cumFailureProb][a,v,I-1],digits = 4)*m[:unitsbuilt_APPS][v,a] for v = 1:I-1))*APP[:UpgradeCostLow][a])
    end

    ###############################################################################
    # Generalized distribution capital costs associated with peak electrical demand
    # See Eq. 2.67/2.68 in Von Wald thesis
    # Currently implement a few different approaches to compute:
    # (a) the total peak power demand at each node
    # (b) the peak distribution-level demand at each node
    # (c) the peak incremental distribution-level demand due to appliance electrification (i.e., above baseline demand)
    # Current version uses PeakDistDemandInc in objective function, but an argument could be made
    # that the peak costs should be evaluated with respect to system-wide coincident peak, as opposed to
    # the sum of individual nodal peaks.
    ###############################################################################
    @variable(m, PeakDemand[I = 1:T_inv, n = 1:NODES_ELEC] >= 0)
    @variable(m, PeakDistDemand[I = 1:T_inv, n = 1:NODES_ELEC] >= 0)
    @variable(m, PeakDistDemandInc[I = 1:T_inv, n = 1:NODES_ELEC] >= 0)
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_ELEC], m[:PeakDemand][I,n] >= m[:Demand_ELEC][I,T,t,n] + sum(STO_ELEC[:to_ELEC][n,s]*(m[:charging_ELEC][I,T,t,s]-m[:discharging_ELEC][I,T,t,s]) for s = 1:sto_elec) + sum(P2G[:to_ELEC][n,d]*m[:P2G_dispatch][I,T,t,d]*(1-P2G[:isBiomethane][d]) for d = 1:p2g) + sum(P2H[:to_ELEC][n,d]*m[:P2H_dispatch][I,T,t,d] for d = 1:p2h))
    @constraint(m, [I = 1:T_inv, t = 1:cons["HOURS_PER_YEAR"], n = 1:NODES_ELEC], m[:PeakDistDemand][I,n] >= PROF[:fullBaselineELEC][t,n] + 1000*sum(APP[:to_ELEC][n,a]*(m[:unitsremaining_APPS][I,a])*PROF[:fullApplianceELEC][t,a] for a = 1:app))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_ELEC], m[:PeakDistDemandInc][I,n] >= m[:Demand_ELEC][I,T,t,n] - PROF[:BaselineELEC][I,T,t,n])

    return nothing
end