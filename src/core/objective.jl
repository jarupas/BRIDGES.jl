using JuMP

function define_objective!(m::Model, param, cons, data)

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

    ###############################################################################
    ### Objective function = total societal costs [$000s/yr]
    # See Eq. 2.1 in Von Wald thesis
    ###############################################################################
    ### COSTS
    # transmission costs, operation
    @expression(m, costs_transmission[I = 1:T_inv], sum(sum(max(min((Years[i0]+ELEC[:Lifetime])-Years[I],1),0)*(ELEC[:CRF]+param["ElecTransmissionOperatingCosts"])*ELEC[:CAPEX][e]*m[:addflow_TRANS_ELEC][i0,e] for i0 = 1:I)/1000 for e = 1:ELEC[:EDGES]) + sum(ELEC[:AMMORTIZED][e] for e = 1:ELEC[:EDGES])/1000)
    # CO2 offsets costs
    @expression(m, costs_CO2offsets[I = 1:T_inv], param["offsets_Cost"][I]/1000*(m[:excess_powerEmissions][I] + m[:excess_gasEmissions][I] + m[:excess_refEmissions][I] + m[:excess_fugitiveMethaneEmissions][I]))
    # imported natgas costs
    @expression(m, costs_NGimports[I = 1:T_inv], sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]*PROF[:GasPrice][I,T]/1000*sum(m[:SUPPLY_GAS_slack][I,T,n] for n = 1:NODES_GAS) for T = 1:T_ops))
    # generator capital costs, ammortized to each investment period
    @expression(m, costs_GENcapital[I = 1:T_inv], sum(GEN[:UnitSize][g]*sum(m[:unitsbuilt_GEN][i0,g]*max(min((Years[i0]+GEN[:EconomicLifetime][g])-Years[I],1),0)*GEN[:CRF][g]*GEN[:CAPEX][i0,g] for i0 = 1:I) for g = 1:gen))
    # generator operating costs, fuel + VOM + FOM
    @expression(m, costs_GENoperating[I = 1:T_inv], sum(GEN[:UnitSize][g]*(GEN[:ExistingUnits][g]+sum(m[:unitsbuilt_GEN][i0,g]-m[:unitsretired_GEN][i0,g] for i0 = 1:I))*GEN[:FOM][I,g] for g = 1:gen)
                                                        + sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum((GEN[:VOM][I,g]+GEN[:HeatRate][g]*GEN[:FUEL][I,g]*(1-GEN[:isNGFueled][g]))/1000*m[:generation][I,T,t,g] for t = 1:t_ops) for g = 1:gen) for T = 1:T_ops)
                                                        + sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum((GEN[:StartupCost][g]+GEN[:StartupFuel][g]*GEN[:FUEL][I,g]*(1-GEN[:isNGFueled][g]))/1000*sum(m[:startup_GEN][I,T,t,g] for t = 1:t_ops) for g = 1:gen) for T = 1:T_ops))
    # elec storage capital costs, ammortized to each investment period
    @expression(m, costs_ELECSTORAGEcapital[I = 1:T_inv], sum(STO_ELEC[:UnitSize][s]*sum(m[:unitsbuilt_STO_ELEC][i0,s]*max(min((Years[i0]+STO_ELEC[:EconomicLifetime][s])-Years[I],1),0)*STO_ELEC[:CRF][s]*STO_ELEC[:CAPEX][i0,s] for i0 = 1:I) for s = 1:sto_elec))
    # elec storage operating costs, FOM + VOM
    @expression(m, costs_ELECSTORAGEoperating[I = 1:T_inv], sum(STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i0,s]-m[:unitsretired_STO_ELEC][i0,s] for i0 = 1:I))*STO_ELEC[:FOM][I,s] for s = 1:sto_elec))
    # gas storage costs
    @expression(m, costs_gasStorage[I = 1:T_inv], sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(param["gasstorage_cost"]/cons["MWh_PER_MMBTU"]/1000*sum(m[:charging_GAS][I,T,t,s] for s = 1:sto_gas) for t = 1:t_ops) for T = 1:T_ops))
    # gas storage capital costs, ammortized to each investment period
    @expression(m, costs_GASSTORAGEcapital[I = 1:T_inv], sum(STO_GAS[:UnitSize][s]*sum(m[:unitsbuilt_STO_GAS][i0,s]*max(min((Years[i0]+STO_GAS[:EconomicLifetime][s])-Years[I],1),0)*STO_GAS[:CRF][s]*STO_GAS[:CAPEX][i0,s] for i0 = 1:I) for s = 1:sto_gas))
    # gas storage operating costs
    @expression(m, costs_GASSTORAGEoperating[I = 1:T_inv], sum(STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i0,s]-m[:unitsretired_STO_GAS][i0,s] for i0 = 1:I))*STO_GAS[:FOM][I,s] for s = 1:sto_gas))
    # heat storage capital costs, ammortized to each investment period
    @expression(m, costs_HEATSTORAGEcapital[I = 1:T_inv], sum(STO_HEAT[:UnitSize][s]*sum(m[:unitsbuilt_STO_HEAT][i0,s]*max(min((Years[i0]+STO_HEAT[:EconomicLifetime][s])-Years[I],1),0)*STO_HEAT[:CRF][s]*STO_HEAT[:CAPEX][i0,s] for i0 = 1:I) for s = 1:sto_heat))
    # heat storage operating costs, FOM + VOM
    @expression(m, costs_HEATSTORAGEoperating[I = 1:T_inv], sum(STO_HEAT[:UnitSize][s]*(STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i0,s]-m[:unitsretired_STO_HEAT][i0,s] for i0 = 1:I))*STO_HEAT[:FOM][I,s] for s = 1:sto_heat))
    # P2G capital costs, ammortized to each investment period
    @expression(m, costs_P2Gcapital[I = 1:T_inv], sum(P2G[:UnitSize][d]*sum(m[:unitsbuilt_P2G][i0,d]*max(min((Years[i0]+P2G[:EconomicLifetime][d])-Years[I],1),0)*P2G[:CRF][d]*P2G[:CAPEX][i0,d] for i0 = 1:I) for d = 1:p2g))
    # P2G operating costs
    @expression(m, costs_P2Goperating[I = 1:T_inv], sum(P2G[:UnitSize][d]*(P2G[:ExistingUnits][d] + sum(m[:unitsbuilt_P2G][i0,d]-m[:unitsretired_P2G][i0,d] for i0 = 1:I))*P2G[:FOM][I,d] for d = 1:p2g) 
                                                        + sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(P2G[:VOM][I,d]/1000*m[:P2G_dispatch][I,T,t,d] for t = 1:t_ops) for d = 1:p2g) for T = 1:T_ops))
    # P2H capital costs, ammortized to each investment period
    @expression(m, costs_P2Hcapital[I = 1:T_inv], sum(P2H[:UnitSize][d]*sum(m[:unitsbuilt_P2H][i0,d]*max(min((Years[i0]+P2H[:EconomicLifetime][d])-Years[I],1),0)*P2H[:CRF][d]*P2H[:CAPEX][i0,d] for i0 = 1:I) for d = 1:p2h))
    # P2H operating costs
    @expression(m, costs_P2Hoperating[I = 1:T_inv], sum(P2H[:UnitSize][d]*(P2H[:ExistingUnits][d] + sum(m[:unitsbuilt_P2H][i0,d]-m[:unitsretired_P2H][i0,d] for i0 = 1:I))*P2H[:FOM][I,d] for d = 1:p2h) 
                                                        + sum(CLUSTER[:weights][I,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(P2H[:VOM][I,d]/1000*m[:P2H_dispatch][I,T,t,d] for t = 1:t_ops) for d = 1:p2h) for T = 1:T_ops))
    # appliances costs
    @expression(m, costs_appliances[I = 1:T_inv],  sum(sum(APP[:CRF][a]*max(min((Years[i0]+APP[:Lifetime][a])-Years[I],1),0)*(APP[:CAPEX][i0,a]*m[:unitsbuilt_APPS][i0,a]*1000 + m[:applianceInfrastructureCosts][i0,a]) for i0 = 1:I)/1000 for a = 1:app))
    # distribution costs
    @expression(m, costs_distribution[I = 1:T_inv], param["Cost_DistributionInfrastructure"]*sum(m[:PeakDistDemandInc][I,n] for n = 1:NODES_ELEC))
    # gas distribution cost
    @expression(m, gasdistsyst_Cost[I = 1:T_inv], sum(sum(param["shutdown_costs"][d,j,I]/1000*m[:distSysRetirement_GAS][j,d] for d = 1:APP[:DIST_GAS]) for j = 1:T_inv) + sum(param["BAU_costs"][d,I]/1000*(1-sum(m[:distSysRetirement_GAS][j,d] for j = 1:T_inv)) for d = 1:APP[:DIST_GAS]))


    ### OBJECTIVE FUNCTION
    @objective(m, Min, sum(param["discountfactor"][i]*(
        # GEN
        costs_GENcapital[i]
        + costs_GENoperating[i]
        # ELEC Storage
        + costs_ELECSTORAGEcapital[i]
        + costs_ELECSTORAGEoperating[i]
        # GAS Storage
        + costs_GASSTORAGEcapital[i]
        + costs_GASSTORAGEoperating[i]
        # Heat Storage
        + costs_HEATSTORAGEcapital[i]
        + costs_HEATSTORAGEoperating[i]
        # P2G
        + costs_P2Gcapital[i]
        + costs_P2Goperating[i]
        # P2H
        + costs_P2Hcapital[i]
        + costs_P2Hoperating[i]
        # Appliances
        + costs_appliances[i]
        # Distribution costs
        + costs_distribution[i]
        #
        + costs_NGimports[i]
        + gasdistsyst_Cost[i] + costs_CO2offsets[i]
        + costs_transmission[i] + costs_gasStorage[i]
        ) for i = 1:T_inv)
        )

    return nothing
end