export mtkbmodel

struct PreSystem
    equations_fn::Function
    t
    variables_dict::OrderedDict{Symbol, Any}
    parameters_dict::OrderedDict{Symbol, Any}
    name
    description
    systems_dict::OrderedDict{Symbol, Any}
    gui_metadata
    continuous_events
    discrete_events
    defaults
    costs
    constraints # TODO: turn into `constraints_fn`
    consolidate
end
function PreSystem(equations_fn::Function, t, variables, parameters;
                   name, description, systems_dict, gui_metadata, continuous_events, discrete_events, defaults, costs,
                   constraints, consolidate)
    return PreSystem(equations_fn, t,
                     Dict(Symbol(v)=>v for v in variables),
                     Dict(Symbol(p)=>p for p in parameters),
                     name, description, systems_dict, gui_metadata, continuous_events, discrete_events, defaults, costs,
                     constraints, consolidate)
end
MTK.rename(ps::PreSystem, name::Symbol) = @set ps.name = name
MTK.rename(pss::Vector{PreSystem}, name::Symbol) =
    [MTK.rename(ps, Symbol(name, :_, i)) for (i, ps) in enumerate(pss)]
function Base.show(io::IO, mime::MIME"text/plain", ps::PreSystem)
    println(io, "--- PreSystem for ---")
    show(io, mime, System(ps))
end

"""
```jldoctest
julia> MTKButter.array_prefix(:my_comps_3)
:my_comps
```
Returns `nothing` otherwise.
"""
function array_prefix(s::Symbol)
    i = findlast('_', string(s))
    return i === nothing ? nothing : Symbol(string(s)[1:i-1])
end
function array_suffix(s::Symbol)
    i = findlast('_', string(s))
    return i === nothing ? nothing : tryparse(Int, string(s)[i+1:end])
end

component_lens(s::Symbol) = IndexLens(array_suffix(s)) ∘ PropertyLens(array_prefix(s))

Base.getproperty(ps::PreSystem, prop::Symbol) =
    hasfield(PreSystem, prop) ? getfield(ps, prop) :
    haskey(ps.systems_dict, prop) ? MTK.rename(ps.systems_dict[prop], Symbol(ps.name, '₊', prop)) :
    getproperty(System(ps), prop)  # inefficient!

function (Accessors.set(ps::PreSystem, optic::ComposedFunction{O, PropertyLens{F}}, val)::PreSystem) where {O, F}
    prefix, suffix = array_prefix(F), array_suffix(F)
    haskey(ps.systems_dict, F)      ? @set(ps.systems_dict[F] = set(ps.systems_dict[F], optic.outer, val)) :
    haskey(ps.systems_dict, prefix) ? @set(ps.systems_dict[prefix][suffix] =
                                           set(ps.systems_dict[prefix][suffix], optic.outer, val)) :
                                      @invoke(set(ps::Any, optic, val))
end

function (Accessors.set(ps::PreSystem, optic::PropertyLens{F}, val)::PreSystem) where F
    haskey(ps.parameters_dict, F) ? @set(ps.defaults[ps.parameters_dict[F]] = val) :
                                    @invoke(set(ps::Any, optic, val))
end


function MTK.System(ps::PreSystem)
    mix_systems = []  # keeps Vector{System} as is
    systems = []
    for (k, v) in ps.systems_dict
        if v isa Vector
            sys_arr = System.(MTK.rename(v, k))
            push!(mix_systems, sys_arr)
            push!(systems, sys_arr...)
        else
            sys = System(MTK.rename(v, k))
            push!(mix_systems, sys)
            push!(systems, sys)
        end
    end
    System(MTK.flatten_equations(ps.equations_fn(mix_systems...)), ps.t,
           values(ps.variables_dict),
           values(ps.parameters_dict);
           ps.name, ps.description, systems,
           ps.gui_metadata, ps.continuous_events, ps.discrete_events, ps.defaults, ps.costs,
           ps.constraints, ps.consolidate)
end
Base.convert(::Type{MTK.AbstractSystem}, ps::PreSystem) = MTK.System(ps)
Base.convert(::Type{MTK.System}, ps::PreSystem) = MTK.System(ps)

MTK.mtkcompile(ps::MTKButter.PreSystem) = MTK.mtkcompile(System(ps))

