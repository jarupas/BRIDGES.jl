using JuMP
using Gurobi

function optimize_model(model::Model)
    optimize!(model)

    # Check the solution status
    if termination_status(model) == OPTIMAL
        println("Solution is optimal!")
    else
        println("Solution status: ", termination_status(model))
    end
    return nothing
end