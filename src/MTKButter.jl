module MTKButter

using ModelingToolkit, MacroTools
import ModelingToolkit as MTK
using Accessors, MLStyle, OrderedCollections
using MacroTools: postwalk

include("bmodel.jl")

function __init__()
    # PIRACY! But it should be benign.
    # I'd like to use `nothing`, but MTK doesn't like it
    @eval MTK (m::Model)(args...; name=:unnamed, kw...) = m.f(args...; name, kw...)
end

end
