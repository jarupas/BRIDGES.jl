using BRIDGES
using Test
using JuMP

# =============================================================================
# runtests.jl
#
# This test script runs the unit tests for the BRIDGES.jl package.
#
# Note on Gurobi tests:
# Some tests require the commercial Gurobi solver, which needs a valid license
# and installation. To avoid failures on continuous integration (CI) servers,
# these tests are skipped by default in CI.
#
# In CI, the environment variable `RUN_GUROBI_TESTS` is set to "false".
# Locally, you can enable Gurobi tests by running:
#
#     RUN_GUROBI_TESTS=true julia --project -e 'using Pkg; Pkg.test()'
#
# =============================================================================

@testset "BRIDGES package tests" begin
    # === Shared setup ===
    param, cons, data = redirect_stdout(devnull) do
        p, c = BRIDGES.load_parameters("test")
        d = BRIDGES.load_data(p, c)
        BRIDGES.cluster!(p, c, d)
        (p, c, d)
    end

    # === Test: Loading parameters ===
    @testset "Loading parameters" begin
        @test param isa Dict
        @test cons isa Dict
        @test haskey(param, "T_inv")
        @test haskey(cons, "MJ_PER_MWh")
    end

    # === Test: Loading data ===
    @testset "Loading data" begin
        @test haskey(data[:GEN], :FUEL)
    end

    # === Test: Clustering ===
    @testset "Clustering" begin
        @test haskey(data[:CLUSTER], :medoids)
    end

    # === Test: Solving optimization problem (conditional) ===
    if get(ENV, "RUN_GUROBI_TESTS", "true") == "true"
        @testset "Solving optimization problem" begin
            redirect_stdout(devnull) do
                model = BRIDGES.solve_optimization_problem("test", false)
                status = string(JuMP.termination_status(model))
                @test status == "OPTIMAL"
            end
        end
    else
        @info "Skipping Gurobi tests: RUN_GUROBI_TESTS is false or unset"
    end
end