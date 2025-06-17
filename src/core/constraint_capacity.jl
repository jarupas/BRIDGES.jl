using JuMP

function unpack_data(data::Dict)
    return (
        data[:GEN], data[:APP], data[:P2G], data[:P2H], 
        data[:STO_ELEC], data[:STO_GAS], data[:STO_HEAT], 
        data[:ELEC], data[:GAS], data[:PROF], data[:CLUSTER]
    )
end


function add_constraint_capacity!(m::Model, param, cons, data)

    GEN, APP, P2G, P2H, STO_ELEC, STO_GAS, STO_HEAT, ELEC, GAS, PROF, CLUSTER = unpack_data(data)
    
    T_inv = param["T_inv"]
    T_ops = param["T_ops"]
    t_ops = param["t_ops"]
    Years = param["Years"]

    gen = GEN[:Units]
    p2g = P2G[:Units]
    p2h = P2H[:Units]
    sto_elec = STO_ELEC[:Units]
    sto_heat = STO_HEAT[:Units]
    sto_gas = STO_GAS[:Units]
    app = APP[:Units]

    #--------- GENERATORS ---------
    # Initialize built and retired variables
    @variable(m, 0 <= unitsbuilt_GEN[I = 1:T_inv, g = 1:gen] <= GEN[:MaxNewAnnual][g])
    @variable(m, 0 <= unitsretired_GEN[I = 1:T_inv, g = 1:gen])

    @variable(m, 0 <= unitsbuilt_P2G[I = 1:T_inv, d = 1:p2g] <= P2G[:MaxNewAnnual][d])
    @variable(m, 0 <= unitsretired_P2G[I = 1:T_inv, d = 1:p2g])

    @variable(m, 0 <= unitsbuilt_P2H[I = 1:T_inv, d = 1:p2h] <= P2H[:MaxNewAnnual][d])
    @variable(m, 0 <= unitsretired_P2H[I = 1:T_inv, d = 1:p2h])

    @variable(m, 0 <= unitsbuilt_STO_ELEC[I = 1:T_inv, s = 1:sto_elec] <= STO_ELEC[:MaxNewAnnual][s])
    @variable(m, 0 <= unitsretired_STO_ELEC[I = 1:T_inv, s = 1:sto_elec])

    @variable(m, 0 <= unitsbuilt_STO_HEAT[I = 1:T_inv, s = 1:sto_heat] <= STO_HEAT[:MaxNewAnnual][s])
    @variable(m, 0 <= unitsretired_STO_HEAT[I = 1:T_inv, s = 1:sto_heat])

    @variable(m, 0 <= unitsbuilt_STO_GAS[I = 1:T_inv, s = 1:sto_gas] <= STO_GAS[:MaxNewAnnual][s])
    @variable(m, 0 <= unitsretired_STO_GAS[I = 1:T_inv, s = 1:sto_gas])

    # Constraint on total capacity, retirement, and replacement
    @constraint(m, [g = 1:gen], sum(m[:unitsbuilt_GEN][i,g] for i = 1:T_inv) <= GEN[:MaxNewTotal][g])                     
    @constraint(m, [g = 1:gen], m[:unitsretired_GEN][1,g] <= GEN[:ExistingUnits][g] + m[:unitsbuilt_GEN][1,g])                          
    @constraint(m, [g = 1:gen], m[:unitsretired_GEN][1,g] >= GEN[:ExistingUnits][g]*max(min(Years[1] - GEN[:Retirement][g],1),0)) 

    @constraint(m, [d = 1:p2g], sum(m[:unitsbuilt_P2G][i,d] for i = 1:T_inv) <= P2G[:MaxNewTotal][d])
    @constraint(m, [d = 1:p2g], m[:unitsretired_P2G][1,d] <= P2G[:ExistingUnits][d] + m[:unitsbuilt_P2G][1,d])
    @constraint(m, [d = 1:p2g], m[:unitsretired_P2G][1,d] >= P2G[:ExistingUnits][d]*max(min(Years[1] - P2G[:Retirement][d],1),0))

    @constraint(m, [d = 1:p2h], sum(m[:unitsbuilt_P2H][i,d] for i = 1:T_inv) <= P2H[:MaxNewTotal][d])  
    @constraint(m, [d = 1:p2h], m[:unitsretired_P2H][1,d] <= P2H[:ExistingUnits][d] + m[:unitsbuilt_P2H][1,d])
    @constraint(m, [d = 1:p2h], m[:unitsretired_P2H][1,d] >= P2H[:ExistingUnits][d]*max(min(Years[1] - P2H[:Retirement][d],1),0))
    
    @constraint(m, [s = 1:sto_elec], sum(m[:unitsbuilt_STO_ELEC][i,s] for i = 1:T_inv) <= STO_ELEC[:MaxNewTotal][s])
    @constraint(m, [s = 1:sto_elec], m[:unitsretired_STO_ELEC][1,s] <= STO_ELEC[:ExistingUnits][s] + m[:unitsbuilt_STO_ELEC][1,s])
    @constraint(m, [s = 1:sto_elec], m[:unitsretired_STO_ELEC][1,s] >= STO_ELEC[:ExistingUnits][s]*max(min(Years[1] - STO_ELEC[:Retirement][s],1),0))
    
    @constraint(m, [s = 1:sto_heat], sum(m[:unitsbuilt_STO_HEAT][i,s] for i = 1:T_inv) <= STO_HEAT[:MaxNewTotal][s])
    @constraint(m, [s = 1:sto_heat], m[:unitsretired_STO_HEAT][1,s] <= STO_HEAT[:ExistingUnits][s] + m[:unitsbuilt_STO_HEAT][1,s])
    @constraint(m, [s = 1:sto_heat], m[:unitsretired_STO_HEAT][1,s] >= STO_HEAT[:ExistingUnits][s]*max(min(Years[1] - STO_HEAT[:Retirement][s],1),0))
    
    @constraint(m, [s = 1:sto_gas], sum(m[:unitsbuilt_STO_GAS][i,s] for i = 1:T_inv) <= STO_GAS[:MaxNewTotal][s])
    @constraint(m, [s = 1:sto_gas], m[:unitsretired_STO_GAS][1,s] <= STO_GAS[:ExistingUnits][s] + m[:unitsbuilt_STO_GAS][1,s])
    @constraint(m, [s = 1:sto_gas], m[:unitsretired_STO_GAS][1,s] >= STO_GAS[:ExistingUnits][s]*max(min(Years[1] - STO_GAS[:Retirement][s],1),0))

    if T_inv > 1
        @constraint(m, [I = 2:T_inv, g = 1:gen], m[:unitsretired_GEN][I,g] <= GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i0,g] - m[:unitsretired_GEN][i0,g]  for i0 = 1:I-1))
        @constraint(m, [I = 2:T_inv, g = 1:gen], m[:unitsretired_GEN][I,g] >= GEN[:ExistingUnits][g]*max(min(Years[I] - GEN[:Retirement][g],1),0) + sum(m[:unitsbuilt_GEN][i0,g]*max(min(Years[I] - (Years[i0] + GEN[:Lifetime][g]),1),0) for i0 = 1:I-1) - sum(m[:unitsretired_GEN][i0,g] for i0 = 1:I-1))

        @constraint(m, [I = 2:T_inv, d = 1:p2g], m[:unitsretired_P2G][I,d] <= P2G[:ExistingUnits][d] + sum(m[:unitsbuilt_P2G][i0,d] - m[:unitsretired_P2G][i0,d]  for i0 = 1:I-1))
        @constraint(m, [I = 2:T_inv, d = 1:p2g], m[:unitsretired_P2G][I,d] >= P2G[:ExistingUnits][d]*max(min(Years[I] - P2G[:Retirement][d],1),0) + sum(m[:unitsbuilt_P2G][i0,d]*max(min(Years[I] - (Years[i0] + P2G[:Lifetime][d]),1),0) for i0 = 1:I-1) - sum(m[:unitsretired_P2G][i0,d] for i0 = 1:I-1))

        @constraint(m, [I = 2:T_inv, d = 1:p2h], m[:unitsretired_P2H][I,d] <= P2H[:ExistingUnits][d] + sum(m[:unitsbuilt_P2H][i0,d] - m[:unitsretired_P2H][i0,d]  for i0 = 1:I-1))
        @constraint(m, [I = 2:T_inv, d = 1:p2h], m[:unitsretired_P2H][I,d] >= P2H[:ExistingUnits][d]*max(min(Years[I] - P2H[:Retirement][d],1),0) + sum(m[:unitsbuilt_P2H][i0,d]*max(min(Years[I] - (Years[i0] + P2H[:Lifetime][d]),1),0) for i0 = 1:I-1) - sum(m[:unitsretired_P2H][i0,d] for i0 = 1:I-1))

        @constraint(m, [I = 2:T_inv, s = 1:sto_elec], m[:unitsretired_STO_ELEC][I,s] <= STO_ELEC[:ExistingUnits][s] + sum(m[:unitsbuilt_STO_ELEC][i0,s] - m[:unitsretired_STO_ELEC][i0,s]  for i0 = 1:I-1))
        @constraint(m, [I = 2:T_inv, s = 1:sto_elec], m[:unitsretired_STO_ELEC][I,s] >= STO_ELEC[:ExistingUnits][s]*max(min(Years[I] - STO_ELEC[:Retirement][s],1),0) + sum(m[:unitsbuilt_STO_ELEC][i0,s]*max(min(Years[I] - (Years[i0] + STO_ELEC[:Lifetime][s]),1),0) for i0 = 1:I-1)  -  sum(m[:unitsretired_STO_ELEC][i0,s]  for i0 = 1:I-1))

        @constraint(m, [I = 2:T_inv, s = 1:sto_heat], m[:unitsretired_STO_HEAT][I,s] <= STO_HEAT[:ExistingUnits][s] + sum(m[:unitsbuilt_STO_HEAT][i0,s] - m[:unitsretired_STO_HEAT][i0,s]  for i0 = 1:I-1))
        @constraint(m, [I = 2:T_inv, s = 1:sto_heat], m[:unitsretired_STO_HEAT][I,s] >= STO_HEAT[:ExistingUnits][s]*max(min(Years[I] - STO_HEAT[:Retirement][s],1),0) + sum(m[:unitsbuilt_STO_HEAT][i0,s]*max(min(Years[I] - (Years[i0] + STO_HEAT[:Lifetime][s]),1),0) for i0 = 1:I-1)  -  sum(m[:unitsretired_STO_HEAT][i0,s]  for i0 = 1:I-1))

        @constraint(m, [I = 2:T_inv, s = 1:sto_gas], m[:unitsretired_STO_GAS][I,s] <= STO_GAS[:ExistingUnits][s] + sum(m[:unitsbuilt_STO_GAS][i0,s] - m[:unitsretired_STO_GAS][i0,s]  for i0 = 1:I-1))
        @constraint(m, [I = 2:T_inv, s = 1:sto_gas], m[:unitsretired_STO_GAS][I,s] >= STO_GAS[:ExistingUnits][s]*max(min(Years[I] - STO_GAS[:Retirement][s],1),0) + sum(m[:unitsbuilt_STO_GAS][i0,s]*max(min(Years[I] - (Years[i0] + STO_GAS[:Lifetime][s]),1),0) for i0 = 1:I-1)  -  sum(m[:unitsretired_STO_GAS][i0,s]  for i0 = 1:I-1))
    end

    #--------- APPLIANCES ---------
    @variable(m, unitsbuilt_APPS[I = 1:T_inv, a = 1:app] >= 0)       # [thousands of units]
    @variable(m, unitsremaining_APPS[I = 1:T_inv, a = 1:app] >= 0)   # [thousands of units]
    @variable(m, unitsretired_APPS[I = 1:T_inv, a = 1:app] >= 0)     # [thousands of units]

    @constraint(m, [I = 1:T_inv, a = 1:app], m[:unitsremaining_APPS][I,a] == APP[:unitsHistorical][I,a] + sum(m[:unitsbuilt_APPS][i0,a] - m[:unitsretired_APPS][i0,a] for i0 = 1:I))
    @constraint(m, [a = 1:app], m[:unitsretired_APPS][1,a] == 0)
    # @constraint(m, [I = 1:T_inv], sum(m[:unitsbuilt_APPS][I,a] for a = 1:app) <= sum(APP[:ApplianceCount][a] - APP[:unitsHistorical][I,a] for a = 1:app))
    @constraint(m, [I = 1:T_inv], sum(m[:unitsremaining_APPS][I,a] for a = 1:app) <= sum(APP[:ApplianceCount][a] for a = 1:app))
    if T_inv > 1
        @constraint(m, [I = 2:T_inv, a = 1:app], m[:unitsretired_APPS][I,a] <= param["forceretire_multiplier"]* (sum(round(APP[:cumFailureProb][a,v,I],digits = 4)*m[:unitsbuilt_APPS][v,a] for v = 1:I-1) - sum(m[:unitsretired_APPS][i0,a] for i0 = 1:I-1)))
        @constraint(m, [I = 2:T_inv, a = 1:app], m[:unitsretired_APPS][I,a] >= sum(round(APP[:cumFailureProb][a,v,I],digits = 4)*m[:unitsbuilt_APPS][v,a] for v = 1:I-1) - sum(m[:unitsretired_APPS][i0,a] for i0 = 1:I-1))
    end

    @constraint(m, [I = 1:T_inv, s = 1:APP[:SERVICES], d = 1:APP[:DIST_GAS]], sum(APP[:DIST_to_GAS][d,a]*APP[:to_SERVICE][a,s]*(m[:unitsremaining_APPS][I,a]) for a = 1:app) >= (1+APP[:ServicesGR][s])^(Years[I]-param["BaseYear"])*sum(APP[:to_SERVICE][a,s]*APP[:DIST_to_GAS][d,a]*APP[:ApplianceCount][a] for a = 1:app))
    @constraint(m, [I = 1:T_inv, s = 1:APP[:SERVICES], d = 1:APP[:DIST_ELEC]], sum(APP[:DIST_to_ELEC][d,a]*APP[:to_SERVICE][a,s]*(m[:unitsremaining_APPS][I,a]) for a = 1:app) >= (1+APP[:ServicesGR][s])^(Years[I]-param["BaseYear"])*sum(APP[:to_SERVICE][a,s]*APP[:DIST_to_ELEC][d,a]*APP[:ApplianceCount][a] for a = 1:app))

    if param["appliance_decisions"] == 0
        @constraint(m, [I = 1:T_inv, a = 1:app], m[:unitsremaining_APPS][I,a] >= ((1+APP[:ForecastGR][a])^(Years[I]-param["BaseYear"]))*APP[:ApplianceCount][a])
    end

    return nothing
end