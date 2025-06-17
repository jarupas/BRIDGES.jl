using BRIDGES
using Test

"""
    runtests.jl

This test script runs the unit tests for the BRIDGES.jl package.

**Note on Gurobi tests:**  
Some tests require the commercial Gurobi solver, which needs a valid license and installation.
To avoid failures on continuous integration (CI) servers, these tests are skipped by default in CI.

- In CI, `RUN_GUROBI_TESTS` is set to `"false"` in the GitHub Actions workflow.
- Locally, you can enable Gurobi tests by running:

    ```bash
    RUN_GUROBI_TESTS=true julia --project -e 'using Pkg; Pkg.test()'
    ```

This allows most tests to run anywhere, while still supporting optional Gurobi functionality when desired.
"""
@testset "Presolve tests" begin
    BRIDGES.solve_optimization_problem("ca",test_mode=true)
end

if get(ENV, "RUN_GUROBI_TESTS", "false") == "true"
    @testset "Solving optimization problem" begin
        BRIDGES.solve_optimization_problem("ca")
    end
else
    @info "Skipping Gurobi tests: RUN_GUROBI_TESTS is false or unset"
end