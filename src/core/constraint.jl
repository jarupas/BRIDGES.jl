using JuMP

include("constraint_capacity.jl")
include("constraint_dispatch.jl")
include("constraint_flow.jl")
include("constraint_policy.jl")

function assemble_constraints!(model, param, cons, data)
    
    add_constraint_capacity!(model, param, cons, data)
    add_constraint_dispatch!(model, param, cons, data)
    add_constraint_flow!(model, param, cons, data)
    add_constraint_policy!(model, param, cons, data)

    return nothing
end