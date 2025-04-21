using BridgesCA
using Documenter

DocMeta.setdocmeta!(BridgesCA, :DocTestSetup, :(using BridgesCA); recursive=true)

makedocs(;
    modules=[BridgesCA],
    authors="jarupas",
    sitename="BridgesCA.jl",
    format=Documenter.HTML(;
        canonical="https://jarupas.github.io/BridgesCA.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/jarupas/BridgesCA.jl",
    devbranch="main",
)
