using JuMP

function add_constraint_flow!(m::Model, param, cons, data)

    GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT, ELEC, GAS, PROF, CLUSTER = unpack_data(data)

    T_inv = param["T_inv"]
    T_ops = param["T_ops"]
    t_ops = param["t_ops"]
    Years = param["Years"]

    NODES_ELEC = ELEC[:Nodes]
    NODES_GAS = GAS[:Nodes]
    GAS_COMPONENTS = param["GAS_COMPONENTS"]

    gen = GEN[:Units]
    p2g = P2G[:Units]
    p2h = P2H[:Units]
    sto_elec = STO_ELEC[:Units]
    sto_heat = STO_HEAT[:Units]
    sto_gas = STO_GAS[:Units]
    app = APP[:Units]
    RepDays = CLUSTER[:repdays]

    @variable(m, Demand_ELEC[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_ELEC] >= 0)
    @variable(m, Demand_GAS[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS] >= 0)
    @variable(m, 0 <= BaselineDemand_fromGAS[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS])
    @variable(m, 0 <= BaselineDemand_fromDirectHeat[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS])

    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_ELEC], m[:Demand_ELEC][I,T,t,n] == PROF[:BaselineELEC][I,T,t,n] + cons["UNIT_PER_THOUSAND"]*sum(APP[:to_ELEC][n,a]*(m[:unitsremaining_APPS][I,a])*PROF[:ApplianceELEC][T,t,a] for a = 1:app))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], m[:Demand_GAS][I,T,t,n] == m[:BaselineDemand_fromGAS][I,T,t,n] + cons["UNIT_PER_THOUSAND"]*sum(APP[:to_GAS][n,a]*(m[:unitsremaining_APPS][I,a])*PROF[:ApplianceGAS][T,t,a] for a = 1:app))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], PROF[:BaselineHEAT][I,T,t,n] == m[:BaselineDemand_fromGAS][I,T,t,n] + m[:BaselineDemand_fromDirectHeat][I,T,t,n] )

    ###############################################################################
    ### Transmission of electric power
    # See Eq. 2.18 in Von Wald thesis
    ###############################################################################
    @variable(m, Flows_Elec[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, e = 1:ELEC[:EDGES]])

    # Built to permit eventual inclusion of transmission expansion
    if param["TRANSMISSION_EXPANSION_ELEC"] == 0
        m[:unitsbuilt_TRANS_ELEC] = zeros(T_inv,ELEC[:EDGES])
        m[:unitsretired_TRANS_ELEC] = zeros(T_inv,ELEC[:EDGES])
        m[:addflow_TRANS_ELEC] = zeros(T_inv,ELEC[:EDGES])
    elseif param["TRANSMISSION_EXPANSION_ELEC"] == 1
        @variable(m, unitsbuilt_TRANS_ELEC[I = 1:T_inv, e = 1:ELEC[:EDGES]], Bin)
        @variable(m, unitsretired_TRANS_ELEC[I = 1:T_inv, e = 1:ELEC[:EDGES]], Bin)
        @constraint(m, [e = 1:ELEC[:EDGES]], sum(m[:unitsbuilt_TRANS_ELEC][I,e] for I = 1:T_inv) <=  ELEC[:MaxNew][e])
        @constraint(m, [I = 1:T_inv, e = 1:ELEC[:EDGES]], sum(m[:unitsretired_TRANS_ELEC][i0,e] for i0 = 1:I) <=  ELEC[:ExistingUnits][e] + sum(m[:unitsbuilt_TRANS_ELEC][i0,e] for i0 = 1:I))
        m[:addflow_TRANS_ELEC] = zeros(T_inv,ELEC[:EDGES])
    elseif param["TRANSMISSION_EXPANSION_ELEC"] == 2
        m[:unitsbuilt_TRANS_ELEC] = zeros(T_inv,ELEC[:EDGES])
        m[:unitsretired_TRANS_ELEC] = zeros(T_inv,ELEC[:EDGES])
        @variable(m, addflow_TRANS_ELEC[I = 1:T_inv,e = 1:ELEC[:EDGES]] >= 0)        # MW
    end

    ## If not simulating steady-state power flows, flows are only bound by the maximum power flow specified for the line (i.e., simple transport model)
    ## If simulating steady-state power flows, we introduce additional voltage angle variables and constraints governing the power flow
    if param["STEADYSTATE_ELEC"] == 0
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, e = 1:ELEC[:EDGES]], m[:Flows_Elec][I,T,t,e] <= (sum(m[:unitsbuilt_TRANS_ELEC][i0,e] - m[:unitsretired_TRANS_ELEC][i0,e] for i0 = 1:I) + ELEC[:ExistingUnits][e])*ELEC[:MaxPower][e] + sum(m[:addflow_TRANS_ELEC][i0,e] for i0 = 1:I))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, e = 1:ELEC[:EDGES]], m[:Flows_Elec][I,T,t,e] >= -1*(sum(m[:unitsbuilt_TRANS_ELEC][i0,e] - m[:unitsretired_TRANS_ELEC][i0,e] for i0 = 1:I) + ELEC[:ExistingUnits][e])*ELEC[:MaxPower][e] - sum(m[:addflow_TRANS_ELEC][i0,e] for i0 = 1:I))
    elseif param["STEADYSTATE_ELEC"] == 1
        SLACK_BUS = 1
        @variable(m, -2*cons["PI"] <= BusAngle[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_ELEC] <= 2*cons["PI"])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops], m[:BusAngle][I,T,t,SLACK_BUS] == 0)
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, e = 1:ELEC[:EDGES]], m[:Flows_Elec][I,T,t,e] <= cons["BASEMVA"]*-1/ELEC[:Reactance][e]*sum(ELEC[:A][n,e]*m[:BusAngle][I,T,t,n] for n = 1:NODES_ELEC) + ELEC[:MaxPower][e]*(1-sum(m[:unitsbuilt_TRANS_ELEC][i0,e] - m[:unitsretired_TRANS_ELEC][i0,e] for i0 = 1:I) + ELEC[:ExistingUnits][e]) + sum(m[:addflow_TRANS_ELEC][i0,e] for i0 = 1:I))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, e = 1:ELEC[:EDGES]], m[:Flows_Elec][I,T,t,e] >= cons["BASEMVA"]*-1/ELEC[:Reactance][e]*sum(ELEC[:A][n,e]*m[:BusAngle][I,T,t,n] for n = 1:NODES_ELEC) - ELEC[:MaxPower][e]*(1-sum(m[:unitsbuilt_TRANS_ELEC][i0,e] - m[:unitsretired_TRANS_ELEC][i0,e] for i0 = 1:I) + ELEC[:ExistingUnits][e]) - sum(m[:addflow_TRANS_ELEC][i0,e] for i0 = 1:I))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, e = 1:ELEC[:EDGES]], m[:Flows_Elec][I,T,t,e] <= (sum(m[:unitsbuilt_TRANS_ELEC][i0,e] - m[:unitsretired_TRANS_ELEC][i0,e] for i0 = 1:I) + ELEC[:ExistingUnits][e])*ELEC[:RatedPower][e] + sum(m[:addflow_TRANS_ELEC][i0,e] for i0 = 1:I))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, e = 1:ELEC[:EDGES]], m[:Flows_Elec][I,T,t,e] >= -1*(sum(m[:unitsbuilt_TRANS_ELEC][i0,e] - m[:unitsretired_TRANS_ELEC][i0,e] for i0 = 1:I) + ELEC[:ExistingUnits][e])*ELEC[:RatedPower][e] - sum(m[:addflow_TRANS_ELEC][i0,e] for i0 = 1:I))
    end

    ###############################################################################
    ### Energy Balance for electricity grid
    # See Eq. 2.19 in Von Wald thesis
    ###############################################################################
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_ELEC], sum(GEN[:to_ELEC][n,g]*m[:generation][I,T,t,g] for g = 1:gen) 
                                                                            + sum(-1*ELEC[:A][n,e]*m[:Flows_Elec][I,T,t,e] for e = 1:ELEC[:EDGES]) 
                                                                            - sum(STO_ELEC[:to_ELEC][n,s]*(m[:charging_ELEC][I,T,t,s]-m[:discharging_ELEC][I,T,t,s]) for s = 1:sto_elec) 
                                                                            - m[:Demand_ELEC][I,T,t,n] 
                                                                            - sum(P2G[:to_ELEC][n,d]*m[:P2G_dispatch][I,T,t,d]*(1-P2G[:isBiomethane][d]) for d = 1:p2g) 
                                                                            - sum(P2H[:to_ELEC][n,d]*m[:P2H_dispatch][I,T,t,d] for d = 1:p2h)
                                                                            - sum(STO_HEAT[:to_HEAT][n,s] * m[:charging_HEAT][I,T,t,s] for s = 1:sto_heat) >= 0)


    ###############################################################################
    ### Transmission of gaseous fuel
    # See Eq. 2.X in Von Wald thesis
    ###############################################################################
    # Nodal gaseous energy demand balance imposed on average across the day
    @variable(m, Flows_Gas[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]])                      # [standard m3/sec]

    if param["TRANSMISSION_EXPANSION_GAS"] == 0
        m[:unitsbuilt_TRANS_GAS] = zeros(T_inv,GAS[:EDGES])
        m[:unitsretired_TRANS_GAS] = zeros(T_inv,GAS[:EDGES])
    elseif param["TRANSMISSION_EXPANSION_GAS"] == 1
        @variable(m, unitsbuilt_TRANS_GAS[I = 1:T_inv, e = 1:GAS[:EDGES]], Bin)
        @variable(m, unitsretired_TRANS_GAS[I = 1:T_inv, e = 1:GAS[:EDGES]], Bin)
        @constraint(m, [e = 1:GAS[:EDGES]], sum(m[:unitsbuilt_TRANS_GAS][I,e] for I = 1:T_inv) <=  GAS[:MaxNew][e])
        @constraint(m, [I = 1:T_inv, e = 1:GAS[:EDGES]], sum(m[:unitsretired_TRANS_GAS][i0,e] for i0 = 1:I) <=  GAS[:ExistingUnits][e] + sum(m[:unitsbuilt_TRANS_GAS][i0,e] for i0 = 1:I))
    end

    if param["GASFLOW_DIRECTIONS"] == 0
        m[:GasFlowDirection] = ones(T_inv,T_ops,GAS[:EDGES])
    elseif param["GASFLOW_DIRECTIONS"] == 1
        @variable(m, GasFlowDirection[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], Bin)
    end

    @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas][I,T,e] <= (sum(m[:unitsbuilt_TRANS_GAS][i0,e] - m[:unitsretired_TRANS_GAS][i0,e] for i0 = 1:I) + GAS[:ExistingUnits][e])*GAS[:MaxGas][e])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], -1*m[:Flows_Gas][I,T,e] <= (sum(m[:unitsbuilt_TRANS_GAS][i0,e] - m[:unitsretired_TRANS_GAS][i0,e] for i0 = 1:I) + GAS[:ExistingUnits][e])*GAS[:MaxGas][e])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas][I,T,e] <= m[:GasFlowDirection][I,T,e]*GAS[:MaxGas][e])
    @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas][I,T,e] >= (m[:GasFlowDirection][I,T,e]-1)*(GAS[:MaxGas][e]))

    if (param["STEADYSTATE_GAS"] == 1) & (NODES_GAS > 1)
        @variable(m, (cons["PRESSURE_MIN"]) <= NodalP2[I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS] <= (cons["PRESSURE_MAX"]))
        @variable(m, cons["PRESSURE_MIN"] <= CompressionP2[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]] <= cons["PRESSURE_MAX"])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2][I,T,e] >= sum(max(GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2][I,T,e] <= GAS[:MaxCompression][e]*sum(max(GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS))

        @constraint(m, [I = 1:T_inv, T = 1:T_ops], m[:NodalP2][I,T,param["SLACK_NODE"]] == (cons["PRESSURE_MAX"]))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]],  m[:CompressionP2][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS) <= m[:GasFlowDirection][I,T,e]*((cons["PRESSURE_MAX"])-(cons["PRESSURE_MIN"])))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS) >= (1-m[:GasFlowDirection][I,T,e])*((cons["PRESSURE_MIN"])-(cons["PRESSURE_MAX"])))
        
        @variable(m, 0 <= lambda[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]] <= cons["PRESSURE_MAX"]-cons["PRESSURE_MIN"])
        a1 = -1
        a2 = cons["PRESSURE_MIN"]-(cons["PRESSURE_MAX"])
        b1 = 1
        b2 = (cons["PRESSURE_MAX"])-(cons["PRESSURE_MIN"])

        # Lambda is a tight constraint such that when y = 1, lambda = P1-P2 and when y = 0, lambda = P2-P1
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda][I,T,e] >= a2*(2*m[:GasFlowDirection][I,T,e]-1) + a1*(m[:CompressionP2][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS)) - a1*a2)
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda][I,T,e] >= b2*(2*m[:GasFlowDirection][I,T,e]-1) + b1*(m[:CompressionP2][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS)) - b1*b2)
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda][I,T,e] <= b2*(2*m[:GasFlowDirection][I,T,e]-1) + a1*(m[:CompressionP2][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS)) - a1*b2)
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda][I,T,e] <= a2*(2*m[:GasFlowDirection][I,T,e]-1) + b1*(m[:CompressionP2][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS)) - b1*a2)
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas][I,T,e]*m[:Flows_Gas][I,T,e] <= GAS[:K2][e]/GAS[:Distance][e]*(m[:lambda][I,T,e]))
    end


    ################################################################################
    ### Gaseous fuel slack supply
    # See Eq. 2.41 in Von Wald thesis
    ###############################################################################
    @variable(m, SUPPLY_GAS_slack[I = 1:T_inv, T = 1:T_ops,  n = 1:NODES_GAS] >= 0)
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS], m[:SUPPLY_GAS_slack][I,T,n] <= GAS[:MAXSLACK][n])

    ## Introduce nominal gas component tracking formulation
    # See Eq. 2.42 in Von Wald thesis
    ###############################################################################
    @variable(m, NominalGasOfftakes[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS, g = 1:GAS_COMPONENTS] >= 0)     # kmol/sec
    @variable(m, NominalGasFlows[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES], g = 1:GAS_COMPONENTS])                          # kmol/sec
    @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES], g = 1:GAS_COMPONENTS], m[:NominalGasFlows][I,T,e,g] <= m[:GasFlowDirection][I,T,e]*(GAS[:MaxGas][e]))
    @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES], g = 1:GAS_COMPONENTS], m[:NominalGasFlows][I,T,e,g] >= (m[:GasFlowDirection][I,T,e]-1)*(GAS[:MaxGas][e]))

    ## Constrain nominal values to match physical values
    # See Eq. 2.43-2.44 in Von Wald thesis
    ###############################################################################
    @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES]], sum(GAS[:MM][g]*m[:NominalGasFlows][I,T,e,g] for g = 1:GAS_COMPONENTS) == cons["M_CH4"]*cons["UNIVDENSITY_CH4"]*m[:Flows_Gas][I,T,e])
    @constraint(m, [I = 1:T_inv,  T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], sum(GAS[:LHV][g]*GAS[:MM][g]*m[:NominalGasOfftakes][I,T,t,n,g] for g = 1:GAS_COMPONENTS) == m[:Demand_GAS][I,T,t,n] + sum(GEN[:to_GAS][n,g]*(m[:generation][I,T,t,g]*GEN[:HeatRate][g] + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*cons["MWh_PER_MMBTU"]*GEN[:isNGFueled][g] for g = 1:gen))

    ## Molar balance
    # See Eq. 2.45 in Von Wald thesis
    ###############################################################################
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS, g = 1:GAS_COMPONENTS], GAS[:FRAC_SLACK][n,g]/(GAS[:LHV_SLACK][n]*GAS[:MM_SLACK][n])*m[:SUPPLY_GAS_slack][I,T,n] 
                                        + sum(-1*GAS[:A][n,e]*m[:NominalGasFlows][I,T,e,g] for e = 1:GAS[:EDGES]) 
                                        - sum(m[:NominalGasOfftakes][I,T,t,n,g] for t = 1:t_ops)/t_ops 
                                        - sum(sum(STO_GAS[:MoleFracs][s,g]/(STO_GAS[:LHV_STORAGE][s]*STO_GAS[:MM_STORAGE][s])*STO_GAS[:to_GAS][n,s]*(m[:charging_GAS][I,T,t,s]
                                        -m[:discharging_GAS][I,T,t,s]) for s = 1:sto_gas) for t = 1:t_ops)/t_ops 
                                        + sum(sum(P2G[:MoleFracs][d,g]/(P2G[:LHV_P2G][d]*P2G[:MM_P2G][d])*P2G[:to_GAS][n,d]*m[:P2G_dispatch][I,T,t,d]*P2G[:ETA][d] for d = 1:p2g) for t = 1:t_ops)/t_ops == 0)

    ## Energy balance
    # See Eq. 2.47 in Von Wald thesis
    ###############################################################################
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS], sum(sum(-1*GAS[:A][n,e]*GAS[:LHV][g]*GAS[:MM][g]*m[:NominalGasFlows][I,T,e,g] for e = 1:GAS[:EDGES]) for g = 1:GAS_COMPONENTS) 
                                                                + m[:SUPPLY_GAS_slack][I,T,n] 
                                                                - sum(sum(STO_GAS[:to_GAS][n,s]*(m[:charging_GAS][I,T,t,s]-m[:discharging_GAS][I,T,t,s]) for s = 1:sto_gas) for t = 1:t_ops)/t_ops 
                                                                - sum(m[:Demand_GAS][I,T,t,n] + sum(GEN[:to_GAS][n,g]*(m[:generation][I,T,t,g]*GEN[:HeatRate][g] 
                                                                + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*cons["MWh_PER_MMBTU"]*GEN[:isNGFueled][g] for g = 1:gen) 
                                                                - sum(P2G[:to_GAS][n,d]*m[:P2G_dispatch][I,T,t,d]*P2G[:ETA][d] for d = 1:p2g) for t = 1:t_ops)/t_ops == 0)


    ## Heat Energy Balance
    # See Eq. TBD, in Saad thesis
    ###############################################################################
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], m[:BaselineDemand_fromDirectHeat][I,T,t,n]
                                                                            - sum( P2H[:to_ELEC][n,d] * m[:P2H_dispatch][I,T,t,d] * P2H[:ETA][d] for d = 1:p2h)
                                                                            - sum( STO_HEAT[:to_HEAT][n,s] * m[:discharging_HEAT][I,T,t,s] * STO_HEAT[:DischargeETA][s] for s = 1:sto_heat) 
                                                                            == 0 )

    if param["nonGasHeat_ON"] == 1
        if param["simpleHeatElectrification_ON"] == 1
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:discharging_HEAT][I,T,t,s] == 0 )
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], m[:BaselineDemand_fromDirectHeat][I,T,t,n] <= param["fraction_electrifiableHeat"] * PROF[:BaselineHEAT][I,T,t,n] )
        end
    else
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], m[:BaselineDemand_fromDirectHeat][I,T,t,n] == 0)
    end

    @expression(m, GAS_energy_P2G[I = 1:T_inv, T = 1:T_ops], sum(sum(m[:P2G_dispatch][I,T,t,d]*P2G[:ETA][d] for d=1:p2g) for t=1:t_ops))
    @expression(m, GAS_energy_Imports[I = 1:T_inv, T = 1:T_ops], t_ops * sum(m[:SUPPLY_GAS_slack][I,T,n] for n=1:NODES_GAS))
    @expression(m, GAS_energy_Charging[I = 1:T_inv, T = 1:T_ops], sum(sum(m[:charging_GAS][I,T,t,s] for s = 1:sto_gas) for t = 1:t_ops))
    @expression(m, GAS_energy_Discharging[I = 1:T_inv, T = 1:T_ops], sum(sum(m[:discharging_GAS][I,T,t,s] for s = 1:sto_gas) for t = 1:t_ops))
    @expression(m, GAS_energy_Demand[I = 1:T_inv, T = 1:T_ops], sum(sum(sum(m[:NominalGasOfftakes][I,T,t,n,g]*GAS[:LHV][g]*GAS[:MM][g] for g=1:GAS_COMPONENTS) for n=1:NODES_GAS) for t = 1:t_ops))

    ################################################################################
    ### Gas quality constraints
    # See Eq. 2.48-2.50 in Von Wald thesis
    ################################################################################
    if param["GasQuality"] == "Annual"
        ## Mole fraction limit imposed on annual, system-wide basis
        # See Eq. 2.48 in Von Wald thesis
        @constraint(m, [I = 1:T_inv, g = 1:GAS_COMPONENTS], sum(CLUSTER[:weights][i,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(m[:NominalGasOfftakes][I,T,t,n,g] for t = 1:t_ops) for n = 1:NODES_GAS) for T = 1:T_ops) <= GAS[:FRAC_MAX][g]*sum(sum(CLUSTER[:weights][i,T]*cons["HOURS_PER_YEAR"]/t_ops*sum(sum(m[:NominalGasOfftakes][I,T,t,n,h] for t = 1:t_ops) for n = 1:NODES_GAS) for T = 1:T_ops) for h = 1:GAS_COMPONENTS))
    elseif param["GasQuality"] == "Nodal"
        ## Mole fraction limit imposed on daily, nodal basis
        # See Eq. 2.49 in Von Wald thesis
        @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES], g = 1:GAS_COMPONENTS], m[:NominalGasFlows][I,T,e,g] <= GAS[:FRAC_MAX][g]*sum(m[:NominalGasFlows][I,T,e,h] for h = 1:GAS_COMPONENTS) + (1-m[:GasFlowDirection][I,T,e])*(GAS[:MaxGas][e]))
        @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES], g = 1:GAS_COMPONENTS], m[:NominalGasFlows][I,T,e,g] >= GAS[:FRAC_MAX][g]*sum(m[:NominalGasFlows][I,T,e,h] for h = 1:GAS_COMPONENTS) - m[:GasFlowDirection][I,T,e]*(GAS[:MaxGas][e]))
        @constraint(m, [I = 1:T_inv,  T = 1:T_ops, n = 1:NODES_GAS, g = 1:GAS_COMPONENTS], sum(m[:NominalGasOfftakes][I,T,t,n,g] for t = 1:t_ops) <= GAS[:FRAC_MAX][g]*sum(sum(m[:NominalGasOfftakes][I,T,t,n,h] for t = 1:t_ops) for h = 1:GAS_COMPONENTS))

        ## Heating value limit imposed on daily, nodal basis
        # See Eq. 2.50 in Von Wald thesis
        @constraint(m, [I = 1:T_inv,  T = 1:T_ops, n = 1:NODES_GAS], sum(sum(GAS[:LHV][g]*GAS[:MM][g]*m[:NominalGasOfftakes][I,T,t,n,g] for g = 1:GAS_COMPONENTS) for t = 1:t_ops) <= cons["HV_MAX"]*sum(sum(GAS[:MM][g]*m[:NominalGasOfftakes][I,T,t,n,g] for g = 1:GAS_COMPONENTS) for t = 1:t_ops))
        @constraint(m, [I = 1:T_inv,  T = 1:T_ops, n = 1:NODES_GAS], sum(sum(GAS[:LHV][g]*GAS[:MM][g]*m[:NominalGasOfftakes][I,T,t,n,g] for g = 1:GAS_COMPONENTS) for t = 1:t_ops) >= cons["HV_MIN"]*sum(sum(GAS[:MM][g]*m[:NominalGasOfftakes][I,T,t,n,g] for g = 1:GAS_COMPONENTS) for t = 1:t_ops))
    end


    ###############################################################################
    ### Bounding steady-states
    # Not included in Von Wald thesis
    ###############################################################################
    if param["bounding_steady_states"] == 1
        @variable(m, Flows_Gas_Min[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]])                  # [m3/sec]
        @variable(m, Flows_Gas_Max[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]])                  # [m3/sec]
        @variable(m, SUPPLY_GAS_slack_Max[I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS] >= 0)
        @variable(m, SUPPLY_GAS_slack_Min[I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS] >= 0)
        @variable(m, NetGasDemands_Max[I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS])
        @variable(m, NetGasDemands_Min[I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS])
        
        if param["GASFLOW_DIRECTIONS"] == 0
            m[:GasFlowDirection_Min] = ones(T_inv,T_ops,GAS[:EDGES])
            m[:GasFlowDirection_Max] = ones(T_inv,T_ops,GAS[:EDGES])
        elseif GASFLOW_DIRECTIONS == 1
            @variable(m, GasFlowDirection_Min[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], Bin)
            @variable(m, GasFlowDirection_Max[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], Bin)
        end
        
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Min][I,T,e] <= (sum(m[:unitsbuilt_TRANS_GAS][i0,e] - m[:unitsretired_TRANS_GAS][i0,e] for i0 = 1:I) + GAS[:ExistingUnits][e])*GAS[:MaxGas][e])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], -1*m[:Flows_Gas_Min][I,T,e] <= (sum(m[:unitsbuilt_TRANS_GAS][i0,e] - m[:unitsretired_TRANS_GAS][i0,e] for i0 = 1:I) + GAS[:ExistingUnits][e])*GAS[:MaxGas][e])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Min][I,T,e] <= m[:GasFlowDirection_Min][I,T,e]*GAS[:MaxGas][e])
        @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Min][I,T,e] >= (m[:GasFlowDirection_Min][I,T,e]-1)*(GAS[:MaxGas][e]))
        
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Max][I,T,e] <= (sum(m[:unitsbuilt_TRANS_GAS][i0,e] - m[:unitsretired_TRANS_GAS][i0,e] for i0 = 1:I) + GAS[:ExistingUnits][e])*GAS[:MaxGas][e])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], -1*m[:Flows_Gas_Max][I,T,e] <= (sum(m[:unitsbuilt_TRANS_GAS][i0,e] - m[:unitsretired_TRANS_GAS][i0,e] for i0 = 1:I) + GAS[:ExistingUnits][e])*GAS[:MaxGas][e])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Max][I,T,e] <= m[:GasFlowDirection_Max][I,T,e]*GAS[:MaxGas][e])
        @constraint(m, [I = 1:T_inv,  T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Max][I,T,e] >= (m[:GasFlowDirection_Max][I,T,e]-1)*(GAS[:MaxGas][e]))
        
        if (param["STEADYSTATE_GAS"] == 1) & (NODES_GAS > 1)
            @variable(m, (cons["PRESSURE_MIN"]) <= NodalP2_Min[I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS] <= (cons["PRESSURE_MAX"]))
            @variable(m, cons["PRESSURE_MIN"] <= CompressionP2_Min[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]] <= cons["PRESSURE_MAX"])
            @variable(m, (cons["PRESSURE_MIN"]) <= NodalP2_Max[I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS] <= (cons["PRESSURE_MAX"]))
            @variable(m, cons["PRESSURE_MIN"] <= CompressionP2_Max[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]] <= cons["PRESSURE_MAX"])

            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2_Min][I,T,e] >= sum(max(GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2_Min][I,T,e] <= GAS[:MaxCompression][e]*sum(max(GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2_Max][I,T,e] >= sum(max(GAS[:A][n,e],0)*m[:NodalP2][I,T,n] for n = 1:NODES_GAS))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2_Max][I,T,e] <= GAS[:MaxCompression][e]*sum(max(GAS[:A][n,e],0)*m[:NodalP2_Max][I,T,n] for n = 1:NODES_GAS))
        
            @constraint(m, [I = 1:T_inv, T = 1:T_ops], m[:NodalP2_Min][I,T,param["SLACK_NODE"]] == (cons["PRESSURE_MAX"]))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]],  m[:CompressionP2_Min][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS) <= m[:GasFlowDirection_Min][I,T,e]*((cons["PRESSURE_MAX"])-(cons["PRESSURE_MIN"])))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2_Min][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS) >= (1-m[:GasFlowDirection_Min][I,T,e])*((cons["PRESSURE_MIN"])-(cons["PRESSURE_MAX"])))
        
            @constraint(m, [I = 1:T_inv, T = 1:T_ops], m[:NodalP2_Max][I,T,param["SLACK_NODE"]] == (cons["PRESSURE_MAX"]))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]],  m[:CompressionP2_Max][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Max][I,T,n] for n = 1:NODES_GAS) <= m[:GasFlowDirection_Max][I,T,e]*((cons["PRESSURE_MAX"])-(cons["PRESSURE_MIN"])))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:CompressionP2_Max][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Max][I,T,n] for n = 1:NODES_GAS) >= (1-m[:GasFlowDirection_Max][I,T,e])*((cons["PRESSURE_MIN"])-(cons["PRESSURE_MAX"])))
            
            @variable(m, 0 <= lambda_Min[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]] <= cons["PRESSURE_MAX"]-cons["PRESSURE_MIN"])
            @variable(m, 0 <= lambda_Max[I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]] <= cons["PRESSURE_MAX"]-cons["PRESSURE_MIN"])
            a1 = -1
            a2 = cons["PRESSURE_MIN"]-(cons["PRESSURE_MAX"])
            b1 = 1
            b2 = (cons["PRESSURE_MAX"])-(cons["PRESSURE_MIN"])
        
            # Lambda is a tight constraint such that when y = 1, lambda = P1-P2 and when y = 0, lambda = P2-P1
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Min][I,T,e] >= a2*(2*m[:GasFlowDirection_Min][I,T,e]-1) + a1*(m[:CompressionP2_Min][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS)) - a1*a2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Min][I,T,e] >= b2*(2*m[:GasFlowDirection_Min][I,T,e]-1) + b1*(m[:CompressionP2_Min][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS)) - b1*b2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Min][I,T,e] <= b2*(2*m[:GasFlowDirection_Min][I,T,e]-1) + a1*(m[:CompressionP2_Min][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS)) - a1*b2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Min][I,T,e] <= a2*(2*m[:GasFlowDirection_Min][I,T,e]-1) + b1*(m[:CompressionP2_Min][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Min][I,T,n] for n = 1:NODES_GAS)) - b1*a2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Max][I,T,e] >= a2*(2*m[:GasFlowDirection_Max][I,T,e]-1) + a1*(m[:CompressionP2_Max][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Max][I,T,n] for n = 1:NODES_GAS)) - a1*a2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Max][I,T,e] >= b2*(2*m[:GasFlowDirection_Max][I,T,e]-1) + b1*(m[:CompressionP2_Max][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Max][I,T,n] for n = 1:NODES_GAS)) - b1*b2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Max][I,T,e] <= b2*(2*m[:GasFlowDirection_Max][I,T,e]-1) + a1*(m[:CompressionP2_Max][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Max][I,T,n] for n = 1:NODES_GAS)) - a1*b2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:lambda_Max][I,T,e] <= a2*(2*m[:GasFlowDirection_Max][I,T,e]-1) + b1*(m[:CompressionP2_Max][I,T,e]-sum(max(-1*GAS[:A][n,e],0)*m[:NodalP2_Max][I,T,n] for n = 1:NODES_GAS)) - b1*a2)
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Min][I,T,e]*m[:Flows_Gas_Min][I,T,e] <= GAS[:K2][e]/GAS[:Distance][e]*(m[:lambda_Min][I,T,e]))
            @constraint(m, [I = 1:T_inv, T = 1:T_ops, e = 1:GAS[:EDGES]], m[:Flows_Gas_Max][I,T,e]*m[:Flows_Gas_Max][I,T,e] <= GAS[:K2][e]/GAS[:Distance][e]*(m[:lambda_Max][I,T,e]))
        end
        
        
        ###############################################################################
        ### Gaseous fuel Supply = Demand
        ###############################################################################
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS], m[:SUPPLY_GAS_slack_Min][I,T,n] <= GAS[:MAXSLACK][n])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS], m[:SUPPLY_GAS_slack_Max][I,T,n] <= GAS[:MAXSLACK][n])
        
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], m[:NetGasDemands_Max][I,T,n] >= -1*sum(STO_GAS[:to_GAS][n,s]*(charging_GAS[I,T,t,s]-discharging_GAS[I,T,t,s]) for s = 1:sto_gas) - m[:Demand_GAS][I,T,t,n] - sum(GEN[:to_GAS][n,g]*(m[:generation][I,T,t,g]*GEN[:HeatRate][g] + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*cons["MWh_PER_MMBTU"]*GEN[:isNGFueled][g] for g = 1:gen) + sum(P2G[:to_GAS][n,d]*m[:P2G_dispatch][I,T,t,d]*P2G[:ETA][d] for d = 1:p2g))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, n = 1:NODES_GAS], m[:NetGasDemands_Min][I,T,n] <= -1*sum(STO_GAS[:to_GAS][n,s]*(charging_GAS[I,T,t,s]-discharging_GAS[I,T,t,s]) for s = 1:sto_gas) - m[:Demand_GAS][I,T,t,n] - sum(GEN[:to_GAS][n,g]*(m[:generation][I,T,t,g]*GEN[:HeatRate][g] + m[:startup_GEN][I,T,t,g]*GEN[:StartupFuel][g])*cons["MWh_PER_MMBTU"]*GEN[:isNGFueled][g] for g = 1:gen) + sum(P2G[:to_GAS][n,d]*m[:P2G_dispatch][I,T,t,d]*P2G[:ETA][d] for d = 1:p2g))
        
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS], cons["LHV_CH4"]*(sum(-1*GAS[:A][n,e]*m[:Flows_Gas_Min][I,T,e] for e = 1:GAS[:EDGES])) + m[:SUPPLY_GAS_slack_Min][I,T,n] + m[:NetGasDemands_Min][I,T,n] == 0)
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, n = 1:NODES_GAS], cons["LHV_CH4"]*(sum(-1*GAS[:A][n,e]*m[:Flows_Gas_Max][I,T,e] for e = 1:GAS[:EDGES])) + m[:SUPPLY_GAS_slack_Max][I,T,n] + m[:NetGasDemands_Max][I,T,n] == 0)

    end

    return nothing
end