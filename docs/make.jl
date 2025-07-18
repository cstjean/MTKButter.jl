using MTKButter
using Documenter

DocMeta.setdocmeta!(MTKButter, :DocTestSetup, :(using MTKButter); recursive = true)

const page_rename = Dict("developer.md" => "Developer docs") # Without the numbers
const numbered_pages = [
    file for file in readdir(joinpath(@__DIR__, "src")) if
    file != "index.md" && splitext(file)[2] == ".md"
]

makedocs(;
    modules = [MTKButter],
    authors = "cstjean",
    repo = "https://github.com/cstjean/MTKButter.jl/blob/{commit}{path}#{line}",
    sitename = "MTKButter.jl",
    format = Documenter.HTML(; canonical = "https://cstjean.github.io/MTKButter.jl"),
    pages = ["index.md"; numbered_pages],
)

deploydocs(; repo = "github.com/cstjean/MTKButter.jl")
