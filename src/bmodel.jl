export mtkbmodel

function _model_macro(mod, fullname::Union{Expr, Symbol}, expr, isconnector)
    # A complete copy of MTK's _model_macro
    if fullname isa Symbol
        name, type = fullname, :System
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
    push!(exprs.args, :(systems = ModelingToolkit.AbstractSystem[]))
    push!(exprs.args, :(equations = Union{Equation, Vector{Equation}}[]))
    push!(exprs.args, :(defaults = Dict{Num, Union{Number, Symbol, Function}}()))

    Base.remove_linenums!(expr)
    for arg in expr.args
        if arg.head == :macrocall
            MTK.parse_model!(exprs.args, comps, ext, eqs, icon, vs, ps,
                sps, c_evts, d_evts, cons, costs, dict, mod, arg, kwargs, where_types)
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

    push!(exprs.args, :(push!(equations, $(eqs...))))
    push!(exprs.args, :(push!(parameters, $(ps...))))
    push!(exprs.args, :(push!(systems, $(comps...))))
    push!(exprs.args, :(push!(variables, $(vs...))))

    gui_metadata = isassigned(icon) > 0 ? MTK.GUIMetadata(GlobalRef(mod, name), icon[]) :
                   MTK.GUIMetadata(GlobalRef(mod, name))

    consolidate = get(dict, :consolidate, MTK.default_consolidate)
    description = get(dict, :description, "")

    @inline MTK.pop_structure_dict!.(
        Ref(dict), [:defaults, :kwargs, :structural_parameters])

    sys = :($type($(MTK.flatten_equations)(equations), $iv, variables, parameters;
        name, description = $description, systems, gui_metadata = $gui_metadata,
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

macro mtkbmodel(fullname::Union{Expr, Symbol}, body)
    esc(MTKButter._model_macro(__module__, fullname, body, false))
end
