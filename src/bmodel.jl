export mtkbmodel

struct PreSystem
    equations_fn::Function
    t
    variables
    parameters
    name
    description
    systems_dict
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
    return PreSystem(equations_fn, t, variables, parameters,
                     name, description, systems_dict, gui_metadata, continuous_events, discrete_events, defaults, costs,
                     constraints, consolidate)
end
MTK.rename(ps::PreSystem, name::Symbol) = @set ps.name = name

function Base.show(io::IO, mime::MIME"text/plain", ps::PreSystem)
    println(io, "--- PreSystem for ---")
    show(io, mime, System(ps))
end

Base.getproperty(ps::PreSystem, prop::Symbol) =
    hasfield(PreSystem, prop) ? getfield(ps, prop) :
    getproperty(System(ps), prop)  # inefficient, but it's OK!

function MTK.System(ps::PreSystem)
    mix_systems = []  # keeps Vector{System} as is
    systems = []
    for (k, v) in ps.systems_dict
        if v isa Vector
            sys_arr = System[MTK.rename(ps, Symbol(k, :_, i))
                             for (i, ps) in enumerate(v)]
            push!(mix_systems, sys_arr)
            push!(systems, sys_arr...)
        else
            sys = System(MTK.rename(v, k))
            push!(mix_systems, sys)
            push!(systems, sys)
        end
    end
    System(MTK.flatten_equations(ps.equations_fn(mix_systems...)), ps.t, ps.variables, ps.parameters;
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
    comps = Union{Symbol, Expr}[]
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
    push!(exprs.args, :(systems_dict = $MTKButter.OrderedDict()))
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

function components_closure(comps, expr)
    :(function ($(comps...),)
          $expr
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
