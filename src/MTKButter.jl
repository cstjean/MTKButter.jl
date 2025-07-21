__precompile__(false)  # apparently even the __init__ piracy is problematic
module MTKButter

using ModelingToolkit, MacroTools
import ModelingToolkit as MTK
using Accessors, MLStyle, OrderedCollections
using MacroTools: postwalk

include("bmodel.jl")

pirate_mtk() =
    # PIRACY! But it should be benign.
    # I'd like to use `nothing`, but MTK doesn't like it
    @eval MTK (m::Model)(args...; name=:unnamed, kw...) = m.f(args...; name, kw...)

function __init__()
    pirate_mtk()
end

end
