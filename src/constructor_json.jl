# Constructors for the JSON schema.

# Parsing utils

struct JSONSchemaParseError <: Exception end

function tryparse_json_schema_null(str::String)::Union{Nothing, JSONSchemaParseError}
    str == "null" ? nothing :
    JSONSchemaParseError()
end

function tryparse_json_schema_bool(str::String)::Union{Bool, JSONSchemaParseError}
    str == "true"  ? true  :
    str == "false" ? false :
    JSONSchemaParseError()
end

function tryparse_json_schema_int(str::String)::Union{Int, JSONSchemaParseError}
    len = length(str)
    if len ≥ 2
        if str[1] == '+'
            # plus sign
            return JSONSchemaParseError()
        elseif str[1] == '0'
            # leading zero
            return JSONSchemaParseError()
        elseif len > 2 && str[1] == '-' && str[2] == '0'
            # minus sign + leading zero
            return JSONSchemaParseError() 
        end
    end
    # decimal
    n = tryparse(Int, str, base=10)
    n === nothing && return JSONSchemaParseError()
    n
end

function tryparse_json_schema_float(str::String)::Union{Float64, JSONSchemaParseError}
    len = length(str)
    # plus sign
    len ≥ 1 && str[1] == '+' && return JSONSchemaParseError()
    # leading dot
    len ≥ 1 && str[1] == '.' && return JSONSchemaParseError()
    # minus sign + leading dot
    len ≥ 2 && str[1] == '-' && str[2] == '.' && return JSONSchemaParseError()
    # leading zero
    len ≥ 2 && str[1] == '0' && str[2] ≠ '.' && return JSONSchemaParseError()
    # minus sign + leading zero
    len ≥ 3 && str[1] == '-' && str[2] == '0' && str[3] ≠ '.' && return JSONSchemaParseError()
    # fixed or exponential
    x = tryparse(Float64, str)
    x === nothing && return JSONSchemaParseError()
    !isfinite(x) && return JSONSchemaParseError()
    x
end

# Construct functions

construct_undefined_json_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' in the JSON schema", node.start_mark))

const construct_json_schema_str = construct_failsafe_schema_str

const construct_json_schema_seq = construct_failsafe_schema_seq

const construct_json_schema_map = construct_failsafe_schema_map

function construct_json_schema_null(constructor::Constructor, node::Node)::Nothing
    str = construct_scalar(constructor, node)
    n = tryparse_json_schema_null(str)
    n isa JSONSchemaParseError &&
    throw(ConstructorError("could not construct a null '$str' in the JSON schema", node.start_mark))
    n
end

function construct_json_schema_bool(constructor::Constructor, node::Node)::Bool
    str = construct_scalar(constructor, node)
    b = tryparse_json_schema_bool(str)
    b isa JSONSchemaParseError &&
    throw(ConstructorError("could not construct a bool '$str' in the JSON schema", node.start_mark))
    b
end

function construct_json_schema_int(constructor::Constructor, node::Node)::Int
    str = construct_scalar(constructor, node)
    n = tryparse_json_schema_int(str)
    n isa JSONSchemaParseError &&
    throw(ConstructorError("could not construct an int '$str' in the JSON schema", node.start_mark))
    n
end

function construct_json_schema_float(construct::Constructor, node::Node)::Float64
    str = construct_scalar(constructor, node)
    x = tryparse_json_schema_float(str)
    x isa JSONSchemaParseError &&
    throw(ConstructorError("could not construct a float '$str' in the JSON schema", node.start_mark))
    x
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
