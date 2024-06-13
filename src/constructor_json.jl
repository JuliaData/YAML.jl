# Constructors for the JSON schema.

construct_undefined_json_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' in the JSON schema", node.start_mark))

const construct_json_schema_str = construct_failsafe_schema_str

const construct_json_schema_seq = construct_failsafe_schema_seq

const construct_json_schema_map = construct_failsafe_schema_map

function construct_json_schema_null(constructor::Constructor, node::Node)::Nothing
    str = construct_scalar(constructor, node)
    str == "null" ? nothing :
    throw(ConstructorError("could not construct a null '$str' in the JSON schema", node.start_mark))
end

function tryparse_json_schema_bool(str::String)::Union{Bool, Nothing}
    str == "true"  ? true  :
    str == "false" ? false :
    nothing
end

function construct_json_schema_bool(constructor::Constructor, node::Node)::Bool
    str = construct_scalar(constructor, node)
    b = tryparse_json_schema_bool(str)
    b !== nothing ? b :
    throw(ConstructorError("could not construct a bool '$str' in the JSON schema", node.start_mark))
end

function tryparse_json_schema_int(str::String)::Union{Int, Nothing}
    len = length(str)
    if len > 1
        if str[1] == '+'
            # plus sign
            nothing
        elseif str[1] == '0'
            # leading zero
            nothing
        elseif len > 2 && str[1] == '-' && str[2] == '0'
            # minus sign + leading zero
            nothing
        else
            # decimal
            tryparse(Int, str, base=10)
        end
    else
        # decimal
        tryparse(Int, str, base=10)
    end
end

function construct_json_schema_int(constructor::Constructor, node::Node)::Int
    str = construct_scalar(constructor, node)
    n = tryparse_json_schema_int(str)
    n !== nothing ? n :
    throw(ConstructorError("could not construct an int '$str' in the JSON schema", node.start_mark))
end

function tryparse_json_schema_float(str::String)::Union{Float64, Nothing}
    len = length(str)
    x = if len > 1
        if str[1] == '+'
            # plus sign
            nothing
        elseif str[1] == '0'
            # leading zero
            nothing
        elseif len > 2 && str[1] == '-' && str[3] == '0'
            # minus sign + leading zero
            nothing
        else
            # fixed or exponential
            tryparse(Float64, str)
        end
    else
        # fixed or exponential
        tryparse(Float64, str)
    end
    x !== nothing && isfinite(x) ? x :
    nothing
end

function construct_json_schema_float(construct::Constructor, node::Node)::Float64
    str = construct_scalar(constructor, node)
    x = tryparse_json_schema_float(str)
    x !== nothing ? x :
    throw(ConstructorError("could not construct a float '$str' in the JSON schema", node.start_mark))
end

const json_schema_constructors = Dict{Union{String, Nothing}, Function}(
    nothing                   => construct_undefined_json_schema,
    "tag:yaml.org,2002:str"   => construct_json_schema_str,
    "tag:yaml.org,2002:seq"   => construct_json_schema_seq,
    "tag:yaml.org,2002:map"   => construct_json_schema_map,
    "tag:yaml.org,2002:null"  => construct_json_schema_null,
    "tag:yaml.org,2002:bool"  => construct_json_schema_bool,
    "tag:yaml.org,2002:int"   => construct_json_schema_int,
    "tag:yaml.org,2002:float" => construct_json_schema_float,
)
