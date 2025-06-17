using BRIDGES
using Documenter

DocMeta.setdocmeta!(BRIDGES, :DocTestSetup, :(using BRIDGES); recursive=true)

makedocs(;
    modules=[BRIDGES],
    authors="jarupas",
    sitename="BRIDGES.jl",
    format=Documenter.HTML(;
        canonical="https://jarupas.github.io/BRIDGES.jl",
        edit_link="main",
        assets=String[],
        sidebar_sitename = false,
    ),
    pages=[
        "Home" => "index.md",
        "Getting Started" => [
            "Introduction" => "introduction.md",
            "Project Structure" => "intro_structure.md",
            "Introduction to Snakemake" => "intro_snakemake.md",
            "Introduction to Sherlock" => "intro_sherlock.md",
            "Introduction to MkDocs" => "intro_mkdocs.md",
        ],
        "Model Data" => [
            "Supply" => "data_supply.md",
            "Residential Sector" => "data_residential.md",
            "Commercial Sector" => "data_commercial.md",
            "Network Topology" => "data_network.md",
        ],
        "Model Formulations" => [
            "Parameters and Data Imports" => "model_parameters.md",
            "Constraints" => "model_constraints.md",
            "Objective" => "model_objective.md",
        ],
        "Publications" => "publications.md",
    ],
)

deploydocs(;
    repo="github.com/jarupas/BRIDGES.jl",
    devbranch="main",
)
