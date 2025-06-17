import Pkg
Pkg.add("DataFrames"); Pkg.add("CSV"); Pkg.add("Clustering")
Pkg.add("Distances"); Pkg.add("Gurobi"); Pkg.add("Tables")
Pkg.add("DelimitedFiles"); Pkg.add("Dates"); Pkg.add("Random")
Pkg.add("YAML"); Pkg.add("JLD")
Pkg.add(Pkg.PackageSpec(;name="Gurobi", version="1.1.0"))
Pkg.add("JuMP")
Pkg.add(Pkg.PackageSpec(;name="JuMP", version="1.7.0"))

using DataFrames, CSV, Tables, Clustering, Distances, Dates, Random, YAML
using Gurobi, JuMP, JLD

# Include other source files into this module
include("core/parameters.jl")
include("core/import.jl")
include("core/cluster.jl")
include("core/constraint.jl")
include("core/objective.jl")
include("core/optimize.jl")
include("core/export.jl")

case = "ca"

# Define parameters
param, cons = load_parameters(case)

# Import and cluster data
data = load_data(param, cons)

cluster!(param, cons, data)

# Create a new optimization model
model = Model(optimizer_with_attributes(Gurobi.Optimizer,"Threads" => 8,"BarHomogeneous" => 1,"ScaleFlag"=>2, "FeasibilityTol"=> 0.005, 
"LogToConsole" => 1, "ScaleFlag" => 1, "OptimalityTol" => 0.001, "BarConvTol"=> 0.0001, "Method"=> 2, "Crossover"=> 0))

# Define the constraints
assemble_constraints!(model, param, cons, data)

# Define the objective function
define_objective!(model, param, cons, data)

# Solve the optimization problem
optimize_model(model)

# Get the results
results = get_results(model, param, cons, data)

top_dir, ts = mk_output_dir(case)
println("Saving to: ", top_dir, " completed at ", ts)
save("/$(top_dir)/results.jld", "results", results)

