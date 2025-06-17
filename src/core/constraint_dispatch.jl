using JuMP

function add_constraint_dispatch!(m::Model, param, cons, data)

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
    RepDays = CLUSTER[:repdays]


    @variable(m, generation[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen] >= 0)         # [MWh]
    @variable(m, commit_GEN[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen] >= 0)         # [no. units]
    @variable(m, startup_GEN[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen] >= 0)        # [no. units]
    @variable(m, shutdown_GEN[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen] >= 0)       # [no. units]

    @variable(m, P2G_dispatch[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g] >= 0)       # [MWh]
    @variable(m, commit_P2G[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g] >= 0)         # [no. units]
    @variable(m, startup_P2G[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g] >= 0)        # [no. units]
    @variable(m, shutdown_P2G[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g] >= 0)       # [no. units]

    @variable(m, P2H_dispatch[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h] >= 0)       # [MWh]
    @variable(m, commit_P2H[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h] >= 0)         # [no. units]
    @variable(m, startup_P2H[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h] >= 0)        # [no. units]
    @variable(m, shutdown_P2H[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h] >= 0)       # [no. units]

    ### Startup and shutdown events
    # See Eq. 2.22a/2.22e in Von Wald thesis
    ################################################################################
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen], m[:commit_GEN][I,T,t,g] <= GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i,g] - m[:unitsretired_GEN][i,g] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen], m[:startup_GEN][I,T,t,g] <= GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i,g] - m[:unitsretired_GEN][i,g] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen], m[:shutdown_GEN][I,T,t,g] <= GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i,g] - m[:unitsretired_GEN][i,g] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 2:t_ops, g = 1:gen], m[:commit_GEN][I,T,t,g] == m[:commit_GEN][I,T,t-1,g] + m[:startup_GEN][I,T,t,g] - m[:shutdown_GEN][I,T,t,g])

    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g], m[:commit_P2G][I,T,t,d] <= P2G[:ExistingUnits][d] + sum(m[:unitsbuilt_P2G][i,d] - m[:unitsretired_P2G][i,d] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g], m[:startup_P2G][I,T,t,d] <= P2G[:ExistingUnits][d] + sum(m[:unitsbuilt_P2G][i,d] - m[:unitsretired_P2G][i,d] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g], m[:shutdown_P2G][I,T,t,d] <= P2G[:ExistingUnits][d] + sum(m[:unitsbuilt_P2G][i,d] - m[:unitsretired_P2G][i,d] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 2:t_ops, d = 1:p2g], m[:commit_P2G][I,T,t,d] == m[:commit_P2G][I,T,t-1,d] + m[:startup_P2G][I,T,t,d] - m[:shutdown_P2G][I,T,t,d])

    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h], m[:commit_P2H][I,T,t,d] <= P2H[:ExistingUnits][d] + sum(m[:unitsbuilt_P2H][i,d] - m[:unitsretired_P2H][i,d] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h], m[:startup_P2H][I,T,t,d] <= P2H[:ExistingUnits][d] + sum(m[:unitsbuilt_P2H][i,d] - m[:unitsretired_P2H][i,d] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h], m[:shutdown_P2H][I,T,t,d] <= P2H[:ExistingUnits][d] + sum(m[:unitsbuilt_P2H][i,d] - m[:unitsretired_P2H][i,d] for i = 1:I))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 2:t_ops, d = 1:p2h], m[:commit_P2H][I,T,t,d] == m[:commit_P2H][I,T,t-1,d] + m[:startup_P2H][I,T,t,d] - m[:shutdown_P2H][I,T,t,d])

    ### Min and Max generation constraints
    # See Eq. 2.22b/2.22c in Von Wald thesis
    ################################################################################
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen], m[:generation][I,T,t,g] >= GEN[:Pmin][g]*GEN[:UnitSize][g]*m[:commit_GEN][I,T,t,g])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen], m[:generation][I,T,t,g] <= GEN[:Pmax][g]*GEN[:UnitSize][g]*m[:commit_GEN][I,T,t,g])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g], m[:P2G_dispatch][I,T,t,d] >= P2G[:Pmin][d]*P2G[:UnitSize][d]*m[:commit_P2G][I,T,t,d])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2g], m[:P2G_dispatch][I,T,t,d] <= P2G[:Pmax][d]*P2G[:UnitSize][d]*m[:commit_P2G][I,T,t,d])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h], m[:P2H_dispatch][I,T,t,d] >= P2H[:Pmin][d]*P2H[:UnitSize][d]*m[:commit_P2H][I,T,t,d])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, d = 1:p2h], m[:P2H_dispatch][I,T,t,d] <= P2H[:Pmax][d]*P2H[:UnitSize][d]*m[:commit_P2H][I,T,t,d])

    ### Constraints on fixed profile generation resources
    # See Eq. 2.22d in Von Wald thesis
    ###############################################################################
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen], m[:generation][I,T,t,g] <= PROF[:VRE][T,t,g]*GEN[:UnitSize][g]*(GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i,g] - m[:unitsretired_GEN][i,g] for i = 1:I)))
    @variable(m, curtailmentRE[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen] >= 0)
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, g = 1:gen], curtailmentRE[I,T,t,g] == GEN[:isRenewable][g]*(PROF[:VRE][T,t,g]*GEN[:UnitSize][g]*(GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i,g] - m[:unitsretired_GEN][i,g] for i = 1:I)) - m[:generation][I,T,t,g]))

    ### Ramping constraint
    # See Eq. 2.23 in Von Wald thesis
    ###############################################################################
    if t_ops > 1
        minimax = min.(GEN[:Pmax], max.(GEN[:Pmin],GEN[:RampDown]))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 2:t_ops, g = 1:gen], m[:generation][I,T,t-1,g]-m[:generation][I,T,t,g] <= GEN[:RampDown][g]*GEN[:UnitSize][g]*(m[:commit_GEN][I,T,t,g]-m[:startup_GEN][I,T,t,g]) - GEN[:Pmin][g]*GEN[:UnitSize][g]*m[:startup_GEN][I,T,t,g] + minimax[g]*GEN[:UnitSize][g]*m[:shutdown_GEN][I,T,t,g])
        minimax = min.(GEN[:Pmax], max.(GEN[:Pmin],GEN[:RampUp]))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 2:t_ops, g = 1:gen], m[:generation][I,T,t,g]-m[:generation][I,T,t-1,g] <= GEN[:RampUp][g]*GEN[:UnitSize][g]*(m[:commit_GEN][I,T,t,g]-m[:startup_GEN][I,T,t,g]) - GEN[:Pmin][g]*GEN[:UnitSize][g]*m[:shutdown_GEN][I,T,t,g] + minimax[g]*GEN[:UnitSize][g]*m[:startup_GEN][I,T,t,g])
    end

    ### Min up time/down time constraints
    # See Eq. 2.25/2.26 in Von Wald thesis
    ###############################################################################
    for g = 1:gen
        if t_ops > GEN[:MinUp][g]
            for t = Int(GEN[:MinUp][g]+1):t_ops
                @constraint(m, [I = 1:T_inv, T = 1:T_ops], m[:commit_GEN][I,T,t,g] >= sum(m[:startup_GEN][I,T,t0,g] for t0 = (t-Int(GEN[:MinUp][g])):t))
            end
        end
    end
    for g = 1:gen
        if t_ops > GEN[:MinDown][g]
            for t = Int(GEN[:MinDown][g]+1):t_ops
                @constraint(m, [I = 1:T_inv, T = 1:T_ops], GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i,g] - m[:unitsretired_GEN][i,g] for i = 1:I) - m[:commit_GEN][I,T,t,g] >= sum(m[:shutdown_GEN][I,T,t0,g] for t0 = (t-GEN[:MinDown][g]):t))
            end
        end
    end

    ### Generator operational constraints across linked time periods
    # See Eq. 2.24/2.25/2.26 in Von Wald thesis
    ###############################################################################
    if param["LINKED_PERIODS_GENOPS"] == 1
        for g = 1:gen
            for i = 2:Int(param["Periods_Per_Year"])
            # Ramping constraint
                minmax = min(GEN[:Pmax][g], max(GEN[:Pmin][g],GEN[:RampDown][g]))
                @constraint(m, [I = 1:T_inv], m[:generation][I,Int(RepDays[I,i-1]),t_ops,g]-m[:generation][I,Int(RepDays[I,i]),1,g] <= GEN[:RampDown][g]*GEN[:UnitSize][g]*(m[:commit_GEN][I,Int(RepDays[I,i]),1,g]-m[:startup_GEN][I,Int(RepDays[I,i]),1,g]) - GEN[:Pmin][g]*GEN[:UnitSize][g]*m[:startup_GEN][I,Int(RepDays[I,i]),1,g] + minmax*GEN[:UnitSize][g]*m[:shutdown_GEN][I,Int(RepDays[I,i]),1,g])
                minmax = min(GEN[:Pmax][g], max(GEN[:Pmin][g],GEN[:RampUp][g]))
                @constraint(m, [I = 1:T_inv], m[:generation][I,Int(RepDays[I,i]),1,g]-m[:generation][I,Int(RepDays[I,i-1]),t_ops,g] <= GEN[:RampUp][g]*GEN[:UnitSize][g]*(m[:commit_GEN][I,Int(RepDays[I,i]),1,g]-m[:startup_GEN][I,Int(RepDays[I,i]),1,g]) - GEN[:Pmin][g]*GEN[:UnitSize][g]*m[:shutdown_GEN][I,Int(RepDays[I,i]),1,g] + minmax*GEN[:UnitSize][g]*m[:startup_GEN][I,Int(RepDays[I,i]),1,g])
            end
            # Min up time/down time constraints
            firstpd_up = Int(round(GEN[:MinUp][g]/t_ops)+2)
            X = repeat(collect(range(t_ops,stop = 1,length = t_ops)), outer = [firstpd_up+3])
            Y = repeat(collect(range(0, stop = 24, length = 25)), inner = [t_ops])
            for i = firstpd_up:Int(param["Periods_Per_Year"])
                for t = 1:t_ops
                    @constraint(m, [I = 1:T_inv], m[:commit_GEN][I,Int(RepDays[I,i]),t,g] >= sum(m[:startup_GEN][I,Int(RepDays[I,Int(i-Y[Int(t0-t+t_ops)])]),Int(X[Int(t0+t_ops-t)]),g] for t0 = 1:GEN[:MinUp][g]))
                end
            end
            firstpd_down = Int(round(GEN[:MinDown][g]/t_ops)+2)
            X = repeat(collect(range(t_ops,stop = 1,length = t_ops)), outer = [firstpd_up+3])
            Y = repeat(collect(range(0, stop = 24, length = 25)), inner = [t_ops])
            for i = firstpd_down:Int(param["Periods_Per_Year"])
                for t = 1:param["HOURS_PER_PERIOD"]
                    @constraint(m, [I = 1:T_inv], GEN[:ExistingUnits][g] + sum(m[:unitsbuilt_GEN][i0,g] - m[:unitsretired_GEN][i0,g] for i0 = 1:I) - m[:commit_GEN][I,Int(RepDays[I,i]),t,g] >= sum(m[:shutdown_GEN][I,Int(RepDays[I,Int(i-Y[Int(t0-t+t_ops)])]),Int(X[Int(t0+t_ops-t)]),g] for t0 = 1:GEN[:MinDown][g]))
                end
            end
        end
    end


    ###############################################################################
    ### Dispatch of storage
    # See Eq. 2.51-2.55 in Von Wald thesis
    ###############################################################################
    @variable(m, storedEnergy_ELEC[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops+1, s = 1:sto_elec] >= 0)       # [MWh]
    @variable(m, charging_ELEC[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec] >= 0)             # [MW]
    @variable(m, discharging_ELEC[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec] >= 0)          # [MW]

    @variable(m, storedEnergy_GAS[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops+1, s = 1:sto_gas] >= 0)         # [MWh]
    @variable(m, charging_GAS[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas] >= 0)               # [MW]
    @variable(m, discharging_GAS[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas] >= 0)            # [MW]

    @variable(m, storedEnergy_HEAT[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops+1, s = 1:sto_heat] >= 0)       # [MWh]
    @variable(m, charging_HEAT[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat] >= 0)             # [MW]
    @variable(m, discharging_HEAT[I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat] >= 0)          # [MW]

    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:storedEnergy_ELEC][I,T,t+1,s] == m[:storedEnergy_ELEC][I,T,t,s] + STO_ELEC[:ChargeETA][s]*m[:charging_ELEC][I,T,t,s] - (1/STO_ELEC[:DischargeETA][s])*m[:discharging_ELEC][I,T,t,s]-STO_ELEC[:LossETA][s]*m[:storedEnergy_ELEC][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops+1, s = 1:sto_elec], m[:storedEnergy_ELEC][I,T,t,s] <= STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I))*STO_ELEC[:Duration][s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:charging_ELEC][I,T,t,s] <= (1/STO_ELEC[:ChargeETA][s])*STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I)))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:charging_ELEC][I,T,t,s] <= STO_ELEC[:Duration][s]*STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I)) - m[:storedEnergy_ELEC][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:discharging_ELEC][I,T,t,s] <= STO_ELEC[:DischargeETA][s]*STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I)))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:discharging_ELEC][I,T,t,s] <= m[:storedEnergy_ELEC][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:discharging_ELEC][I,T,t,s]/STO_ELEC[:DischargeETA][s] + STO_ELEC[:ChargeETA][s]*m[:charging_ELEC][I,T,t,s] <= STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I)))

    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:storedEnergy_GAS][I,T,t+1,s] == m[:storedEnergy_GAS][I,T,t,s] + STO_GAS[:ChargeETA][s]*m[:charging_GAS][I,T,t,s] - (1/STO_GAS[:DischargeETA][s])*m[:discharging_GAS][I,T,t,s]-STO_GAS[:LossETA][s]*m[:storedEnergy_GAS][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops+1, s = 1:sto_gas], m[:storedEnergy_GAS][I,T,t,s] <= STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s] for i = 1:I))*STO_GAS[:Duration][s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:charging_GAS][I,T,t,s] <= (1/STO_GAS[:ChargeETA][s])*STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s] for i = 1:I)))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:charging_GAS][I,T,t,s] <= STO_GAS[:Duration][s]*STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s] for i = 1:I)) - m[:storedEnergy_GAS][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:discharging_GAS][I,T,t,s] <= STO_GAS[:DischargeETA][s]*STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s] for i = 1:I)))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:discharging_GAS][I,T,t,s] <= m[:storedEnergy_GAS][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:discharging_GAS][I,T,t,s]/STO_GAS[:DischargeETA][s] + STO_GAS[:ChargeETA][s]*m[:charging_GAS][I,T,t,s] <= STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s] for i = 1:I)))

    ## To limit flexible charge/discharge associated with gas storage
    # See Eq. 2.52 in Von Wald thesis
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops-1, s = 1:sto_gas], m[:charging_GAS][I,T,t,s] == m[:charging_GAS][I,T,t+1,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops-1, s = 1:sto_gas], m[:discharging_GAS][I,T,t,s] == m[:discharging_GAS][I,T,t+1,s])

    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:storedEnergy_HEAT][I,T,t+1,s] == m[:storedEnergy_HEAT][I,T,t,s] + STO_HEAT[:ChargeETA][s]*m[:charging_HEAT][I,T,t,s] - (1/STO_HEAT[:DischargeETA][s])*m[:discharging_HEAT][I,T,t,s]-STO_HEAT[:LossETA][s]*m[:storedEnergy_HEAT][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops+1, s = 1:sto_heat], m[:storedEnergy_HEAT][I,T,t,s] <= STO_HEAT[:UnitSize][s]*(STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i,s] - m[:unitsretired_STO_HEAT][i,s] for i = 1:I)))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:charging_HEAT][I,T,t,s] <= (1/STO_HEAT[:ChargeETA][s]) * STO_HEAT[:ChargeRate][s] * (STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i,s] - m[:unitsretired_STO_HEAT][i,s] for i = 1:I)))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:charging_HEAT][I,T,t,s] <= STO_HEAT[:UnitSize][s] * (STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i,s] - m[:unitsretired_STO_HEAT][i,s] for i = 1:I)) - m[:storedEnergy_HEAT][I,T,t,s])
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:discharging_HEAT][I,T,t,s] <= STO_HEAT[:DischargeETA][s] * STO_HEAT[:DischargeRate][s] * (STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i,s] - m[:unitsretired_STO_HEAT][i,s] for i = 1:I)))
    @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:discharging_HEAT][I,T,t,s] <= m[:storedEnergy_HEAT][I,T,t,s])

    ### Constraints for linking energy storage across representative periods
    # See Eq. 2.56-2.59 in Von Wald thesis
    ################################################################################
    if param["LINKED_PERIODS_STORAGE"] == 0
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_elec], m[:storedEnergy_ELEC][I,T,1,s] == m[:storedEnergy_ELEC][I,T,t_ops+1,s])       # [MWh]
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_gas], m[:storedEnergy_GAS][I,T,1,s] == m[:storedEnergy_GAS][I,T,t_ops+1,s])       # [MWh]
    elseif param["LINKED_PERIODS_STORAGE"] == 1
        # ELECTRIC
        @variable(m, MinSOC_ELEC[I = 1:T_inv, T = 1:T_ops, s = 1:sto_elec] >= 0)
        @variable(m, MaxSOC_ELEC[I = 1:T_inv, T = 1:T_ops, s = 1:sto_elec] >= 0)
        @variable(m, SOCTracked_ELEC[I = 1:T_inv, d = 1:Int(param["Periods_Per_Year"]), s = 1:sto_elec] >= 0)

        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_elec], m[:MinSOC_ELEC][I,T,s] <= STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I))*STO_ELEC[:Duration][s])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_elec], m[:MaxSOC_ELEC][I,T,s] <= STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I))*STO_ELEC[:Duration][s])
        @constraint(m, [I = 1:T_inv, d = 1:Int(param["Periods_Per_Year"]), s = 1:sto_elec], m[:SOCTracked_ELEC][I,d,s] <=  STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I))*STO_ELEC[:Duration][s])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:MinSOC_ELEC][I,T,s] <= m[:storedEnergy_ELEC][I,T,t,s])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_elec], m[:MaxSOC_ELEC][I,T,s] >= m[:storedEnergy_ELEC][I,T,t,s])
        for i = 1:Int(param["Periods_Per_Year"])
            @constraint(m, [I = 1:T_inv, s = 1:sto_elec], m[:SOCTracked_ELEC][I,i,s] == m[:storedEnergy_ELEC][I,Int(RepDays[I,1]),1,s] + sum(m[:storedEnergy_ELEC][I,Int(RepDays[I,t]),t_ops+1,s] - m[:storedEnergy_ELEC][I,Int(RepDays[I,t]),1,s] for t = 1:i))
            if i < param["Periods_Per_Year"]
                @constraint(m, [I = 1:T_inv, s = 1:sto_elec], m[:SOCTracked_ELEC][I,i,s] + (m[:MaxSOC_ELEC][I,Int(RepDays[I,i+1]),s] - m[:storedEnergy_ELEC][I,Int(RepDays[I,i+1]),1,s]) <=  STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i0,s] - m[:unitsretired_STO_ELEC][i0,s] for i0 = 1:I))*STO_ELEC[:Duration][s])
                @constraint(m, [I = 1:T_inv, s = 1:sto_elec], m[:SOCTracked_ELEC][I,i,s] - (m[:storedEnergy_ELEC][I,Int(RepDays[I,i+1]),1,s] - m[:MinSOC_ELEC][I,Int(RepDays[I,i+1]),s]) >= 0)
            end
        end
        @constraint(m, [I = 1:T_inv, s = 1:sto_elec], m[:SOCTracked_ELEC][I,Int(param["Periods_Per_Year"]),s] == m[:storedEnergy_ELEC][I,Int(RepDays[I,1]),1,s])
        @constraint(m, [I = 1:T_inv, s = 1:sto_elec], m[:SOCTracked_ELEC][I,Int(param["Periods_Per_Year"]),s] == param["SOC_fraction"]*STO_ELEC[:UnitSize][s]*(STO_ELEC[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_ELEC][i,s] - m[:unitsretired_STO_ELEC][i,s] for i = 1:I))*STO_ELEC[:Duration][s])

        
        # GAS
        @variable(m, MinSOC_GAS[I = 1:T_inv, T = 1:T_ops, s = 1:sto_gas] >= 0)
        @variable(m, MaxSOC_GAS[I = 1:T_inv, T = 1:T_ops, s = 1:sto_gas] >= 0)
        @variable(m, SOCTracked_GAS[I = 1:T_inv, d = 1:Int(param["Periods_Per_Year"]), s = 1:sto_gas] >= 0)

        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_gas], m[:MinSOC_GAS][I,T,s] <= STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s]  for i = 1:I))*STO_GAS[:Duration][s])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_gas], m[:MaxSOC_GAS][I,T,s] <= STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s]  for i = 1:I))*STO_GAS[:Duration][s])
        @constraint(m, [I = 1:T_inv, d = 1:Int(param["Periods_Per_Year"]), s = 1:sto_gas], m[:SOCTracked_GAS][I, d, s] <= STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i,s] - m[:unitsretired_STO_GAS][i,s]  for i = 1:I))*STO_GAS[:Duration][s])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:MinSOC_GAS][I,T,s] <= m[:storedEnergy_GAS][I,T,t,s])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_gas], m[:MaxSOC_GAS][I,T,s] >= m[:storedEnergy_GAS][I,T,t,s])
        for i = 1:Int(param["Periods_Per_Year"])
            @constraint(m, [I = 1:T_inv, s = 1:sto_gas], m[:SOCTracked_GAS][I,i,s] == m[:storedEnergy_GAS][I,Int(RepDays[I,1]),1,s] + sum(m[:storedEnergy_GAS][I,Int(RepDays[I,t]),t_ops+1,s] - m[:storedEnergy_GAS][I,Int(RepDays[I,t]),1,s] for t = 1:i))
            if i < param["Periods_Per_Year"]
                @constraint(m, [I = 1:T_inv, s = 1:sto_gas], m[:SOCTracked_GAS][I,i,s] + (m[:MaxSOC_GAS][I,Int(RepDays[I,i+1]),s] - m[:storedEnergy_GAS][I,Int(RepDays[I,i+1]),1,s]) <=  STO_GAS[:UnitSize][s]*(STO_GAS[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_GAS][i0,s] - m[:unitsretired_STO_GAS][i0,s] for i0 = 1:I))*STO_GAS[:Duration][s])
                @constraint(m, [I = 1:T_inv, s = 1:sto_gas], m[:SOCTracked_GAS][I,i,s] - (m[:storedEnergy_GAS][I,Int(RepDays[I,i+1]),1,s] - m[:MinSOC_GAS][I,Int(RepDays[I,i+1]),s]) >= 0)
            end
        end
        @constraint(m, [I = 1:T_inv, s = 1:sto_gas], m[:SOCTracked_GAS][I,Int(param["Periods_Per_Year"]),s] == m[:storedEnergy_GAS][I,Int(RepDays[I,1]),1,s])
        @constraint(m, [I = 1:T_inv, d = 1, s = 1:sto_gas], m[:SOCTracked_GAS][I,d,s] == STO_GAS[:InitialStorage][s])

        # HEAT
        @variable(m, MinSOC_HEAT[I = 1:T_inv, T = 1:T_ops, s = 1:sto_heat] >= 0)
        @variable(m, MaxSOC_HEAT[I = 1:T_inv, T = 1:T_ops, s = 1:sto_heat] >= 0)
        @variable(m, SOCTracked_HEAT[I = 1:T_inv, d = 1:Int(param["Periods_Per_Year"]), s = 1:sto_heat] >= 0)

        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_heat], m[:MinSOC_HEAT][I,T,s] <= STO_HEAT[:UnitSize][s]*(STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i,s] - m[:unitsretired_STO_HEAT][i,s] for i = 1:I)))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, s = 1:sto_heat], m[:MaxSOC_HEAT][I,T,s] <= STO_HEAT[:UnitSize][s]*(STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i,s] - m[:unitsretired_STO_HEAT][i,s] for i = 1:I)))
        @constraint(m, [I = 1:T_inv, d = 1:Int(param["Periods_Per_Year"]), s = 1:sto_heat], m[:SOCTracked_HEAT][I,d,s] <= STO_HEAT[:UnitSize][s]*(STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i,s] - m[:unitsretired_STO_HEAT][i,s] for i = 1:I)))
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:MinSOC_HEAT][I,T,s] <= m[:storedEnergy_HEAT][I,T,t,s])
        @constraint(m, [I = 1:T_inv, T = 1:T_ops, t = 1:t_ops, s = 1:sto_heat], m[:MaxSOC_HEAT][I,T,s] >= m[:storedEnergy_HEAT][I,T,t,s])
        for i = 1:Int(param["Periods_Per_Year"])
            @constraint(m, [I = 1:T_inv, s = 1:sto_heat], m[:SOCTracked_HEAT][I,i,s] == m[:storedEnergy_HEAT][I,Int(RepDays[I,1]),1,s] + sum(m[:storedEnergy_HEAT][I,Int(RepDays[I,t]),t_ops+1,s] - m[:storedEnergy_HEAT][I,Int(RepDays[I,t]),1,s] for t = 1:i))
            if i < param["Periods_Per_Year"]
                @constraint(m, [I = 1:T_inv, s = 1:sto_heat], m[:SOCTracked_HEAT][I,i,s] + (m[:MaxSOC_HEAT][I,Int(RepDays[I,i+1]),s] - m[:storedEnergy_HEAT][I,Int(RepDays[I,i+1]),1,s]) <=  STO_HEAT[:UnitSize][s]*(STO_HEAT[:ExistingUnits][s]+sum(m[:unitsbuilt_STO_HEAT][i0,s] - m[:unitsretired_STO_HEAT][i0,s] for i0 = 1:I)))
                @constraint(m, [I = 1:T_inv, s = 1:sto_heat], m[:SOCTracked_HEAT][I,i,s] - (m[:storedEnergy_HEAT][I,Int(RepDays[I,i+1]),1,s] - m[:MinSOC_HEAT][I,Int(RepDays[I,i+1]),s]) >= 0)
            end
        end
        @constraint(m, [I = 1:T_inv, s = 1:sto_heat], m[:SOCTracked_HEAT][I,Int(param["Periods_Per_Year"]),s] == m[:storedEnergy_HEAT][I,Int(RepDays[I,1]),1,s])
    end

    return nothing
end