function _model_macro(mod, fullname::Union{Expr, Symbol}, expr, isconnector)
    # A copy of MTK's _model_macro. Changes:
    #   - Special-case parse_components
    #   - equations becomes equations_fn
    #   -
    if fullname isa Symbol
        name, type = fullname, :($MTKButter.PreSystem)
    else
        if fullname.head == :(::)
            name, type = fullname.args
        else
            error("`$fullname` is not a valid name.")
        end
    end
    exprs = Expr(:block)
    dict = Dict{Symbol, Any}(
        :defaults => Dict{Symbol, Any}(),
        :kwargs => Dict{Symbol, Dict}(),
        :structural_parameters => Dict{Symbol, Dict}()
    )
    comps = Symbol[]   # was Union{Expr, Symbol} in MTK, but I don't know how that'd happen!
    ext = []
    eqs = Expr[]
    icon = Ref{Union{String, MTK.URI}}()
    ps, sps, vs, = [], [], []
    c_evts = []
    d_evts = []
    cons = []
    costs = []
    kwargs = OrderedCollections.OrderedSet()
    where_types = Union{Symbol, Expr}[]

    push!(exprs.args, :(variables = []))
    push!(exprs.args, :(parameters = []))
    # We build `System` by default
    push!(exprs.args, :(systems_dict = $MTKButter.OrderedDict{Symbol, Any}()))
    push!(exprs.args, :(defaults = Dict{Num, Union{Number, Symbol, Function}}()))

    Base.remove_linenums!(expr)
    for arg in expr.args
        if arg.head == :macrocall
            if arg.args[1] == Symbol("@components")
                parse_components!(exprs.args, comps, dict, arg.args[end], kwargs)
            else
                MTK.parse_model!(exprs.args, comps, ext, eqs, icon, vs, ps,
                                 sps, c_evts, d_evts, cons, costs, dict, mod, arg, kwargs, where_types)
            end
        elseif arg.head == :block
            push!(exprs.args, arg)
        elseif arg.head == :if
            MLStyle.@match arg begin
                Expr(:if, condition, x) => begin
                    parse_conditional_model_statements(comps, dict, eqs, exprs, kwargs,
                        mod, ps, vs, where_types,
                        parse_top_level_branch(condition, x.args)...)
                end
                Expr(:if, condition, x, y) => begin
                    parse_conditional_model_statements(comps, dict, eqs, exprs, kwargs,
                        mod, ps, vs, where_types,
                        parse_top_level_branch(condition, x.args, y)...)
                end
                _ => error("Got an invalid argument: $arg")
            end
        elseif isconnector
            # Connectors can have variables listed without `@variables` prefix or
            # begin block.
            MTK.parse_variable_arg!(
                exprs.args, vs, dict, mod, arg, :variables, kwargs, where_types)
        else
            error("$arg is not valid syntax. Expected a macro call.")
        end
    end

    iv = get(dict, :independent_variable, nothing)
    if iv === nothing
        iv = dict[:independent_variable] = MTK.get_t(mod, :t)
    end

    push!(exprs.args, :(equations_fn =
        $(components_closure(comps, :(Union{$MTK.Equation, Vector{$MTK.Equation}}[$(eqs...)])))))
    push!(exprs.args, :(push!(parameters, $(ps...))))
    push!(exprs.args, :(push!(variables, $(vs...))))

    gui_metadata = isassigned(icon) > 0 ? MTK.GUIMetadata(GlobalRef(mod, name), icon[]) :
                   MTK.GUIMetadata(GlobalRef(mod, name))

    consolidate = get(dict, :consolidate, MTK.default_consolidate)
    description = get(dict, :description, "")

    @inline MTK.pop_structure_dict!.(
        Ref(dict), [:defaults, :kwargs, :structural_parameters])

    sys = :($type(equations_fn, $iv, variables, parameters;
        name, description = $description, systems_dict, gui_metadata = $gui_metadata,
        continuous_events = [$(c_evts...)], discrete_events = [$(d_evts...)],
        defaults, costs = [$(costs...)], constraints = [$(cons...)], consolidate = $consolidate))

    if length(ext) == 0
        push!(exprs.args, :(var"#___sys___" = $sys))
    else
        push!(exprs.args, :(var"#___sys___" = $extend($sys, [$(ext...)])))
    end

    isconnector && push!(exprs.args,
        :($Setfield.@set!(var"#___sys___".connector_type=$connector_type(var"#___sys___"))))

    f = if length(where_types) == 0
        :($(Symbol(:__, name, :__))(; name, $(kwargs...)) = $exprs)
    else
        f_with_where = Expr(:where)
        push!(f_with_where.args,
            :($(Symbol(:__, name, :__))(; name, $(kwargs...))), where_types...)
        :($f_with_where = $exprs)
    end

    :($name = $MTK.Model($f, $dict, $isconnector))
end

""" Returns an Expr that defines an anonymous function accepting the components, in order. """
function components_closure(comps::Vector{Symbol}, expr)
    # Since we don't parse the RHS of the @components equations,
    # we have to "guess" that when `some_comp_1` appears and
    # `some_comp` is a LHS in the @components block, then
    # `some_comp` is likely an array. So we transform `some_comp_1`
    # into `some_comp[1]`
    comp_dict = Dict(Symbol(c, :_, n) => :($c[$n]) for c in comps
                     for n in 1:100)  # lazy and inefficient, but works for now
    expr2 = postwalk(expr) do x
        x isa Symbol ? get(comp_dict, x, x) : x
    end
    :(function ($(comps...),)
          $expr2
      end)
end

function parse_components!(exprs, cs, dict, compbody, kwargs)
    dict[:components] = []
    Base.remove_linenums!(compbody)
    for arg in compbody.args
        MLStyle.@match arg begin
            Expr(:(=), lhs, _) => begin
                push!(cs, lhs)
                # push!(dict[:components], comps...)  # TODO
                push!(exprs, arg)
                push!(exprs, :(systems_dict[$(Expr(:quote, lhs))] = $lhs))
            end
            _ => error("Expression not handled (yet) - please file issue. ", arg)
        end
    end
end

macro mtkbmodel(fullname::Union{Expr, Symbol}, body)
    esc(MTKButter._model_macro(__module__, fullname, body, false))
end
