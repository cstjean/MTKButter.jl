module MTKButter

using ModelingToolkit, MacroTools
import ModelingToolkit as MTK
using Accessors, MLStyle, OrderedCollections

include("bmodel.jl")

function __init__()
    # PIRACY! But it should be benign.
    # I'd like to use `nothing`, but MTK doesn't like it
    @eval MTK (m::Model)(args...; name=:unspecified, kw...) = m.f(args...; name, kw...)
end

end
