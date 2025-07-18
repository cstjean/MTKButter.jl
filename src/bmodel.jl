export mtkbmodel

macro mtkbmodel(fullname::Union{Expr, Symbol}, body)
    esc(MTK._model_macro(__module__, fullname, body, false))
end
